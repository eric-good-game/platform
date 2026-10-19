# Identity: roles y permisos

Documento 2 de la Fase 1. Define cómo se modelan los roles en el servicio Identity y cómo cada sistema decide qué puede hacer cada usuario.

Estado: **borrador para revisión**.

## 1. Principio

Identity solo conoce **roles**. Los **permisos** (acciones concretas como `product:create`) viven dentro de cada sistema. El rol viaja en el JWT y cada sistema lo traduce a permisos con su propia tabla.

Consecuencias:

- Identity no necesita saber qué es un producto, un ticket o un pedido.
- Agregar un sistema nuevo no obliga a modificar Identity.
- Cambiar qué puede hacer un rol en un sistema es un cambio local a ese sistema, sin tocar el token ni Identity.

## 2. Catálogo de roles

Los roles son **fijos** en esta fase: se crean con seeders y no se administran desde la API.

### Roles base (tipo de cuenta)

| Rol | Descripción |
|---|---|
| `admin` | Superusuario. Puede realizar cualquier acción en cualquier sistema. |
| `employee` | Personal interno. Acceso a los paneles empresariales según sus roles de área. |
| `customer` | Cliente de Store. Sin acceso a los paneles internos. |

### Roles de área

| Rol | Alcance |
|---|---|
| `inventory_manager` | Gestiona el catálogo, los proveedores y el stock del sistema de Inventory. |
| `support_agent` | Gestiona tickets, garantías y devoluciones. |
| `store_manager` | Gestiona catálogo público, pedidos y pagos de Store. |

## 3. Reglas e invariantes

Las invariantes son condiciones que deben cumplirse siempre. Cada una tiene un criterio verificable que luego se convierte en test.

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Un usuario puede tener **varios roles** a la vez (roles apilables). | Asignar `employee` e `inventory_manager` al mismo usuario funciona y ambos aparecen en el token. |
| 2 | `customer` y `employee` son **excluyentes**. | Asignar `employee` a un usuario con `customer` (o al revés) responde `409`. |
| 3 | `admin` es superusuario y no necesita roles de área para operar. | Un usuario `admin` sin roles de área pasa la comprobación de cualquier permiso. |
| 4 | Los roles de área solo se asignan a cuentas `employee`. | Asignar `inventory_manager` a un `customer` responde `409`. |
| 5 | Los permisos se **suman**: una acción se permite si cualquiera de los roles la autoriza. | Un usuario con `employee` + `inventory_manager` puede ejecutar `product:create`. |

Ejemplos válidos:

| Usuario | Roles |
|---|---|
| Cliente de Store | `["customer"]` |
| Empleado de almacén | `["employee"]` |
| Encargado de Inventory | `["employee", "inventory_manager"]` |
| Empleado con dos áreas | `["employee", "inventory_manager", "support_agent"]` |
| Administrador | `["admin"]` |

Ejemplos inválidos: `["customer", "employee"]`, `["customer", "inventory_manager"]`.

> Confirmado: `admin` no necesita `employee` ni registro de empleado para operar (ver documento de modelo de datos).

Pruebas: la invariante 1 se prueba en Identity (los roles aparecen en el token). Las invariantes 3 y 5 se completan en cada sistema, con su propia tabla de permisos (Inventory, en la Fase 2); en la Fase 1 Identity prueba que `admin` y los roles viajan en el token.

## 4. Roles en el token

El JWT incluye los roles como arreglo:

```json
{
  "iss": "identity",
  "sub": "user-id",
  "roles": ["employee", "inventory_manager"],
  "iat": 0,
  "exp": 0
}
```

Cada sistema lee `roles`, lo traduce a permisos y decide. Un cambio de roles de un usuario se refleja cuando se emite un nuevo access token (por eso el access token es de vida corta, 15 minutos; ver documento de flujo de autenticación).

## 5. Permisos por sistema

Cada sistema define su propia tabla `rol → permisos`. Formato del permiso: `recurso:acción`.

La siguiente tabla es el **ejemplo de referencia para Inventory**; se refinará en la fase de Inventory, no en Identity.

| Permiso | `admin` | `employee` | `inventory_manager` | `customer` |
|---|:-:|:-:|:-:|:-:|
| `product:read` | sí | sí | sí | no |
| `product:create` / `product:update` | sí | no | sí | no |
| `product:delete` | sí | no | sí | no |
| `movement:create` | sí | sí | sí | no |
| `stock:read` | sí | sí | sí | no |
| `reservation:create` | sí | sí | sí | no |
| `supplier:manage` | sí | no | sí | no |

Las tablas de Tickets y Store se definen cuando se llegue a esas fases.

## 6. Implementación (a grandes rasgos)

- Cada endpoint declara el permiso que exige.
- Una capa del sistema (guard/middleware/filtro, según el framework) traduce los roles del token a permisos y responde `403` si no alcanza.
- `admin` salta la comprobación de permisos.

## 7. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Roles apilables (varios por usuario) | Un solo rol por usuario | Más expresivo sin complicar el modelo; refleja puestos reales. |
| Permisos finos en cada sistema | Permisos centralizados en Identity | Mantiene a Identity independiente de los sistemas; permite agregar sistemas sin tocarlo. |
| `customer` y `employee` excluyentes | Permitir ambos en la misma cuenta | Separa claramente la cara pública de los paneles internos y evita ambigüedad de acceso. |
| Roles de área fijos (seeders) | Roles creables por el admin desde la API | Reduce alcance del MVP; se puede agregar en una segunda iteración. |
| `admin` como superusuario | `admin` con permisos explícitos | Más simple para el MVP; se puede endurecer después. |

## 8. Fuera de alcance (por ahora)

- Creación y edición de roles desde la API.
- Permisos a nivel de registro (por ejemplo, "solo los tickets asignados a mí").
- Jerarquías entre roles.
