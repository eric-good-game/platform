# Contratos de eventos

Documento 6 de la Fase 1. Define cómo es cada mensaje que viaja entre los sistemas: el sobre estándar, las convenciones, el versionado, el formato de los esquemas y el catálogo de eventos de la Fase 1 (Inventory). Es agnóstico de tecnología: no dice por dónde viajan los mensajes (eso lo cubre el documento de infraestructura).

Estado: **borrador para revisión**.

## 1. Principios

- Un **evento** cuenta algo que **ya ocurrió** (`stock.reserved`). Quien lo publica no sabe quién lo recibirá ni espera respuesta. No se usan comandos entre sistemas: pedir algo a otro sistema crearía una dependencia que rompe la regla de que la integración es opcional.
- Cada evento tiene **un solo dueño**: el servicio que lo publica. Solo él define y cambia su contrato.
- Los contratos viven en un **repositorio aparte**. Es lo único que se comparte entre sistemas; ninguno depende del código de otro.
- Los eventos son **autosuficientes**: llevan los datos que sus consumidores necesitan, para que no tengan que llamar de vuelta al publicador. Los eventos "delgados" (solo identificadores, con consulta posterior) quedan para casos puntuales justificados, y están fuera de alcance por ahora (ver sección 9).
- Un evento publicado es **inmutable**: no se edita ni se retira. Un error se corrige con un evento posterior.

## 2. El sobre

Todos los eventos usan el mismo sobre; lo que cambia es el `payload`.

```json
{
  "id": "0192f5a1-3c4d-7e2b-8a10-6f3d9c1b2a47",
  "type": "stock.reserved",
  "version": 1,
  "occurredAt": "2026-10-17T19:51:00Z",
  "source": "inventory",
  "correlationId": "0192f5a0-9b11-7c3e-9f20-1a2b3c4d5e6f",
  "causationId": "0192f5a1-1111-7aaa-8b22-0c1d2e3f4a5b",
  "payload": { }
}
```

| Campo | Obligatorio | Descripción |
|---|:-:|---|
| `id` | sí | Identificador único del evento (UUID v7). Los consumidores lo usan para reconocer eventos repetidos. |
| `type` | sí | Nombre del evento (`<recurso>.<evento>`). Es también la etiqueta con la que se enruta. |
| `version` | sí | Versión del esquema del `payload`, entero (`1`, `2`...). |
| `occurredAt` | sí | Momento en que ocurrió el hecho (no el de publicación), ISO 8601 en UTC. |
| `source` | sí | Servicio que publica el evento (`inventory`, `store`, `tickets`, `identity`). |
| `correlationId` | sí | Identifica toda una cadena de eventos y peticiones relacionadas (por ejemplo, todo lo que deriva de un pedido). |
| `causationId` | no | `id` del evento que provocó este. Vacío si lo originó una acción directa (una petición de un usuario). |
| `payload` | sí | Datos del evento, según el esquema de su `type` y `version`. |

Reglas de trazabilidad:

- Quien inicia una cadena genera el `correlationId` (UUID v7). Puede reutilizar el identificador de la petición que la originó.
- Un servicio que publica un evento **como consecuencia** de otro copia su `correlationId` y pone en `causationId` el `id` del evento recibido.

## 3. Convenciones

Las mismas que las APIs del portafolio, más las propias de eventos.

| Tema | Regla |
|---|---|
| Nombre del evento | `<recurso>.<evento>` en minúsculas, en inglés y con el verbo en pasado (`order.paid`, `ticket.created`). Excepción aceptada: `stock.low`, que significa "el stock cayó por debajo del mínimo". |
| Nombres de campos | `camelCase`. |
| Fechas con hora | ISO 8601 en UTC (`2026-10-17T19:51:00Z`). |
| Identificadores | UUID v7 como texto. |
| Enumeraciones | Minúsculas (`entry`, `exit`). Los códigos de motivo (por ejemplo, de un fallo) usan `MAYUSCULAS_CON_GUION_BAJO`, como los `code` de error de las APIs. |
| Cantidades | Números. La unidad se indica en un campo aparte. |
| Campos opcionales | Se omiten cuando no tienen valor, en vez de enviarlos como `null`. |
| Datos personales | Solo los que algún consumidor necesita. Nunca contraseñas, hashes, tokens ni datos de tarjeta. |

## 4. Versionado

El `version` del sobre identifica el esquema del `payload`. Hay un esquema por evento y por versión.

| Tipo de cambio | Ejemplos | ¿Sube la versión? |
|---|---|:-:|
| **Compatible** | Añadir un campo opcional; añadir un valor a una enumeración que los consumidores ya tratan como "desconocido" | No |
| **Incompatible** | Quitar o renombrar un campo; cambiar su tipo o su significado; hacer obligatorio un campo que era opcional | Sí |

Reglas:

- Los **consumidores ignoran los campos que no conocen**. Eso es lo que hace posibles los cambios compatibles sin coordinar a nadie.
- Ante un cambio incompatible, el publicador emite **ambas versiones** durante una transición. Una versión se retira cuando el catálogo ya no registra consumidores de ella.
- El catálogo (sección 7) indica qué sistemas consumen cada evento y versión.
- Si un consumidor recibe un `type` o una `version` que no soporta, **lo ignora y lo registra en el log**; no falla ni bloquea a los demás.
- Durante una transición se publican ambas versiones del mismo hecho. Un consumidor procesa **una sola versión** de cada `type` (la que soporta) y descarta las demás, o contaría el mismo hecho dos veces.

## 5. Esquemas

Cada evento y versión tiene su **esquema JSON Schema** y un ejemplo en el repositorio de contratos. Hay además un esquema del sobre.

```text
event-contracts/
├── envelope/
│   └── v1.schema.json
├── events/
│   ├── stock.adjusted/
│   │   ├── v1.schema.json
│   │   └── v1.example.json
│   ├── stock.low/
│   ├── stock.reserved/
│   └── stock.failed/
└── catalog.md
```

- Los esquemas del `payload` son **estrictos** (no admiten campos no definidos) para que el publicador detecte sus errores en los tests.
- Los consumidores **no** rechazan por campos de más: validan solo lo que usan.
- Un cambio en un esquema se revisa junto con el ejemplo y con el catálogo.
- Un documento AsyncAPI que describa todos los eventos queda para más adelante, cuando haya varios sistemas publicando (ver sección 9).

## 6. Reglas para publicadores y consumidores

### Publicadores

- Publican mediante el patrón **outbox**: el evento se guarda en la misma transacción que el cambio de datos que lo origina y un proceso aparte lo publica. Así un evento nunca se pierde ni se publica sin que el cambio exista (el detalle está en el documento de infraestructura).
- Validan sus eventos contra el esquema en los tests.
- Incluyen en el `payload` lo que sus consumidores necesitan, y nada más.

### Consumidores

- La entrega es **al menos una vez**: un mismo evento puede llegar repetido. El consumidor debe ser **idempotente** y reconocer los repetidos por su `id`.
- El **orden no está garantizado** entre eventos. Los consumidores no asumen que un evento llega antes que otro; por eso los eventos llevan el estado resultante (por ejemplo, `quantityAfter`) y no solo diferencias.
- Si un evento no se puede procesar tras los reintentos, va a una cola de mensajes fallidos (ver documento de infraestructura).

## 7. Catálogo de la Fase 1: eventos de Inventory

Los eventos que Inventory **consume** (`order.paid`, `order.cancelled`) pertenecen a Store y se definen en su fase. Aquí solo se definen los que Inventory **publica**.

| Evento | Versión | Publica | Lo consumirán |
|---|:-:|---|---|
| `stock.adjusted` | 1 | Inventory | Reports |
| `stock.low` | 1 | Inventory | n8n (alerta y reposición), Notifications |
| `stock.reserved` | 1 | Inventory | Store |
| `stock.failed` | 1 | Inventory | Store |

### 7.1 `stock.adjusted`

El stock de un producto cambió por un movimiento (entrada, salida o ajuste). Se publica **un evento por movimiento**.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|:-:|---|
| `movementId` | UUID | sí | Movimiento que originó el cambio. |
| `movementType` | enumeración | sí | `entry`, `exit` o `adjustment`. |
| `productId` | UUID | sí | |
| `sku` | texto | sí | |
| `productName` | texto | sí | |
| `unit` | texto | sí | Unidad de medida (por ejemplo, `piece`, `kg`). |
| `quantityChange` | número | sí | Cambio con signo: positivo aumenta el stock, negativo lo reduce. |
| `quantityAfter` | número | sí | Stock total del producto tras el movimiento. |
| `reason` | texto | no | Motivo indicado en el movimiento. |
| `performedBy` | UUID | no | Usuario que registró el movimiento (el `id` de Identity). Vacío si lo originó el sistema. |

```json
{
  "id": "0192f5a1-3c4d-7e2b-8a10-6f3d9c1b2a47",
  "type": "stock.adjusted",
  "version": 1,
  "occurredAt": "2026-10-17T19:51:00Z",
  "source": "inventory",
  "correlationId": "0192f5a1-3c4d-7e2b-8a10-6f3d9c1b2a47",
  "payload": {
    "movementId": "0192f5a1-2b3c-7d4e-9f50-7a8b9c0d1e2f",
    "movementType": "exit",
    "productId": "0192f3c4-7a1e-7b3d-9c2a-5e8f1a2b3c4d",
    "sku": "TOR-001",
    "productName": "Tornillo 5mm",
    "unit": "piece",
    "quantityChange": -6,
    "quantityAfter": 4,
    "performedBy": "0192f3c4-0000-7a1b-9c2d-3e4f5a6b7c8d"
  }
}
```

### 7.2 `stock.low`

El stock de un producto cayó por debajo de su umbral mínimo.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|:-:|---|
| `productId` | UUID | sí | |
| `sku` | texto | sí | |
| `productName` | texto | sí | |
| `unit` | texto | sí | |
| `quantity` | número | sí | Stock del producto tras el movimiento. |
| `minimumThreshold` | número | sí | Umbral mínimo configurado para el producto. |

```json
{
  "id": "0192f5a1-3d00-7f11-8b20-2c3d4e5f6a7b",
  "type": "stock.low",
  "version": 1,
  "occurredAt": "2026-10-17T19:51:00Z",
  "source": "inventory",
  "correlationId": "0192f5a1-3c4d-7e2b-8a10-6f3d9c1b2a47",
  "causationId": "0192f5a1-3c4d-7e2b-8a10-6f3d9c1b2a47",
  "payload": {
    "productId": "0192f3c4-7a1e-7b3d-9c2a-5e8f1a2b3c4d",
    "sku": "TOR-001",
    "productName": "Tornillo 5mm",
    "unit": "piece",
    "quantity": 4,
    "minimumThreshold": 10
  }
}
```

Regla de publicación: se emite **una vez al cruzar el umbral hacia abajo** (de `quantity >= minimumThreshold` a `quantity < minimumThreshold`), no en cada movimiento mientras el stock siga bajo el mínimo. Vuelve a poder emitirse cuando el stock regrese al umbral o por encima y caiga de nuevo.

### 7.3 `stock.reserved`

Se apartó stock para una solicitud (una reserva) con éxito.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|:-:|---|
| `reservationId` | UUID | sí | Identificador de la reserva en Inventory. |
| `reference` | texto | no | Referencia opaca que envió quien pidió la reserva (por ejemplo, el identificador de un pedido). Inventory la devuelve sin interpretarla: no conoce pedidos. |
| `items` | lista | sí | Lo reservado (mínimo un elemento). |
| `items[].productId` | UUID | sí | |
| `items[].sku` | texto | sí | |
| `items[].quantity` | número | sí | Cantidad reservada. |
| `expiresAt` | fecha y hora | sí | Cuándo expira la reserva si no se confirma. |

```json
{
  "id": "0192f5a2-4a00-7b12-9c30-3d4e5f6a7b8c",
  "type": "stock.reserved",
  "version": 1,
  "occurredAt": "2026-10-17T19:55:00Z",
  "source": "inventory",
  "correlationId": "0192f5a0-9b11-7c3e-9f20-1a2b3c4d5e6f",
  "causationId": "0192f5a1-8800-7aaa-8b22-0c1d2e3f4a5b",
  "payload": {
    "reservationId": "0192f5a2-3f00-7c10-8d20-4e5f6a7b8c9d",
    "reference": "order-1042",
    "items": [
      {
        "productId": "0192f3c4-7a1e-7b3d-9c2a-5e8f1a2b3c4d",
        "sku": "TOR-001",
        "quantity": 2
      }
    ],
    "expiresAt": "2026-10-17T20:10:00Z"
  }
}
```

### 7.4 `stock.failed`

No se pudo reservar el stock solicitado. Se reserva **todo o nada**: si algún elemento no se puede apartar, no se aparta ninguno, y `items` lista los elementos que fallaron.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|:-:|---|
| `reference` | texto | no | Misma referencia opaca de la solicitud. |
| `items` | lista | sí | Elementos que no se pudieron reservar (mínimo uno). |
| `items[].productId` | UUID | sí | |
| `items[].sku` | texto | no | Ausente si el producto no existe. |
| `items[].requestedQuantity` | número | sí | Cantidad pedida. |
| `items[].availableQuantity` | número | sí | Cantidad disponible en ese momento (`0` si no existe). |
| `items[].reason` | enumeración | sí | `INSUFFICIENT_STOCK` o `PRODUCT_NOT_FOUND`. |

```json
{
  "id": "0192f5a2-5b00-7d13-9e40-4e5f6a7b8c9d",
  "type": "stock.failed",
  "version": 1,
  "occurredAt": "2026-10-17T19:56:00Z",
  "source": "inventory",
  "correlationId": "0192f5a0-9b11-7c3e-9f20-1a2b3c4d5e6f",
  "causationId": "0192f5a1-8801-7aaa-8b22-0c1d2e3f4a5b",
  "payload": {
    "reference": "order-1043",
    "items": [
      {
        "productId": "0192f3c4-7a1e-7b3d-9c2a-5e8f1a2b3c4d",
        "sku": "TOR-001",
        "requestedQuantity": 20,
        "availableQuantity": 4,
        "reason": "INSUFFICIENT_STOCK"
      }
    ]
  }
}
```

### Preguntas que se resuelven en la fase de Inventory

Los esquemas anteriores parten de supuestos que se confirman al diseñar Inventory. Un cambio incompatible sube la versión, así que es barato corregirlos ahora.

- **Stock reservado:** hay que decidir si `stock.low` y `availableQuantity` descuentan lo reservado o miden solo el stock físico.

## 8. Eventos futuros (no definidos todavía)

Los contratos de estos eventos se escriben cuando se llegue a la fase de su publicador.

| Evento | Publica | Fase |
|---|---|---|
| `order.paid`, `order.cancelled`, `order.refunded`, `payment.failed` | Store | Store |
| `ticket.created`, `ticket.resolved` | Tickets | Tickets |
| `user.disabled` | Identity | Mejora futura (ver documento de flujo de autenticación) |

## 9. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Todo evento incluye los campos obligatorios del sobre. | El evento valida contra el esquema del sobre. |
| 2 | `id` es único por evento y es un UUID v7. | Dos eventos nunca comparten `id`; el `id` tiene versión 7. |
| 3 | `type` y `version` identifican un único esquema de `payload`. | Cada combinación del catálogo tiene un archivo de esquema. |
| 4 | Todo `payload` publicado valida contra su esquema. | Los tests del publicador validan cada evento contra el esquema. |
| 5 | Procesar dos veces el mismo evento no duplica efectos. | Entregar el mismo `id` dos veces a un consumidor deja el mismo resultado que una vez. |
| 6 | Un consumidor tolera campos nuevos. | Añadir un campo extra al ejemplo no rompe a ningún consumidor. |
| 7 | Un cambio incompatible mantiene ambas versiones durante la transición. | Mientras el catálogo registre consumidores de la versión anterior, esta se sigue publicando. |
| 8 | Las fechas con hora van en UTC. | Todo campo de fecha con hora termina en `Z`. |
| 9 | Los eventos derivados conservan la trazabilidad. | Un evento publicado como consecuencia de otro copia su `correlationId` y pone en `causationId` el `id` recibido. |
| 10 | Ningún evento lleva contraseñas, hashes, tokens ni datos de tarjeta. | Revisión de los esquemas: ningún campo de ese tipo. |
| 11 | Un consumidor ignora y registra un `type` o una `version` que no soporta. | Entregar un evento desconocido no produce error ni afecta a otros mensajes. |
| 12 | `stock.low` se publica una sola vez por cruce del umbral. | Dos salidas seguidas bajo el mínimo producen un solo `stock.low`. |
| 13 | `quantityAfter` refleja el stock real tras el movimiento y nunca es negativo. | Tras registrar una salida, `quantityAfter` coincide con el stock consultado. |
| 14 | Una reserva es todo o nada. | Con un elemento sin stock suficiente se publica `stock.failed` y no se aparta stock de los demás. |
| 15 | Un consumidor procesa cada hecho una sola vez aunque se publiquen dos versiones. | Con las versiones 1 y 2 del mismo evento en transición, un consumidor de la versión 2 ignora la versión 1. |

Cuándo se prueban: las invariantes 1, 2, 3, 8 y 10 se comprueban en la Fase 1 con la validación de esquemas y ejemplos del repositorio de contratos. Las invariantes 4 a 7, 9 y 11 a 15 dependen de publicadores y consumidores reales y se prueban desde la Fase 2 (Inventory publica; Store consume).

## 10. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Eventos entre sistemas, sin comandos | Comandos entre sistemas | Los comandos acoplan a quien los envía con quien los atiende; los eventos mantienen la integración opcional. |
| Eventos autosuficientes | Eventos "delgados" con consultas al publicador | Sin dependencia del publicador, sin autenticación entre servicios (Identity no tiene cuentas de servicio) y con el dato correcto a la hora del evento. |
| Sobre con `source` y `causationId` además de los campos del plan | Sobre mínimo del plan | Permiten saber quién publicó y reconstruir cadenas (`order.paid` → `stock.reserved`). |
| `version` entera en el sobre; cambios compatibles sin subir versión | Versión en el nombre del evento (`stock.reserved.v2`) | Mantiene limpio el catálogo y las etiquetas de enrutamiento. |
| Ambas versiones durante la transición | Cambio con corte inmediato | Los consumidores migran a su ritmo, sin coordinar despliegues. |
| Esquema JSON Schema por evento y versión | Solo documentación en texto | Se puede validar de forma automática en tests. |
| Esquemas estrictos para quien publica, consumidores tolerantes | Esquemas estrictos también al consumir | Los consumidores no se rompen con campos nuevos. |
| Sin campos de almacén en los eventos de Inventory (un solo almacén) | Incluir `warehouseId` desde el inicio | El sistema tiene un solo almacén; los campos se añaden cuando haya varios (cambio compatible). |
| `quantity` y `quantityAfter` son el stock **total** del producto | Stock por almacén | Conserva su significado si algún día hay varios almacenes: solo se añadirían campos opcionales. |
| `reference` opaca en las reservas | Que Inventory conozca el identificador de pedido | Inventory no depende de Store ni sabe qué es un pedido. |
| Reserva todo o nada | Reservas parciales | Simplifica la saga de Store: o se confirma el pedido o se cancela. |
| Nombres de la arquitectura (`stock.failed`, `stock.low`) | Renombrar a `stock.reservation_failed` y similares | Se respetan los nombres ya definidos en el plan. |

## 11. Fuera de alcance (por ahora)

- Varios almacenes y transferencias entre almacenes. Añadirlos solo requeriría campos opcionales nuevos en los eventos (`warehouseId`, `warehouseName`), un cambio compatible que no sube la versión.
- Eventos "delgados" (solo identificadores, con consulta posterior al publicador) para datos sensibles o muy grandes. Requieren cuentas de servicio en Identity.
- Documento AsyncAPI que catalogue todos los eventos, canales y operaciones.
- Registro centralizado de esquemas (*schema registry*) con validación en tiempo de ejecución.
- Firma o cifrado de los eventos.
- Garantía de orden entre eventos.
- Eventos de Identity (por ejemplo, `user.disabled`).
- Contratos de los eventos de Store y Tickets (se definen en sus fases).
- Publicar el catálogo como documentación navegable.
