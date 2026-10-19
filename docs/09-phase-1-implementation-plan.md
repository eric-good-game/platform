# Plan de implementación de la Fase 1

Documento 9 de la Fase 1. Convierte los documentos 1 a 8 en una secuencia de **hitos** de construcción: qué se hace en cada uno, de qué depende, qué invariantes cierra y cuándo se considera terminado. Es una guía de trabajo, no un cronograma: no estima tiempos.

Vive en `platform/docs`.

Estado: **borrador para revisión**.

## 1. Cómo se usa este plan

- Cada **hito** es un tramo vertical y pequeño: termina con algo que se ejecuta y se prueba, y deja el sistema funcionando.
- Los hitos se hacen **en orden**, salvo los marcados como paralelizables.
- Cada hito se integra por **pull request** en el repositorio que corresponda, con el CI en verde.
- Una invariante se da por cerrada cuando existe una **prueba cuyo nombre lleva el número de la invariante** y esa prueba pasa (documento 8, sección 9).
- Si al implementar se descubre que un documento está equivocado, **se corrige el documento en el mismo pull request**. La documentación no queda atrás del código.
- Tamaño de referencia: **S** (pocas horas), **M** (una o dos sesiones), **L** (varias sesiones).

### Repositorios que se crean

| Repositorio | Contenido |
|---|---|
| `platform` | `docker-compose`, `Makefile`, configuración, documentación transversal |
| `identity` | Servicio Identity (NestJS) y su documentación |
| `event-contracts` | Esquemas de eventos, ejemplos y catálogo |

## 2. Resumen de hitos

| # | Hito | Repositorio | Depende de | Tamaño | Resultado verificable |
|:-:|---|---|---|:-:|---|
| 0 | Preparación | los tres | — | S | Repositorios con README, CI mínimo y convenciones |
| 1 | Plataforma base | `platform` | 0 | M | `make base` levanta PostgreSQL y RabbitMQ sanos |
| 2 | Esqueleto de Identity | `identity` | 0 | M | El servicio arranca, valida su configuración y responde `/health` |
| 3 | Modelo de datos y datos iniciales | `identity` | 1, 2 | M | Migraciones aplicadas y roles, admin y usuarios demo cargados |
| 4 | Claves y JWKS | `identity` | 2 | M | `/.well-known/jwks.json` publica la clave y un verificador valida un token |
| 5 | Autenticación | `identity` | 3, 4 | L | Login, renovación con rotación, cierre de sesión y cookies por cliente |
| 6 | Registro y cuenta propia | `identity` | 5 | M | Registro de clientes, `/v1/me` y cambio de contraseña |
| 7 | Gestión de usuarios y roles | `identity` | 5 | L | CRUD de usuarios y asignación de roles solo para `admin` |
| 8 | Contratos de eventos | `event-contracts` | 0 | M | Esquemas y ejemplos validados por CI (**paralelizable**) |
| 9 | Integración y prueba de humo | `platform`, `identity` | 1 a 7 | M | `make base` con Identity y la prueba de humo en CI |
| 10 | Cierre de la Fase 1 | todos | 1 a 9 | S | Matriz de trazabilidad completa y documentos aprobados |

```text
0 ──► 1 ──────────────┐
 │                    ├──► 3 ──► 5 ──┬──► 6 ──┐
 ├──► 2 ──┬───────────┘      ▲       │        ├──► 9 ──► 10
 │        └──► 4 ────────────┘       └──► 7 ──┘
 └──► 8 (en paralelo) ──────────────────────────┘
```

## 3. Hitos

### Hito 0: Preparación

**Objetivo.** Dejar los repositorios y las herramientas listos para trabajar.

- Crear los tres repositorios en GitHub con README, licencia y `.gitignore`.
- Añadir en `platform` la carpeta `docs` con los documentos 1 a 9.
- Acordar las convenciones: commits en inglés con *Conventional Commits* (`feat:`, `fix:`, `docs:`), ramas `feature/<hito>-<tema>` y rama principal protegida con CI obligatorio.
- Comprobar el entorno local: Docker Desktop, Node, `pnpm` y `make`.
- Configurar un CI mínimo (lint) en cada repositorio.
- Añadir las plantillas de pull request y de issues, un `CONTRIBUTING.md` corto y un `SECURITY.md`.
- Activar Dependabot y la protección de la rama principal (CI obligatorio y sin *push* directo).

**Listo cuando.** Los tres repositorios existen, el CI corre en un pull request de prueba y `secrets/` ya está en el `.gitignore` de `platform`.

### Hito 1: Plataforma base

**Objetivo.** PostgreSQL y RabbitMQ funcionando con un solo comando (documento 7).

- `docker-compose.yml` con la red interna, volúmenes, controles de salud e imágenes de versión fija.
- Script de inicialización de PostgreSQL: bases y usuarios de `identity` y de los servicios futuros, retirando el permiso de conexión público.
- Definición del broker: exchange `events` (*topic*) y `events.dlx`.
- `Makefile` con `base`, `down`, `reset`, `logs` y `setup`.
- `make setup`: genera las contraseñas de las bases y del broker, el par de claves de firma y, sin datos de demostración, la del primer `admin`. Es idempotente.
- Archivos `envs/base.env`, `inventory.env`, `tickets.env`, `store.env` y `full.env` con `SESSION_MODE`, `INTEGRATION_MODE`, `SEED_DEMO_DATA` y `DEMO_PASSWORD`.
- `compose.debug.yml` que expone PostgreSQL en `localhost`.

**Listo cuando.** `make base` deja PostgreSQL y RabbitMQ sanos, el exchange `events` existe y el usuario de la base `inventory` no puede conectarse a la base `identity`.

### Hito 2: Esqueleto de Identity

**Objetivo.** Un servicio NestJS que arranca bien configurado, aunque todavía no haga nada de negocio (documento 8).

- Proyecto con `pnpm`, TypeScript, ESLint y Prettier.
- Estructura de carpetas y módulos vacíos (`auth`, `users`, `roles`, `keys`, `health`, `prisma`, `config`, `common`).
- Configuración validada al arrancar (`@nestjs/config`).
- Registros con `pino` y `correlationId` en cada línea (el origen del `correlationId` se define aquí: se usa la cabecera `X-Correlation-Id` si llega, o se genera una nueva, y se devuelve en la respuesta).
- Filtro global de errores: Problem Details, `code` estable, `errors[]` y `INTERNAL_ERROR` sin detalles.
- Módulo `health` con `GET /health`.
- Documentación OpenAPI con `@nestjs/swagger`.
- Reglas de lint que imponen las invariantes de arquitectura (el dominio no importa NestJS ni Prisma; solo los repositorios usan Prisma).
- `Dockerfile` de varias etapas con usuario sin privilegios.

**Listo cuando.** El servicio no arranca si falta una variable obligatoria, arranca con una configuración válida, `GET /health` responde y toda respuesta devuelve `X-Correlation-Id`.

### Hito 3: Modelo de datos y datos iniciales

**Objetivo.** La base de Identity y las reglas del dominio de usuario (documentos 2 y 3).

- Esquema de Prisma: `User`, `Role`, `UserRole`, `Employee` y `RefreshToken`, con sus restricciones únicas.
- Primera migración, aplicada al arrancar.
- Generación de identificadores UUID v7 en la aplicación.
- Dominio: objetos de valor `Email` y política de contraseña; clase `User` con las invariantes de roles y errores de dominio.
- Repositorio de usuarios (interfaz e implementación con Prisma) y repositorio de roles.
- Hash de contraseñas con `argon2`.
- Seeds idempotentes: `essential` (roles y primer `admin`) y `demo` (los usuarios del documento 8, sección 8).

**Listo cuando.** Las migraciones se aplican en una base vacía, los seeds se pueden ejecutar dos veces sin duplicar, y las pruebas unitarias del dominio pasan sin base de datos.

### Hito 4: Claves y JWKS

**Objetivo.** Firmar tokens y publicar las claves públicas (documento 4, sección 4).

- Módulo `keys`: carga de la clave privada desde un archivo montado, identificador `kid`, firma RS256 con `jose` y construcción del JWKS.
- `GET /.well-known/jwks.json`, cacheable y sin autenticación.
- En esta fase hay **una sola clave activa**; la rotación manual queda descrita en el documento 4, pero no se implementa.
- Verificador externo: un script independiente que descarga el JWKS y valida un token (firma, `iss`, `exp` y `roles`). Será la base de la prueba de humo.

**Listo cuando.** El verificador valida un token firmado por Identity, y rechaza uno firmado con otra clave o vencido. La clave privada no aparece en los registros.

### Hito 5: Autenticación

**Objetivo.** El flujo completo de sesiones (documentos 4 y 5, sección 6.1).

- `POST /v1/auth/login`: credenciales, estado `active`, creación de la familia y el primer refresh token, access token de 15 minutos.
- Respuesta de error uniforme `INVALID_CREDENTIALS` para email inexistente, contraseña incorrecta y usuario desactivado.
- Deducción del cliente por `Origin`, con `client` opcional en el cuerpo (obligatorio sin `Origin`), y comprobación del tipo de cuenta contra el cliente.
- Cookies por cliente y por modo: `SESSION_MODE=separate` o `shared`; las cuentas `admin` con cookie propia; cookie `HttpOnly`, `Secure` y `SameSite`, con ruta `/v1/auth`.
- `POST /v1/auth/refresh`: rotación, detección de reutilización y revocación de la familia.
- `POST /v1/auth/logout` y `POST /v1/auth/logout-all`.
- Límite de intentos por email e IP, con respuesta `429` y sin bloqueo de cuentas.
- Guard que verifica el access token y lee los roles.
- **Pendiente de diseño (`F1-01`/`F1-02`):** decidir el modelo de clientes de Store y corregir la regla cliente ↔ tipo de cuenta, para que `store_manager` y `admin` puedan operar Store (ver documento 5, sección 6.1).

**Listo cuando.** Los escenarios de reutilización, de varias sesiones, de usuario desactivado y de cookie compartida o individual tienen pruebas de integración que pasan con clientes simulados (peticiones con el `Origin` de cada frontend).

### Hito 6: Registro y cuenta propia

**Objetivo.** Los flujos de la cuenta del propio usuario (documento 5).

- `POST /v1/auth/register`: crea solo cuentas `customer`, sin iniciar sesión.
- `GET /v1/me`.
- `POST /v1/me/password`: contraseña actual obligatoria, política de contraseña, límite de intentos y revocación de las demás sesiones.

**Listo cuando.** Una contraseña de 11 caracteres o una común se rechazan con su `code`, y tras el cambio la otra sesión deja de renovar mientras la actual sigue.

### Hito 7: Gestión de usuarios y roles

**Objetivo.** La administración de cuentas, solo para `admin` (documentos 2 y 5).

- `POST /v1/users`: creación atómica del usuario, sus roles y su registro de empleado; un `admin` puede crear otros `admin`.
- `GET /v1/users` con paginación y filtros, y `GET /v1/users/{id}`.
- `PATCH /v1/users/{id}`.
- `PUT /v1/users/{id}/roles`: validación del conjunto final y bloqueo de cambios sobre uno mismo.
- `DELETE /v1/users/{id}`: borrado lógico y revocación de todos los tokens de refresco.
- `GET /v1/roles`.
- Guard de roles que exige `admin` en `/v1/users`.

**Listo cuando.** Las combinaciones de roles prohibidas responden `409 ROLE_INCOMPATIBLE`, un `employee` recibe `403` en `/v1/users`, y un admin no puede desactivarse ni cambiarse los roles a sí mismo.

### Hito 8: Contratos de eventos (paralelizable)

**Objetivo.** El repositorio de esquemas de la Fase 1 (documento 6).

- Estructura `envelope/`, `events/<tipo>/` y `catalog.md`.
- Esquema del sobre y esquemas y ejemplos de `stock.adjusted`, `stock.low`, `stock.reserved` y `stock.failed`.
- CI que valida que cada esquema es válido y que cada ejemplo cumple el suyo.
- Cada ejemplo cumple las convenciones: UUID v7, fechas en UTC y sin datos sensibles.

**Listo cuando.** El CI falla al romper un esquema o al alterar un ejemplo para que no lo cumpla.

### Hito 9: Integración y prueba de humo

**Objetivo.** Que quien clone solo `platform` vea todo funcionando (documento 7, sección 9).

- Flujo de GitHub Actions en `identity` que construye y publica la imagen en GitHub Container Registry (`latest` y *hash* del commit).
- Identity añadido a `docker-compose.yml` con su control de salud, su clave montada y las migraciones y seeds al arrancar.
- `compose.dev.yml` que construye Identity desde la carpeta local.
- Prueba de humo: levanta `make base`, espera a que todo esté sano, inicia sesión con `inventory.manager@example.com`, descarga el JWKS y verifica el token con el verificador del hito 4.
- Flujo de CI en `platform`: valida el Compose, ejecuta la prueba de humo y comprueba que no se haya versionado ningún secreto.
- Definir en `platform` los flujos de CI reutilizables, y hacer que `identity` y `event-contracts` los invoquen.
- Activar CodeQL, Trivy y Gitleaks como comprobaciones obligatorias de los pull requests.
- Configurar release-please y publicar la primera *release* (`0.1.0`), con la imagen etiquetada con su versión.
- README principal con el diagrama, la descripción de los modos y las credenciales de demostración.

**Listo cuando.** En un equipo sin nada más que `platform` clonado, `make base` funciona, y la prueba de humo pasa en el CI de `platform`.

### Hito 10: Cierre de la Fase 1

**Objetivo.** Dejar la fase demostrablemente completa.

- Completar la matriz de trazabilidad (sección 4) y comprobar que cada invariante de la Fase 1 tiene su prueba.
- Revisar los ocho documentos contra lo implementado y pasarlos de «borrador» a «aprobado».
- Anotar lo aprendido y lo que cambia en la Fase 2 (valores de referencia de infraestructura, ajustes de documentos).
- Revisar que cada mejora futura siga registrada en el «Fuera de alcance» de su documento.
- Extraer las decisiones principales a `platform/docs/adr/`, como registros de decisiones de arquitectura (contexto, decisión y consecuencias).
- Completar el README de cada repositorio con diagrama, insignias de CI y de cobertura, y capturas o ejemplos de uso.

**Listo cuando.** El criterio de terminado del documento 1 se cumple de forma automatizada.

## 4. Trazabilidad: invariantes por hito

Qué hito cierra cada invariante. «Fase 2» o posterior significa que depende de componentes que aún no existen y se prueba cuando existan (ver la nota «Cuándo se prueban» de cada documento).

| Documento | Invariantes y hito que las cierra |
|---|---|
| 2. Roles y permisos | 1 → hitos 3 y 5; 2 y 4 → hitos 3 y 7; 3 y 5 → Fase 2 (cada sistema) |
| 3. Modelo de datos | 1 → hitos 3 y 6; 2 → hitos 3 y 5; 3 y 5 → hito 7; 4 → hito 5; 6 → hitos 3 y 7; 7 y 8 → hito 3 |
| 4. Flujo de autenticación | 1 a 7, 9, 10 y 12 a 15 → hito 5; 8 y 11 → hitos 4 y 9 (verificador externo); 16 → hito 6 |
| 5. API | 1 y 2 → hito 2; 3, 5 a 9, 13 y 18 → hito 7; 4, 15 a 17 → hito 6; 10, 11 y 14 → hito 5; 12 → hitos 5 y 7; 19 → hito 2 |
| 6. Contratos de eventos | 1, 2, 3, 8 y 10 → hito 8; 4 a 7, 9 y 11 a 15 → Fase 2 o posterior |
| 7. Infraestructura | 1 a 7 y 11 → hito 1; 8 → hitos 1 y 9; 9, 10 y 24 → hito 3; 19 a 21 y 25 a 26 → hito 9; 12 a 18 → Fase 2 o posterior; 22 y 23 → Fases 4 y 6 |
| 8. Estructura de Identity | 1 a 6, 8 y 9 → hito 2; 7 → hitos 2 y 7; 10 → hito 4; 11 y 13 → hito 3; 12 → todos los hitos; 14 → hitos 2 y 9; 15 → hito 2 |
| 1. Visión y alcance | 1 → hito 1; 2 → hito 8; 3 → Fase 2; 4 a 7 → hito 10 |

## 5. Riesgos y puntos de atención

| Riesgo | Qué hacer |
|---|---|
| Las cookies `Secure` en `http://localhost` | Los navegadores modernos las aceptan en `localhost`; hay que probarlo en el hito 5 con un frontend simulado y no solo con Postman. |
| En `localhost` las cookies no se aíslan por puerto | Los nombres distintos por cliente (`refresh_inventory`, `refresh_tickets`…) son los que separan las sesiones; las pruebas del hito 5 lo comprueban. |
| Postman no envía `Origin` | Para eso existe el campo `client` en el cuerpo; las pruebas cubren los dos caminos. |
| La imagen de Identity en GitHub Container Registry debe poder descargarse sin credenciales | Hacer público el paquete; sin eso, `make base` falla en un equipo ajeno (hito 9). |
| Plataformas distintas (macOS con Docker Desktop, Linux en CI) | El hito 9 ejecuta la prueba de humo en Linux, así que las diferencias salen en el CI y no al final. |
| Un documento se queda desfasado del código | Regla del plan: se corrige en el mismo pull request. |
| El modelo de clientes de Store deja fuera a `store_manager` y a `admin` | Decidirlo en el hito 5 antes de implementar el login (`F1-01`/`F1-02`, documento 5, sección 6.1). |

## 6. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Cada hito se integra con el CI en verde. | Ningún pull request de un hito se fusiona con el CI fallando. |
| 2 | Cada hito deja la plataforma ejecutable. | Tras cada hito, `make base` sigue levantando sin errores. |
| 3 | Una invariante solo se da por cerrada con una prueba rastreable. | El número de la invariante aparece en el nombre de una prueba que pasa. |
| 4 | Los cambios llegan por pull request. | La rama principal de cada repositorio rechaza *push* directos. |
| 5 | Los commits siguen *Conventional Commits* en inglés. | Un chequeo del CI rechaza mensajes que no cumplen el formato. |
| 6 | Un cambio de comportamiento actualiza el documento afectado en el mismo pull request. | La descripción del pull request enlaza el documento modificado cuando el comportamiento cambia. |
| 7 | La matriz de trazabilidad no deja invariantes sin hito. | Cada invariante de la Fase 1 aparece en la sección 4. |
| 8 | Desde el hito 9, los escaneos de seguridad bloquean los pull requests con hallazgos graves. | Un pull request con una vulnerabilidad crítica o un secreto no se puede fusionar. |

## 7. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Hitos verticales que terminan en algo ejecutable | Construir por capas (primero toda la base de datos, luego toda la API) | Cada hito se prueba de punta a punta y se detectan los problemas pronto. |
| Plataforma base antes que Identity | Identity antes que la plataforma | Identity necesita PostgreSQL y las claves ya generadas. |
| Autenticación antes que la gestión de usuarios | Gestión de usuarios primero | Los endpoints de administración dependen del guard y de los tokens. |
| Contratos de eventos en paralelo | Después de Identity | No dependen de Identity y se pueden hacer cuando haya un hueco. |
| Una sola clave de firma activa en la Fase 1 | Implementar la rotación de claves | La rotación está documentada; implementarla ahora añade complejidad sin beneficio para la demo. |
| Prueba de humo al final, tras los demás hitos | Probar la integración solo al cerrar la fase | Con el verificador del hito 4, la integración se prueba de forma temprana y se amplía en el hito 9. |
| Sin estimaciones de tiempo | Cronograma por semanas | Los tamaños de referencia bastan; el ritmo depende de la disponibilidad. |
| Flujos de CI reutilizables en `platform` | CI duplicado en cada repositorio | Con tres repositorios (y más después) evita duplicar y que diverjan. |
| ADR extraídos al cierre de la fase | ADR desde el primer día | Las decisiones ya están en las tablas de cada documento; se extraen cuando están confirmadas por la implementación. |

## 8. Fuera de alcance (por ahora)

- Estimación de tiempos y cronograma con fechas.
- Un tablero de gestión del proyecto (issues, columnas, etiquetas).
- Planes de implementación de las fases 2 a 6, que se escriben al empezar cada fase.
- Automatización de la publicación de versiones (*releases*) y del registro de cambios.
