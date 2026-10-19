# Identity: API

Documento 5 de la Fase 1. Define el contrato HTTP del servicio Identity: convenciones, formato de errores, paginación y catálogo de endpoints. Es agnóstico de tecnología.

Las convenciones de las secciones 2 a 5 (versionado, errores, paginación, formato de datos) son la **referencia para todas las APIs del portafolio**: los demás sistemas las heredan.

Estado: **borrador para revisión**.

## 1. Alcance

Esta API cubre: autenticación y sesiones, registro de clientes, gestión de usuarios y roles por un administrador, consulta de la cuenta propia, publicación de claves (JWKS) y estado de salud del servicio. Los flujos de tokens están descritos en el documento de flujo de autenticación; aquí solo se define el contrato.

## 2. Convenciones

| Tema | Regla |
|---|---|
| Versionado | En la ruta: `/v1/...`. El JWKS (`/.well-known/jwks.json`) no lleva versión porque es un estándar, ni el endpoint de salud (`/health`), que es de operación. |
| Formato | JSON (`Content-Type: application/json`), excepto errores (ver sección 3). |
| Nombres de campos | `camelCase` (`firstName`, `createdAt`). |
| Fechas con hora | ISO 8601 en UTC: `"2026-10-17T19:51:00Z"`. El frontend las convierte a la hora local. |
| Fechas sin hora | ISO 8601 corto: `"2026-03-15"`. |
| Identificadores | UUID v7 como texto. |
| Roles | Siempre como arreglo de nombres: `["employee", "inventory_manager"]`. |
| Autenticación | Cabecera `Authorization: Bearer <access token>`. |
| Campos desconocidos | Si una petición trae campos que la API no define, se ignoran. |
| Correlación | Cabecera `X-Correlation-Id`: si llega con un UUID válido se conserva; si falta o no es válido, Identity genera uno. Siempre se devuelve en la respuesta, también en los errores. |

### Códigos de estado

| Código | Uso |
|---|---|
| `200` | Éxito con cuerpo. |
| `201` | Recurso creado. |
| `204` | Éxito sin cuerpo. |
| `401` | Sin credenciales válidas, o token inválido o vencido. |
| `403` | Autenticado, pero sin permiso. |
| `404` | El recurso no existe. |
| `409` | Conflicto con el estado actual (email duplicado, roles incompatibles). |
| `422` | Datos inválidos o incompletos. |
| `429` | Demasiados intentos. |
| `503` | Servicio no disponible (solo en el endpoint de salud). |

### Reglas de contraseña

Se aplican al registro, a la creación de usuarios por un administrador y al cambio de contraseña. Siguen las recomendaciones actuales del NIST (SP 800-63B).

| Regla | Valor | `code` del campo en `errors` |
|---|---|---|
| Longitud mínima | 12 caracteres | `TOO_SHORT` |
| Longitud máxima | 128 caracteres | `TOO_LONG` |
| Caracteres permitidos | Cualquiera (Unicode y espacios) | — |
| Reglas de composición | Ninguna (no se exige mayúscula, número ni símbolo) | — |
| Contraseñas comunes | Se rechazan las de una lista de contraseñas habituales | `TOO_COMMON` |
| Igual al email | Se rechaza | `SAME_AS_EMAIL` |
| Expiración periódica | No hay | — |

La contraseña nunca se recorta ni se modifica antes de calcular el hash.

## 3. Formato de errores

Todos los errores siguen el estándar **Problem Details** (RFC 9457), con el tipo de contenido `application/problem+json`, más dos campos propios: `code` y, en errores de validación, `errors`.

```json
{
  "type": "/errors/email-already-exists",
  "title": "Email already exists",
  "status": 409,
  "detail": "An account with this email already exists.",
  "code": "EMAIL_ALREADY_EXISTS"
}
```

Error de validación, con la lista de campos con problemas:

```json
{
  "type": "/errors/validation-failed",
  "title": "Validation failed",
  "status": 422,
  "detail": "One or more fields are invalid.",
  "code": "VALIDATION_FAILED",
  "errors": [
    { "field": "email", "code": "INVALID_FORMAT", "message": "Must be a valid email address." },
    { "field": "password", "code": "TOO_SHORT", "message": "Must be at least 12 characters." }
  ]
}
```

Reglas:

- El **`code`** es estable y es lo que usan los frontends para decidir qué mostrar. El `title` y `detail` son informativos y pueden cambiar; los frontends no dependen de su texto.
- Los mensajes de error no revelan información sensible (ver la regla de login en la sección 6.1).
- Un error no controlado responde `500` con `code: "INTERNAL_ERROR"` y sin detalles internos.

### Catálogo de códigos

| `code` | Estado | Cuándo |
|---|---|---|
| `VALIDATION_FAILED` | `422` | Algún campo es inválido o falta. |
| `INVALID_CREDENTIALS` | `401` | Email o contraseña incorrectos, o usuario desactivado. |
| `UNAUTHENTICATED` | `401` | Falta el access token, o es inválido o vencido. |
| `INVALID_REFRESH_TOKEN` | `401` | Refresh token inexistente, vencido, revocado o reutilizado. |
| `FORBIDDEN` | `403` | El usuario no tiene los roles necesarios. |
| `CLIENT_NOT_ALLOWED` | `403` | El origen o el cliente no está registrado. |
| `USER_NOT_FOUND` | `404` | No existe un usuario con ese id. |
| `EMAIL_ALREADY_EXISTS` | `409` | El email ya está registrado (sin distinguir mayúsculas). |
| `ROLE_INCOMPATIBLE` | `409` | Combinación de roles prohibida (ver documento de roles y permisos). |
| `EMPLOYEE_DATA_NOT_ALLOWED` | `409` | Se enviaron datos de empleado para una cuenta que no es `employee`. |
| `EMPLOYEE_DATA_REQUIRED` | `422` | Falta el bloque de datos de empleado para una cuenta `employee`. |
| `CANNOT_MODIFY_SELF` | `409` | Un administrador intenta desactivarse o cambiarse sus propios roles. |
| `TOO_MANY_ATTEMPTS` | `429` | Se superó el límite de intentos de login. |
| `INTERNAL_ERROR` | `500` | Error inesperado. |

## 4. Paginación

Las listas usan paginación por **página y tamaño**.

Petición: `GET /v1/users?page=1&pageSize=20`

| Parámetro | Por omisión | Límites |
|---|---|---|
| `page` | `1` | Mínimo 1. |
| `pageSize` | `20` | Entre 1 y 100. |

Respuesta:

```json
{
  "items": [ { "id": "..." } ],
  "page": 1,
  "pageSize": 20,
  "totalItems": 134,
  "totalPages": 7
}
```

Un `page` mayor al total devuelve `items` vacío, no un error. Un parámetro fuera de rango responde `422`.

## 5. Recursos

### Usuario (`User`)

```json
{
  "id": "0192f3c4-7a1e-7b3d-9c2a-5e8f1a2b3c4d",
  "email": "ana@empresa.com",
  "roles": ["employee", "inventory_manager"],
  "status": "active",
  "employee": {
    "firstName": "Ana",
    "lastName": "Pérez",
    "jobTitle": "Encargada de almacén",
    "department": "Logística",
    "hireDate": "2026-03-15"
  },
  "createdAt": "2026-03-15T15:00:00Z",
  "updatedAt": "2026-03-15T15:00:00Z"
}
```

- `employee` solo aparece en cuentas `employee`; en el resto el campo se omite.
- Nunca se devuelven `passwordHash` ni datos de tokens de refresco.

### Rol (`Role`)

```json
{ "id": "...", "name": "inventory_manager", "description": "Manages catalog, suppliers and stock." }
```

## 6. Endpoints

### 6.1 Autenticación

#### `POST /v1/auth/login` — público

Petición:

```json
{ "email": "ana@empresa.com", "password": "...", "client": "inventory" }
```

Respuesta `200`:

```json
{ "accessToken": "<jwt>", "tokenType": "Bearer", "expiresIn": 900 }
```

- El refresh token **no** viaja en el cuerpo: Identity lo entrega en una cookie `HttpOnly` según el cliente y el rol (ver documento de flujo de autenticación, sección 6).
- Errores: `422` (datos inválidos), `401 INVALID_CREDENTIALS`, `403 CLIENT_NOT_ALLOWED`, `429 TOO_MANY_ATTEMPTS`.
- **Email inexistente, contraseña incorrecta y usuario desactivado responden lo mismo** (`401 INVALID_CREDENTIALS`), para no revelar qué cuentas existen ni su estado.
- El cliente se deduce de la cabecera `Origin` (los navegadores siempre la envían), que debe ser el origen registrado de un cliente. `client` es **opcional** si hay `Origin`; si se envía, debe coincidir con él. Sin `Origin` (Postman, pruebas), `client` es obligatorio y debe ser un cliente registrado. Si no coincide o no está registrado responde `403 CLIENT_NOT_ALLOWED`, y si falta (sin `Origin` ni `client`) responde `422 VALIDATION_FAILED`.
- Un `customer` solo puede iniciar sesión desde el cliente `store`, y un `employee` o `admin` solo desde los paneles internos. En caso contrario responde `403 CLIENT_NOT_ALLOWED`.
- **Estas comprobaciones son una medida de orden, no de seguridad.** Evitan que una cuenta reciba la cookie equivocada (por ejemplo, un cliente con la cookie compartida de los paneles internos) y detectan frontends mal configurados, pero quien llame sin navegador puede falsificarlas. La protección real son los permisos de cada sistema: un `customer` no puede hacer nada en Inventory aunque tenga un token válido.

> **Pendiente para el hito 5 (`F1-01` y `F1-02`).** Con esta regla, ni un `employee` con `store_manager` ni un `admin` tienen un cliente de Store desde el que iniciar sesión, aunque el documento 2 los describe con acceso a Store. Antes de implementar la autenticación (hito 5) hay que decidir el modelo de clientes de Store (cliente `store` con cara pública y panel interno, o un panel interno propio) y corregir esta regla y la invariante 11.

#### `POST /v1/auth/register` — público

Crea una cuenta **`customer`**. Es el único camino de autoregistro y no puede crear otros tipos de cuenta.

Petición:

```json
{ "email": "cliente@correo.com", "password": "..." }
```

Respuesta `201`: el recurso `User` (con `roles: ["customer"]`). **No inicia sesión**: el frontend llama después a `login`.

- Errores: `422`, `409 EMAIL_ALREADY_EXISTS`, `429`.
- Los datos propios del cliente (nombre, dirección, teléfono) los guarda Store, no Identity.

> Nota de seguridad: este endpoint revela si un email ya existe (`409`). Es una concesión habitual del registro. Se protege con el mismo límite de intentos que el login.

#### `POST /v1/auth/refresh` — con refresh token

Lee el refresh token de la cookie, aplica la rotación y responde `200` con un nuevo `accessToken` (mismo formato que el login) y la cookie renovada.

- El cliente se determina como en el login (por `Origin`, o por `client` en el cuerpo si no hay `Origin`); con él se elige la cookie que se lee y se renueva.
- Errores: `401 INVALID_REFRESH_TOKEN` (incluye la reutilización, que además revoca la familia), `403 CLIENT_NOT_ALLOWED`.

#### `POST /v1/auth/logout` — con refresh token

Revoca la familia de la sesión actual y borra la cookie. Responde `204`. Es idempotente: si la sesión ya estaba cerrada, también responde `204`. El cliente se determina como en el login, para saber qué cookie leer y borrar.

#### `POST /v1/auth/logout-all` — autenticado

Revoca todas las familias del usuario autenticado. Responde `204`.

#### `GET /.well-known/jwks.json` — público

Devuelve las claves públicas de firma en formato JWKS. Es cacheable. Sin versión ni autenticación.

### 6.2 Cuenta propia

#### `GET /v1/me` — autenticado

Responde `200` con el recurso `User` del usuario autenticado. El `id` se toma del token.

#### `POST /v1/me/password` — autenticado

Cambia la contraseña del usuario autenticado.

```json
{ "currentPassword": "...", "newPassword": "..." }
```

- La nueva contraseña cumple las reglas de contraseña (sección 2).
- Si `currentPassword` es incorrecta responde `422 VALIDATION_FAILED` con el campo `currentPassword` y el `code` `INCORRECT`. No cierra la sesión.
- Revoca **todas las demás sesiones** del usuario (todas las familias salvo la actual), que conserva su sesión. El access token vigente de las demás sesiones funciona hasta expirar (máximo 15 minutos).
- Está sujeto al límite de intentos: sin él, un access token robado permitiría adivinar la contraseña actual.
- Responde `204`.
- Errores: `401`, `422`, `429`.

### 6.3 Gestión de usuarios (solo `admin`)

#### `POST /v1/users`

Crea un usuario con sus roles.

```json
{
  "email": "ana@empresa.com",
  "password": "...",
  "roles": ["employee", "inventory_manager"],
  "employee": {
    "firstName": "Ana",
    "lastName": "Pérez",
    "jobTitle": "Encargada de almacén",
    "department": "Logística",
    "hireDate": "2026-03-15"
  }
}
```

- Si `roles` incluye `employee`, `employee` es obligatorio (`422 EMPLOYEE_DATA_REQUIRED`). Si no lo incluye, `employee` no debe enviarse (`409 EMPLOYEE_DATA_NOT_ALLOWED`).
- Valida las invariantes de roles (`409 ROLE_INCOMPATIBLE`).
- Se crea el usuario, sus roles y, si aplica, su registro de empleado en **una sola operación**: o se guarda todo o nada.
- La contraseña es la **inicial** y cumple las mismas reglas de contraseña. El empleado puede cambiarla después con `POST /v1/me/password`.
- Un administrador puede crear otras cuentas `admin` (`roles: ["admin"]`); la primera cuenta `admin` sale de los datos iniciales.
- Responde `201` con el recurso `User`.
- Errores: `409 EMAIL_ALREADY_EXISTS`, `422`, `403`.

#### `GET /v1/users`

Lista paginada. Filtros opcionales: `role`, `status` y `email` (búsqueda parcial). Orden por omisión: `createdAt` descendente.

#### `GET /v1/users/{id}`

Responde `200` con el recurso `User`, o `404 USER_NOT_FOUND`.

#### `PATCH /v1/users/{id}`

Edita parcialmente el email y/o los datos de empleado. Solo se modifican los campos enviados.

```json
{ "email": "ana.perez@empresa.com", "employee": { "jobTitle": "Jefa de almacén" } }
```

- Los roles **no** se cambian aquí (ver `PUT .../roles`).
- La contraseña no se cambia aquí: cada usuario la cambia con `POST /v1/me/password`.
- Errores: `404`, `409 EMAIL_ALREADY_EXISTS`, `409 EMPLOYEE_DATA_NOT_ALLOWED`, `422`.

#### `PUT /v1/users/{id}/roles`

Reemplaza el conjunto completo de roles.

```json
{ "roles": ["employee", "support_agent"] }
```

- Identity valida el **resultado final** contra las invariantes de roles.
- Si el nuevo conjunto incluye `employee` y el usuario no tiene registro de empleado, la petición debe traer también el bloque `employee` (`422 EMPLOYEE_DATA_REQUIRED` en caso contrario). Cambiar de `employee` a `customer` (o al revés) exige además que el usuario no tenga datos incompatibles; para el MVP, esos cambios de tipo de cuenta no se permiten (`409 ROLE_INCOMPATIBLE`).
- Un administrador no puede cambiar sus propios roles (`409 CANNOT_MODIFY_SELF`).
- Los cambios se reflejan en el siguiente access token del usuario (hasta 15 minutos).
- Responde `200` con el recurso `User`.

#### `DELETE /v1/users/{id}`

Es un **borrado lógico**: pasa el usuario a `disabled` y revoca todos sus tokens de refresco. Responde `204`. Es idempotente.

- Un administrador no puede desactivarse a sí mismo (`409 CANNOT_MODIFY_SELF`).
- Errores: `404`.

### 6.4 Roles

#### `GET /v1/roles` — autenticado

Lista el catálogo de roles (solo lectura). No está paginado: el catálogo es corto y fijo.

### 6.5 Salud

#### `GET /health` — público

Responde `200` con `{ "status": "ok" }` si Identity y su base de datos responden, o `503` si no. Lo usa el control de salud de la infraestructura. No lleva versión ni autenticación y no expone detalles internos.

## 7. Resumen de acceso

| Endpoint | Acceso |
|---|---|
| `POST /v1/auth/login`, `POST /v1/auth/register`, `GET /.well-known/jwks.json`, `GET /health` | Público |
| `POST /v1/auth/refresh`, `POST /v1/auth/logout` | Refresh token (cookie) |
| `POST /v1/auth/logout-all`, `GET /v1/me`, `POST /v1/me/password`, `GET /v1/roles` | Cualquier usuario autenticado |
| `/v1/users` (todas las operaciones) | Solo `admin` |

## 8. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Todos los errores usan Problem Details e incluyen un `code` estable. | Cada respuesta de error tiene `Content-Type: application/problem+json` y un campo `code` del catálogo. |
| 2 | Los errores de validación listan los campos con problemas. | Una petición con email inválido responde `422` con `errors` conteniendo el campo `email`. |
| 3 | Ninguna respuesta incluye `passwordHash` ni tokens de refresco en el cuerpo. | Revisar las respuestas de todos los endpoints de `User`: ningún campo los contiene. |
| 4 | El registro público solo crea cuentas `customer`. | Enviar `roles` en `POST /v1/auth/register` se ignora; la cuenta queda como `customer`. |
| 5 | Solo un `admin` puede usar `/v1/users`. | Un `employee` o `customer` recibe `403` en cualquiera de sus operaciones. |
| 6 | Crear un usuario es atómico: usuario, roles y datos de empleado se guardan juntos o no se guarda nada. | Si falla la creación del registro de empleado, el usuario tampoco existe. |
| 7 | `PUT .../roles` valida el conjunto final de roles. | Enviar `["customer", "employee"]` responde `409 ROLE_INCOMPATIBLE`. |
| 8 | Un administrador no puede desactivarse ni cambiarse sus propios roles. | `DELETE` y `PUT .../roles` sobre su propio `id` responden `409 CANNOT_MODIFY_SELF`. |
| 9 | `DELETE /v1/users/{id}` no borra físicamente. | Tras el borrado, `GET /v1/users/{id}` devuelve el usuario con `status = disabled`. |
| 10 | Login no distingue entre email inexistente, contraseña incorrecta y usuario desactivado. | Los tres casos devuelven la misma respuesta `401 INVALID_CREDENTIALS`. |
| 11 | Un `customer` no recibe sesión de los paneles internos, y un `employee` o `admin` no la recibe de Store (medida de orden; la seguridad real son los permisos de cada sistema). | Login de un `customer` desde `inventory` responde `403 CLIENT_NOT_ALLOWED`. |
| 12 | Todas las fechas se devuelven en UTC con formato ISO 8601. | Todo campo de fecha con hora termina en `Z`. |
| 13 | `logout` y `DELETE /v1/users/{id}` son idempotentes. | Llamarlos dos veces seguidas responde `204` las dos veces. |
| 14 | El cliente se deduce del `Origin`; si también se envía `client`, debe coincidir; sin `Origin`, `client` es obligatorio. | Login con `Origin` de Inventory y sin `client` usa el cliente `inventory`; con `client: "store"` y ese `Origin` responde `403 CLIENT_NOT_ALLOWED`; sin `Origin` ni `client` responde `422`; sin `Origin` y con `client` funciona. |
| 15 | Toda contraseña nueva cumple las reglas de contraseña. | Una contraseña de 11 caracteres responde `422` con `TOO_SHORT`; `123456789012` responde `422` con `TOO_COMMON`. |
| 16 | Cambiar la contraseña revoca las demás sesiones y conserva la actual. | Con dos sesiones, tras el cambio la otra responde `401` al renovar y la actual sigue renovando. |
| 17 | El cambio de contraseña exige la contraseña actual y está limitado en intentos. | Con una contraseña actual incorrecta responde `422`; superado el límite, responde `429`. |
| 18 | Un `admin` puede crear cuentas `admin`; la primera sale de los datos iniciales. | `POST /v1/users` con `roles: [\"admin\"]` hecho por un `admin` responde `201`; hecho por un `employee`, `403`. |
| 19 | Toda respuesta incluye `X-Correlation-Id`. | Sin la cabecera en la petición, la respuesta trae un UUID nuevo; con un UUID válido, devuelve el mismo; con un valor inválido, devuelve uno nuevo. Aplica también a los errores. |

## 9. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Versionado en la ruta (`/v1`) | Versión en una cabecera HTTP | Más visible y fácil de probar en navegador, Swagger o Postman. |
| Errores con Problem Details y `code` estable | Formato propio de cada servicio | Es un estándar; el `code` desacopla al frontend del texto. |
| Paginación por página y tamaño | Paginación por cursor | Suficiente para listas de administración; el cursor se reserva para historiales grandes. |
| `camelCase`, ISO 8601 y UTC | `snake_case` o formatos locales de fecha | Es el estilo nativo de los frontends, sin ambigüedad y sin problemas de zonas horarias. |
| Registro público de clientes en Identity | Que Store cree la cuenta y la sincronice con Identity | Evita acoplar los dos servicios; Identity es dueña de las credenciales. |
| `register` no inicia sesión | Devolver tokens al registrarse | Un solo camino para emitir sesiones (el login), con una sola lógica de cookies. |
| Cambiar roles con `PUT` y el conjunto completo | Endpoints de agregar y quitar rol | Identity valida el resultado final de una vez. |
| Creación de empleado en una sola operación | Crear usuario y empleado por separado | Garantiza la invariante de que un `employee` siempre tiene registro. |
| `DELETE` como desactivación | Borrado físico | Coherente con el borrado lógico del modelo de datos. |
| El refresh token solo viaja por cookie | Devolverlo también en el cuerpo | Evita exponerlo a scripts del frontend. |
| Cliente deducido del `Origin`, con `client` opcional en el cuerpo | Exigir siempre `client` / deducirlo solo del `Origin` | El navegador ya envía el `Origin`, así que el frontend no repite el dato; Postman y las pruebas siguen funcionando con `client`; sin concepto de cliente no habría cookies por panel. |
| Las comprobaciones de `client` son medidas de orden | Presentarlas como barrera de seguridad | Son falsificables fuera del navegador; la protección real son los permisos por sistema. |
| Reglas de contraseña del NIST (largo, sin composición, sin expiración) | Reglas clásicas (mayúscula, número, símbolo, caducidad) | Empujan a contraseñas predecibles; la longitud aporta más seguridad. |
| Cambio de contraseña autenticado en el MVP | Dejarlo fuera | El administrador fija la contraseña inicial; sin cambio, el empleado nunca podría reemplazarla. |
| Un administrador puede crear otros administradores | Un único `admin` inicial | Evita depender de una sola cuenta; todo `admin` nuevo lo crea otro `admin`. |

## 10. Fuera de alcance (por ahora)

- Recuperación de contraseña por email ("olvidé mi contraseña").
- Comprobar las contraseñas contra listas de filtraciones externas (servicios como Have I Been Pwned). En el MVP solo se usa una lista local de contraseñas comunes.
- Que cada frontend llame a Identity mediante su propio proxy inverso, de modo que las cookies queden ligadas a su dominio y no haga falta el campo `client`.
- Verificación de email.
- Reactivación de usuarios desactivados.
- Cambio de tipo de cuenta (de `employee` a `customer` y al revés).
- Lista de sesiones activas del usuario.
- Auditoría de acciones administrativas.
- Filtros avanzados y ordenamiento configurable en `GET /v1/users`.
- Refresh token en el cuerpo para clientes que no sean navegadores (móvil, scripts).
