# Identity: flujo de autenticación

Documento 4 de la Fase 1. Define cómo inicia sesión un usuario, qué tokens se emiten, cómo se renuevan y cómo los demás sistemas validan la identidad sin depender de este servicio en cada petición.

Estado: **borrador para revisión**.

## 1. Principios

- Identity es el **único** que firma tokens; los demás sistemas solo los verifican.
- Los sistemas validan los access tokens **localmente**, con la clave pública. Si Identity se cae, las sesiones ya emitidas siguen funcionando hasta que su access token expire.
- Una sesión equivale a una **familia** de refresh tokens (`familyId`). Cada login crea una familia nueva. La familia corresponde a una sesión de **navegador**: en el modo `full`, los paneles internos de un mismo navegador comparten familia (ver sección 6).
- Los tokens de refresco se guardan solo como hash (ver modelo de datos).

## 2. Tokens

| | Access token | Refresh token |
|---|---|---|
| Para qué | Acceder a las APIs de los sistemas | Obtener un access token nuevo |
| Formato | JWT firmado con clave asimétrica (RS256) | Valor aleatorio opaco |
| Vida | 15 minutos | 7 días |
| Validación | Local en cada sistema, con la clave pública | Solo Identity, contra su base de datos |
| Rotación | No aplica | Se usa una sola vez; cada uso entrega uno nuevo |

### Contenido del access token

```json
{
  "iss": "identity",
  "sub": "<user id, UUID v7>",
  "roles": ["employee", "inventory_manager"],
  "iat": 0,
  "exp": 0
}
```

El encabezado incluye `kid`, el identificador de la clave con la que se firmó. El contenido está firmado pero **no cifrado**: nunca se incluyen datos sensibles.

## 3. Flujos

### 3.1 Login

1. El cliente envía email y contraseña; Identity determina qué frontend lo usa (ver sección 6.2).
2. Identity verifica las credenciales y que el usuario esté `active`.
3. Crea una **familia nueva** y su primer refresh token.
4. Responde con el access token en el cuerpo y el refresh token en una cookie.

Los errores de credenciales no distinguen entre "email inexistente" y "contraseña incorrecta": ambos responden `401` con el mismo mensaje, para no revelar qué emails existen.

### 3.2 Uso del access token

1. El cliente envía el access token en cada petición a un sistema.
2. El sistema verifica la firma con la clave pública (obtenida del JWKS), que `exp` no haya pasado y que `iss` sea el esperado.
3. Si es válido, lee `roles` y aplica sus permisos (ver documento de roles y permisos).

**Un mismo token sirve para todos los sistemas.** Ningún sistema emite tokens: solo Identity los emite, en el login. Como Inventory, Tickets y Store validan la misma firma, el token obtenido al iniciar sesión se presenta tal cual en cualquiera de ellos. Qué puede hacer el usuario en cada sistema lo decide ese sistema con los `roles` del token. Por ejemplo, un usuario con `["employee", "support_agent"]` puede entrar a Tickets pero no editar el catálogo de Inventory, aunque use el mismo token.

### 3.3 Renovación (refresh con rotación)

1. El cliente envía su refresh token a Identity.
2. Identity busca su hash y comprueba que no esté revocado ni vencido, y que el usuario siga `active`.
3. Marca el token como revocado, crea uno nuevo **en la misma familia** y emite un access token nuevo.

```text
Login        → access A1 + refresh R1
Renovar (R1) → access A2 + refresh R2   (R1 revocado)
Renovar (R2) → access A3 + refresh R3   (R2 revocado)
```

### 3.4 Detección de reutilización

Si llega un refresh token **ya revocado**, es señal de posible robo:

1. Identity revoca **toda la familia** a la que pertenece.
2. Responde `401`; el usuario debe iniciar sesión de nuevo en ese navegador.
3. Las demás familias (otros navegadores o dispositivos) no se tocan.

Un token simplemente **vencido** responde `401` sin revocar la familia, porque no indica robo.

### 3.5 Logout

| Acción | Efecto |
|---|---|
| Cerrar sesión | Revoca la familia del navegador actual. Con sesión compartida (modo `full`), cierra todos los paneles internos de ese navegador. Las sesiones de otros navegadores y las de cuentas `admin` siguen activas. |
| Cerrar todas las sesiones | Revoca todas las familias del usuario (endpoint aparte). |

Los access tokens ya emitidos siguen siendo válidos hasta expirar (máximo 15 minutos). Es una consecuencia aceptada de validar localmente.

### 3.6 Usuario desactivado

Al desactivar un usuario se revocan todas sus familias. No puede iniciar sesión ni renovar. Su access token vigente funciona hasta expirar (máximo 15 minutos).

### 3.7 Cambio de contraseña

Al cambiar su contraseña, un usuario conserva su sesión actual y se revocan **todas las demás familias**. Si alguien había obtenido acceso con la contraseña anterior, queda fuera. Los access tokens vigentes de esas sesiones funcionan hasta expirar (máximo 15 minutos).

## 4. Claves de firma y JWKS

Identity firma con una **clave privada** y publica las **claves públicas** en un endpoint JWKS (`/.well-known/jwks.json`). Cada clave tiene un `kid`.

Cómo lo usan los demás sistemas:

- Descargan el JWKS y lo guardan en caché.
- Si llega un token con un `kid` desconocido, vuelven a consultar el JWKS (una vez) antes de rechazarlo.

### Rotación de claves

1. Se genera una clave nueva y se publica en el JWKS junto a la anterior.
2. Identity empieza a firmar con la nueva.
3. La anterior permanece publicada al menos 15 minutos (la vida de un access token) para que los tokens ya emitidos sigan validando.
4. Se retira la anterior.

## 5. Protección del login

- **Límite de intentos** (*rate limiting*) por email y por IP, con espera temporal al excederlo.
- **No se bloquean cuentas**: bloquearlas permitiría a un tercero dejar fuera a cualquier usuario a propósito.
- Al exceder el límite se responde `429`.

> Pendiente: los valores concretos (intentos y ventana de tiempo) se definen en la implementación. Una referencia inicial razonable es 5 intentos por ventana de 15 minutos.

## 6. Cookies y sesión compartida

### 6.1 Recomendación para los frontends

- El **refresh token** se entrega en una cookie `HttpOnly` y `Secure`, que el JavaScript de la página no puede leer.
- El **access token** se mantiene solo en memoria, sin guardarlo en almacenamiento persistente del navegador.
- Al recargar la página, el frontend usa la cookie para pedir un access token nuevo.

Esto reduce el riesgo de robo de tokens por scripts maliciosos. Para los frontends es una recomendación; en Identity es una regla: el refresh token viaja **solo** en la cookie y nunca en el cuerpo de la respuesta (ver documento de la API).

### 6.2 Clientes

Identity conoce a los frontends que la usan (**clientes**) por **configuración**, no por una tabla en la base de datos. Cada cliente tiene un identificador (`inventory`, `tickets`, `store`), un origen permitido (CORS) y la cookie que le corresponde. Identity deduce el cliente de la cabecera `Origin`, que los navegadores siempre envían, comparándola con los orígenes registrados; un origen no registrado se rechaza. Las herramientas que no envían `Origin` (Postman, pruebas) indican el cliente con un campo `client` en el cuerpo del login, de la renovación y del cierre de sesión; si llegan ambos, deben coincidir. Con el cliente se elige la cookie que corresponde. Estas comprobaciones ordenan las cookies y el CORS, pero **no son una barrera de seguridad**: se pueden falsificar fuera de un navegador. La protección real son los permisos de cada sistema.

> **Pendiente para el hito 5 (`F1-01`/`F1-02`).** El cliente `store` todavía no cubre el panel interno de Store: hay que decidir cómo inician sesión `store_manager` y `admin` para operar Store (documento 5, sección 6.1).

### 6.3 Sesión compartida o individual según el modo de ejecución

Si los paneles comparten sesión depende del modo de ejecución con el que se levante el sistema (ver el documento de infraestructura). Es solo configuración de la cookie de cada cliente.

| Cliente | Modo de un solo sistema (independiente) | Modo `full` |
|---|---|---|
| `inventory` | `refresh_inventory` | `refresh_internal` (compartida con tickets) |
| `tickets` | `refresh_tickets` | `refresh_internal` (compartida con Inventory) |
| `store` | `refresh_store` | `refresh_store` (nunca se comparte) |

Los nombres de cookie son de referencia.

Reglas:

- **Las cuentas `admin` no comparten sesión.** En cualquier modo, Identity entrega al `admin` una cookie propia de cada cliente (por ejemplo, `refresh_admin_inventory`) y debe iniciar sesión en cada panel. Así, el robo de una sesión compartida no da poder total.
- La cookie es `HttpOnly`, `Secure` y `SameSite`, limitada a la ruta `/v1/auth`. La compartida se define a nivel del dominio principal para que la reciban todos los paneles internos, que deben estar en el mismo sitio que Identity.
- Store usa siempre una cookie distinta de la de los paneles internos.

### 6.4 Consecuencias de compartir sesión

- **Cerrar sesión es compartido:** cerrar sesión en un panel cierra los demás paneles internos del navegador (sus access tokens siguen vigentes hasta 15 minutos).
- **Una cuenta no admin por navegador** en los paneles internos. Tras cada renovación, el frontend compara el `sub` del token nuevo con el del usuario que muestra y, si cambió, reinicia su estado o cierra sesión. Para usar otra cuenta no admin, se usa otro perfil o ventana privada. Las cuentas `admin` no tienen esta limitación, porque su cookie es independiente.
- **Renovaciones simultáneas:** los frontends serializan sus renovaciones entre pestañas (por ejemplo, con la API Web Locks del navegador). La ventana de gracia en Identity queda para una iteración posterior (ver riesgo conocido).

## 7. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Un refresh token se puede usar una sola vez. | Usar el mismo refresh token dos veces: la segunda respuesta es `401`. |
| 2 | Reutilizar un token revocado revoca toda su familia. | Tras la reutilización, el token más reciente de esa familia también responde `401`. |
| 3 | La reutilización en una familia no afecta a otras familias del mismo usuario. | Con dos sesiones, revocar una por reutilización deja la otra funcionando. |
| 4 | Cada login crea una familia nueva. | Dos logins del mismo usuario producen dos `familyId` distintos. |
| 5 | Logout solo cierra la sesión actual; "cerrar todas" cierra todas. | Tras logout, el otro dispositivo renueva sin problema; tras "cerrar todas", ninguno. |
| 6 | Un usuario `disabled` no obtiene ni renueva tokens. | Login y refresh responden `401`. |
| 7 | El access token expira a los 15 minutos y el refresh a los 7 días. | Un access token con `exp` pasado es rechazado por los sistemas; un refresh vencido responde `401`. |
| 8 | Un sistema valida el access token sin llamar a Identity. | Con Identity apagado, un token vigente sigue validando usando el JWKS en caché. |
| 9 | Los errores de login no revelan si el email existe. | Email inexistente y contraseña incorrecta devuelven la misma respuesta. |
| 10 | Superar el límite de intentos responde `429`, sin bloquear la cuenta. | Tras exceder el límite y esperar la ventana, el login vuelve a funcionar. |
| 11 | Solo Identity emite tokens; un token firmado con otra clave es rechazado por todos los sistemas. | Un token firmado con una clave que no está en el JWKS responde `401` en Inventory, Tickets y Store. |
| 12 | En el modo `full`, Inventory y Tickets comparten sesión para cuentas no `admin`. | Tras iniciar sesión en Inventory, abrir Tickets en el mismo navegador entrega un access token sin pedir credenciales. |
| 13 | La sesión de una cuenta `admin` nunca se comparte entre paneles. | Tras iniciar sesión como `admin` en Inventory, Tickets pide credenciales. |
| 14 | En un modo de un solo sistema, cada panel usa su propia cookie. | Con la sesión de un panel, otro panel no obtiene un access token sin iniciar sesión. |
| 15 | Store no comparte cookie con los paneles internos en ningún modo. | Iniciar sesión en Store no abre sesión en Inventory ni en Tickets. |
| 16 | Cambiar la contraseña revoca las demás sesiones del usuario y conserva la actual. | Con dos sesiones, tras el cambio la otra responde `401` al renovar y la actual sigue renovando. |

Pruebas en la Fase 1: las invariantes 11 a 15 se prueban contra Identity con clientes simulados (peticiones con el `Origin` de cada frontend) y con un verificador externo del JWKS; se completan con los sistemas reales en sus fases.

## 8. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Firma asimétrica (RS256) con JWKS | Firma simétrica con secreto compartido | Con secreto compartido cualquier sistema podría fabricar tokens; con clave pública solo Identity firma. |
| Validación local del access token | Consultar a Identity en cada petición | Evita dependencia constante y cuello de botella; sobrevive a una caída de Identity. |
| Refresh token de 7 días con rotación | 30 días / sin rotación | Equilibrio entre comodidad y riesgo; la rotación permite detectar robo. |
| Revocar la familia ante reutilización | Revocar solo el token reutilizado | El atacante puede tener un token más reciente de la misma cadena. |
| Una familia por login (varias sesiones) | Una sola sesión por usuario | Permite usar varios dispositivos a la vez. |
| Logout de la sesión actual + endpoint aparte para todas | Logout siempre global | Cerrar sesión en un dispositivo no debe afectar a los demás. |
| Rate limiting sin bloquear cuentas | Bloqueo de cuenta tras N intentos | Bloquear permitiría a terceros dejar fuera a cualquier usuario. |
| Refresh token en cookie `HttpOnly`, access token en memoria | Ambos en almacenamiento del navegador | Reduce el riesgo de robo de tokens por scripts. |
| Sesión compartida entre Inventory y Tickets en el modo `full` | Sesiones individuales siempre | Mejor experiencia para el personal interno; al ser solo configuración de cookie, volver a sesiones individuales es un cambio de variable. |
| Sesión compartida o individual según el modo de ejecución | Un único comportamiento fijo | Cada sistema debe funcionar solo; la integración es opcional. |
| Sesiones `admin` no compartidas | Admin dentro de la sesión compartida | Una sesión compartida robada no da poder total. |
| Clientes definidos por configuración | Tabla de clientes en la base de datos | Suficiente para el MVP; evita ampliar el modelo de datos. |
| Cliente deducido del `Origin`, con `client` opcional en el cuerpo | Exigir siempre `client` | El navegador ya envía el dato; el campo cubre las herramientas sin navegador. |

## 9. Fuera de alcance (por ahora)

- Lista de sesiones activas visible para el usuario.
- Revocación inmediata de access tokens (lista de tokens revocados).
- Aviso a los demás sistemas cuando se desactiva un usuario, mediante un evento `user.disabled`. Cada sistema guardaría localmente los ids desactivados y los comprobaría en operaciones sensibles (por ejemplo, un pago). En el MVP se acepta la ventana de hasta 15 minutos; este aviso es la mejora futura. Se retoma en el documento de contratos de eventos.
- Restringir un token a sistemas concretos con el claim `aud` (*audience*). Hoy cualquier token válido es aceptado por todos los sistemas, y cada uno decide por los roles.
- Recuperación de contraseña por email ("olvidé mi contraseña"). El cambio de contraseña autenticado sí está en el MVP (ver documento de la API).
- Verificación de email.
- Autenticación de dos factores.
- Inicio de sesión con proveedores externos (Google, etc.).
- Ventana de gracia para dos renovaciones simultáneas con el mismo token (ver riesgo abajo).

### Riesgo conocido

Si un frontend envía dos renovaciones a la vez con el mismo refresh token (por ejemplo, dos pestañas, o Inventory y Tickets con sesión compartida), la segunda parecerá una reutilización y cerrará la sesión. Con sesión compartida es más probable. Se mitiga en el frontend (una sola renovación a la vez entre pestañas) y, si hiciera falta, con una ventana de gracia de pocos segundos en Identity en una iteración posterior.
