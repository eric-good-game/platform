# Portafolio backend empresarial + fullstack

Plan de arquitectura y alcance del MVP para tres sistemas independientes (Inventory, Tickets y Store) apoyados en microservicios compartidos.

Este documento es la **visión general**. El detalle de la Fase 1 está en los documentos 1 a 9 (ver `01-vision-and-scope.md`); cuando hay diferencias, mandan esos documentos.

## 1. Objetivo y principios

Construir tres sistemas sólidos que puedan probarse **cada uno por separado**, pero que se comuniquen de forma fluida cuando se ejecutan juntos. No es un sistema gigante: es una plataforma compartida más productos autónomos.

Reglas de diseño:

1. **Cada sistema es dueño de sus datos.** Tiene su propia base de datos y nadie lee la base de otro.
2. **La integración es opcional.** Los sistemas se comunican por eventos asíncronos; si el otro sistema no está, el evento simplemente no tiene suscriptor y nada se rompe.
3. **Cada sistema solo depende de la plataforma** (Identity, broker), nunca de otro sistema principal.
4. **Los contratos de eventos viven en un repositorio aparte.** Es lo único que se comparte entre sistemas; ninguno depende del código de otro.
5. **Primero se documenta, luego se implementa.**
6. **El diseño de cada servicio es proporcional a su complejidad.** El DDD estratégico se aplica siempre; los patrones tácticos, según las invariantes que proteja cada servicio.

## 2. Mapa de tecnologías

| Pieza | Tecnología | Rol |
|---|---|---|
| Identity | NestJS | Usuarios, roles, empleados, emisión de JWT |
| Reports | Python (FastAPI, pandas) | Reportes, exportaciones, predicciones |
| Notifications | NestJS o n8n | Correo, Telegram/Slack, plantillas |
| Broker | RabbitMQ | Bus de eventos entre servicios |
| Base de datos | PostgreSQL | Una instancia con una base y un usuario por servicio |
| Inventory | C# + .NET | Catálogo, stock, movimientos, reservas |
| Tickets | Java + Spring | Tickets, garantías, devoluciones |
| Store | Por decidir | Catálogo público, pedidos, pagos |
| Automatizaciones | n8n | Alertas, reposición, reportes programados |
| Frontends internos | Angular | Inventory y Tickets (paneles empresariales) |
| Frontend público | Next.js (React) | Store (SEO, rendimiento, experiencia de cliente) |

Criterio de frontend: **paneles internos y empresariales → Angular; cara pública al cliente → Next.js.**

## 3. Arquitectura general

```text
                        ┌──────────────────────────┐
                        │  Frontends               │
                        │  Angular (Inventory,     │
                        │           Tickets)       │
                        │  Next.js (Store)         │
                        └────────────┬─────────────┘
                                     │ REST + JWT
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
┌───────▼───────┐           ┌────────▼───────┐           ┌────────▼───────┐
│  Inventory    │           │    Tickets     │           │     Store      │
│  .NET         │           │    Spring      │           │  (por decidir) │
│  DB propia    │           │    DB propia   │           │   DB propia    │
└───────┬───────┘           └────────┬───────┘           └────────┬───────┘
        │                            │                            │
        └────────────────┬───────────┴────────────┬───────────────┘
                         │   eventos (RabbitMQ)   │
          ┌──────────────▼──────────┐    ┌────────▼─────────┐
          │ Reports (Python)        │    │ n8n              │
          │ Notifications           │    │ automatizaciones │
          └─────────────────────────┘    └──────────────────┘

   Identity (NestJS): emite JWT, publica JWKS. Cada sistema valida el
   token localmente, sin llamar a Identity en cada petición.
```

**Decisión clave:** el JWT se firma con una clave asimétrica (RS256) e Identity expone un endpoint JWKS. Así .NET, Spring y Store validan tokens por su cuenta, y si Identity se cae, las sesiones ya emitidas siguen funcionando mientras el access token (15 minutos) no venza.

Detalle: `04-identity-authentication-flow.md`.

## 4. Modos de ejecución

Un `docker-compose` con **perfiles** decide qué se levanta, y un `Makefile` con un archivo de variables por modo configura cada uno:

```text
make base                                # solo PostgreSQL, RabbitMQ e Identity
make inventory                           # base + Inventory
make tickets                             # base + Tickets
make store                               # base + Store
make inventory WITH="reports"            # un sistema + complementos
make inventory WITH="reports notifications"
make full                                # todo conectado
```

- Los perfiles `inventory`, `tickets` y `store` son sistemas autónomos.
- `reports` y `notifications` (con n8n) son **complementos** que se suman a cualquier sistema.
- `full` activa la integración entre sistemas y la sesión compartida entre Inventory y Tickets.

Cada sistema incluye datos de demostración (seeders) y usuarios de prueba para que cualquiera lo vea funcionando en minutos. Con solo el repositorio `platform` clonado todo funciona, porque los servicios se descargan como imágenes publicadas.

Detalle: `07-platform-infrastructure.md`.

### Patrón puerto y adaptador

Para que un sistema funcione solo, la dependencia de otro sistema se abstrae detrás de una interfaz. Ejemplo en Store:

- `StockProvider` (interfaz)
  - `LocalStockProvider`: stock simple propio (modo independiente).
  - `InventoryEventProvider`: delega en Inventory por eventos (modo integrado).

Se activa con una variable de entorno (`INTEGRATION_MODE`). El mismo enfoque aplica a Tickets: pueden crearse manualmente o automáticamente desde Store.

## 5. Eventos entre sistemas (modo integrado)

| Evento | Publica | Reacciona |
|---|---|---|
| `order.paid` | Store | Inventory (reserva/descuenta), Reports, Notifications |
| `stock.reserved` / `stock.failed` | Inventory | Store (confirma o cancela el pedido) |
| `stock.low` | Inventory | n8n (alerta y reposición) |
| `payment.failed` / `order.refunded` | Store | Tickets (crea ticket automático) |
| `ticket.created` / `ticket.resolved` | Tickets | Notifications, Reports |

Sobre estándar para todos los eventos: `id`, `type`, `version`, `occurredAt`, `source`, `correlationId`, `causationId` (opcional) y `payload`. Cada evento y versión tiene su esquema JSON Schema en el repositorio de contratos. En la Fase 1 solo se definen los eventos de Inventory.

Detalle: `06-event-contracts.md`.

### Consistencia e idempotencia

- **Entrega al menos una vez:** el broker puede repetir mensajes y no garantiza orden; los consumidores deben ser idempotentes.
- **Outbox pattern:** cada servicio publicador guarda el evento en su base en la misma transacción que el cambio, y un proceso lo publica después. Un evento nunca se pierde.
- **Inbox (`processed_events`):** un evento repetido no duplica pedidos ni descuentos de stock.
- **Saga con compensación:** si el pago se confirma pero Inventory no tiene stock, se cancela el pedido y se reembolsa.
- **Mensajes fallidos:** tras varios intentos van a una cola de mensajes fallidos que se revisa a mano.

## 6. Pagos (Store)

- Stripe o Mercado Pago en **modo sandbox**. Nunca se almacenan datos de tarjeta.
- Webhooks de confirmación con idempotencia.
- Estados del pago: pendiente, pagado, fallido, reembolsado.
- El módulo de pagos vive dentro del servicio de pedidos; se separa solo si luego hace falta.

## 7. Organización de repositorios

- `platform`: `docker-compose` con perfiles, `Makefile`, configuración compartida, documentación transversal, diagrama general y README principal del portafolio.
- `event-contracts`: esquemas JSON Schema de los eventos, ejemplos y catálogo.
- Un repo por servicio compartido: `identity` y `reports`.
- Un repo por sistema: `inventory`, `tickets`, `store`.
- Cada repo con su README, tests, CI (GitHub Actions), documentación OpenAPI y su carpeta `docs`.
- Los servicios publican sus imágenes en GitHub Container Registry.

## 8. Orden de construcción

1. **Plataforma base:** Identity, broker y contratos de eventos (sin frontend, probado con Swagger o Postman).
2. **Inventory:** backend en .NET + frontend en Angular.
3. **Store:** funcionando sola, luego integrada con Inventory (Next.js).
4. **Reports** en Python.
5. **Tickets** en Spring + Angular, integrado con Store.
6. **n8n y Notifications** como última capa.

Cada paso deja algo presentable por sí solo.

## 9. Fase 1: plataforma base

La Fase 1 se documenta por completo antes de implementarla. Los documentos son:

| # | Documento | Tema |
|:-:|---|---|
| 1 | `01-vision-and-scope.md` | Visión, alcance, convenciones y mejoras futuras |
| 2 | `02-identity-roles-and-permissions.md` | Roles y permisos |
| 3 | `03-identity-data-model.md` | Modelo de datos |
| 4 | `04-identity-authentication-flow.md` | Tokens, sesiones y JWKS |
| 5 | `05-identity-api.md` | Convenciones y endpoints |
| 6 | `06-event-contracts.md` | Contratos de eventos |
| 7 | `07-platform-infrastructure.md` | Infraestructura |
| 8 | `08-identity-project-structure.md` | Estructura del código de Identity |
| 9 | `09-phase-1-implementation-plan.md` | Hitos de implementación y trazabilidad |

### Servicio Identity (NestJS)

| Entidades | Endpoints principales |
|---|---|
| User, Role, UserRole, Employee, RefreshToken | `POST /v1/auth/login`, `/register`, `/refresh`, `/logout`, `/logout-all` |
| | `GET /.well-known/jwks.json` |
| | CRUD de usuarios y empleados (solo `admin`) |
| | `GET /v1/me` y `POST /v1/me/password` |
| | `GET /v1/roles` |

Roles base: `admin` (superusuario), `employee` y `customer` (excluyentes entre sí). Roles de área: `inventory_manager`, `support_agent` y `store_manager`. Los permisos finos viven en cada sistema; los roles viajan en el token.

### Contratos de eventos

- Sobre estándar de eventos (ver sección 5).
- Esquemas JSON Schema para cada evento y versión. En esta fase solo los de Inventory: `stock.adjusted`, `stock.low`, `stock.reserved` y `stock.failed`.

### Infraestructura

- `docker-compose` con perfiles y `Makefile`, RabbitMQ y una instancia de PostgreSQL con una base por servicio.
- Secretos generados en el primer arranque, datos esenciales y de demostración separados.
- CI por repositorio en GitHub Actions: build, tests y lint; publicación de imágenes.

**Listo cuando:** `make base` levanta la plataforma, un usuario de prueba inicia sesión, obtiene un JWT y un cliente externo lo valida usando solo el JWKS (prueba de humo automatizada).

## 10. Fase 2: Inventory (.NET + Angular)

### Modelo de datos

El sistema maneja **un solo almacén**, por lo que no existe una entidad de almacén ni stock por ubicación.

| Entidad | Notas |
|---|---|
| Product | SKU único, nombre, categoría, unidad, umbral de stock mínimo |
| Category | Jerarquía simple |
| StockMovement | Entrada, salida o ajuste; nunca se edita, solo se agrega |
| Reservation | Stock apartado con expiración |
| Supplier | Proveedor básico |

El inventario es un **registro de movimientos**: el stock actual de cada producto se deriva de ellos y cada cambio queda auditado.

### Endpoints del MVP

- CRUD de productos, categorías y proveedores.
- `POST /movements` (entrada, salida, ajuste).
- `GET /stock` con filtros por producto y bajo mínimo.
- `POST /reservations` y `DELETE /reservations/{id}`.
- Historial de movimientos con paginación.

### Eventos

- **Publica:** `stock.adjusted`, `stock.low`, `stock.reserved`, `stock.failed`.
- **Consume (modo integrado, después):** `order.paid`, `order.cancelled`.

### Stack técnico

ASP.NET Core, EF Core, PostgreSQL, FluentValidation, xUnit con Testcontainers, Swagger y outbox pattern. Aplica DDD en nivel alto (movimientos como libro inmutable, stock derivado y reservas todo o nada con concurrencia).

### Frontend Angular

- Login y guards por rol.
- Listado de productos con filtros y paginación.
- Formularios de producto y de movimiento.
- Vista de stock por producto y categoría.
- Panel con alertas de stock bajo.

### Criterios de terminado

- Se registra una salida que deja el stock bajo el mínimo y se emite `stock.low`.
- Una reserva concurrente no permite vender más de lo disponible (con test que lo demuestre).
- Todo levanta con `make inventory` y datos de ejemplo.
- README con diagrama, decisiones de diseño y capturas.

### Fuera del MVP

Varios almacenes y transferencias entre almacenes, órdenes de compra a proveedores, lotes y caducidades, códigos de barras, importación masiva, reportes avanzados y SQL Server como motor alternativo. Buenos candidatos para una segunda iteración.

## 11. Para no duplicar trabajo entre frameworks

- **Tokens de diseño compartidos** (colores, tipografía, espaciado) en un archivo CSS o preset de Tailwind usado por ambos frontends.
- **Cliente de autenticación pequeño** en TypeScript para manejar el JWT, adaptado a cada framework. Mantiene el access token en memoria y el refresh token en una cookie `HttpOnly`.
- **Tipos generados desde OpenAPI** (`openapi-typescript` u `openapi-generator`) para mantener los frontends sincronizados con cada API.
- Cada frontend consume solo la API de su propio sistema y la de Identity, nunca la de otro sistema.

## 12. Decisiones pendientes

- Framework del backend de Store (candidatos: NestJS como proyecto distinto al de Identity, FastAPI o Django).
- Pasarela de pagos: Stripe o Mercado Pago.
- Si Notifications es un servicio propio o un flujo de n8n.
- Si el stock reservado cuenta como disponible (Fase 2).

Las decisiones ya cerradas y las alternativas descartadas están en la sección correspondiente de cada documento de la Fase 1; la lista consolidada de mejoras futuras, en `01-vision-and-scope.md`.
