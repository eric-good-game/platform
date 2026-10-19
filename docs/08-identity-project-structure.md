# Identity: estructura del proyecto

Documento 8 de la Fase 1. Define cómo se organiza el código del servicio Identity: tecnologías, carpetas, módulos, capas, nivel de DDD aplicado, manejo de errores, configuración, pruebas y contenedor. **Este documento depende de la tecnología** (NestJS, Prisma, PostgreSQL).

Vive en `identity/docs`, junto al código del servicio.

Estado: **borrador para revisión**.

## 1. Tecnologías

| Pieza | Elección | Notas |
|---|---|---|
| Framework | NestJS con TypeScript | Se fija la versión mayor al crear el proyecto |
| Base de datos | PostgreSQL | Instancia compartida de la plataforma, base `identity` (documento 7) |
| ORM y migraciones | Prisma | `schema.prisma` y Prisma Migrate |
| Hash de contraseñas | `argon2` | |
| JWT y JWKS | `jose` | RS256, `kid`, construcción del JWKS |
| Validación de entrada | `class-validator` y `class-transformer` | Sobre DTOs |
| Configuración | `@nestjs/config` con validación al arrancar | |
| Rate limiting | `@nestjs/throttler` | Por email e IP en login (documento 4) |
| Documentación de la API | `@nestjs/swagger` | OpenAPI generado desde decoradores |
| Registros | `pino` en JSON | Con `correlationId` en cada línea, tomado de la cabecera `X-Correlation-Id` (ver sección de configuración común) |
| Salud | `@nestjs/terminus` | Comprueba la conexión a PostgreSQL |
| Gestor de paquetes | `pnpm` | |
| Pruebas | Jest, Supertest y Testcontainers | Ver sección 9 |
| Calidad | ESLint, Prettier y *pre-commit* con lint | |

## 2. Organización por funcionalidad

El código se agrupa **por área funcional**, no por tipo de archivo. Cada carpeta contiene su módulo, controlador, servicio y DTOs.

```text
identity/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── auth/                  # login, register, refresh, logout, cambio de contraseña (POST /v1/me/password)
│   │   ├── domain/            # sesión y refresh token (reglas de rotación y reutilización)
│   │   ├── dto/
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── auth.guard.ts      # verifica el access token
│   │   ├── sessions.repository.ts          # interfaz
│   │   └── prisma-sessions.repository.ts   # implementación
│   ├── users/                 # CRUD de usuarios, GET /v1/me, asignación de roles
│   │   ├── domain/            # User, Email, errores de dominio
│   │   ├── dto/
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── users.repository.ts             # interfaz
│   │   └── prisma-users.repository.ts      # implementación
│   ├── roles/                 # catálogo de roles (GET /v1/roles), con su repositorio
│   ├── keys/                  # claves de firma, firma de tokens y JWKS
│   ├── health/                # endpoint de salud
│   ├── prisma/                # módulo y servicio del cliente de Prisma
│   ├── config/                # esquema y validación de variables de entorno
│   └── common/                # filtro de errores, guards de roles, paginación, utilidades
├── prisma/
│   ├── schema.prisma
│   ├── migrations/
│   └── seeds/
│       ├── essential.ts       # roles y primera cuenta admin
│       └── demo.ts            # usuarios de ejemplo
├── test/                      # pruebas de integración y de contrato
├── docs/                      # documentación del servicio
├── Dockerfile
└── package.json
```

Los módulos sin reglas de negocio propias (`roles`, `keys`, `health`) son planos: no tienen carpeta `domain`. `roles` conserva su repositorio; `health` es la única excepción a la invariante 2, porque usa el indicador de base de datos de `@nestjs/terminus` sobre el servicio de `prisma`.

## 3. Módulos y dependencias

| Módulo | Responsabilidad | Usa |
|---|---|---|
| `auth` | Flujos de autenticación, sesiones y cambio de contraseña | `users`, `keys` |
| `users` | Usuarios, empleados y asignación de roles | `roles` |
| `roles` | Catálogo de roles | `prisma` |
| `keys` | Cargar la clave privada, firmar tokens, publicar el JWKS | `config` |
| `health` | Estado del servicio | `prisma` |
| `prisma` | Conexión a la base de datos | `config` |
| `common` | Piezas transversales sin lógica de negocio | |

Reglas de dependencia:

- `keys` no conoce usuarios ni sesiones: recibe *claims* y devuelve un token firmado.
- `auth` usa `users` por su servicio exportado; nunca accede a las tablas de usuarios directamente.
- Los repositorios de un módulo no los usa otro módulo; se pasa por su servicio.
- `common` no depende de ningún módulo funcional.

## 4. Capas y responsabilidades

| Pieza | Responsabilidad | No debe |
|---|---|---|
| **Controller** | Recibe la petición, valida la entrada con el DTO, llama al servicio, devuelve la respuesta | Contener reglas de negocio ni acceder a la base |
| **Service** | Orquesta: carga, ejecuta la regla de dominio, guarda | Usar Prisma directamente |
| **Dominio** | Protege las invariantes con clases sin dependencias de NestJS ni de Prisma | Conocer HTTP, la base de datos o el framework |
| **Repository (interfaz)** | Define qué operaciones de persistencia necesita el servicio | |
| **Repository (Prisma)** | Implementa la interfaz y mapea entre los registros de Prisma y las clases de dominio | Contener reglas de negocio |
| **DTO** | Forma y validación de lo que entra y sale por la API | Reutilizarse como clase de dominio |
| **Guard** | Decide si la petición pasa: access token válido y roles requeridos | |
| **Filter** | Traduce los errores al formato Problem Details | |

Los servicios dependen de la **interfaz** del repositorio y NestJS inyecta la implementación de Prisma. En las pruebas unitarias se inyecta una implementación en memoria.

## 5. Nivel de DDD aplicado

Criterio general: cada servicio evalúa qué patrones tácticos de DDD aplica según la cantidad de invariantes que protege. Identity tiene pocas zonas con reglas reales, así que aplica un **DDD ligero**.

**DDD estratégico.** Cada servicio es un *bounded context* con su propio modelo y su base. Los eventos son el lenguaje publicado entre contextos. El vocabulario es el de los documentos de la Fase 1.

**DDD táctico.** Solo en las zonas con invariantes:

| Zona | Patrón | Reglas que protege |
|---|---|---|
| Usuario y roles | Clase de dominio `User` | Exclusión de `customer` y `employee`; roles de área solo para `employee`; un admin no se desactiva ni cambia sus propios roles (documentos 2 y 5) |
| Sesión y refresh token | Clase de dominio de sesión | Rotación, familia y detección de reutilización (documento 4) |
| Email y contraseña | Objetos de valor `Email` y política de contraseña | Normalización del email; mínimo 12, máximo 128, no común, no igual al email (documento 5) |

Fuera de esas zonas el código es simple, sin capa de dominio.

**No se aplica en Identity:** CQRS, event sourcing, eventos de dominio internos ni una capa de aplicación aparte por módulo. Identity no publica eventos en la Fase 1.

**Coste asumido:** el repositorio de Prisma mapea entre el registro y la clase de dominio. Es poco código con un puñado de clases; por eso el dominio se limita a las zonas con reglas.

## 6. Manejo de errores

Las reglas de negocio lanzan **errores de dominio** que no conocen HTTP. Un filtro global los traduce a Problem Details (documento 5). Así el dominio se prueba sin NestJS y el formato de error vive en un solo sitio.

| Error de dominio | `code` | Estado |
|---|---|---|
| Combinación de roles prohibida | `ROLE_INCOMPATIBLE` | `409` |
| Datos de empleado en una cuenta que no es `employee` | `EMPLOYEE_DATA_NOT_ALLOWED` | `409` |
| Falta el bloque de empleado | `EMPLOYEE_DATA_REQUIRED` | `422` |
| Admin sobre sí mismo | `CANNOT_MODIFY_SELF` | `409` |
| Email duplicado | `EMAIL_ALREADY_EXISTS` | `409` |
| Refresh token inválido o reutilizado | `INVALID_REFRESH_TOKEN` | `401` |
| Contraseña que no cumple la política | `VALIDATION_FAILED`, con `errors[]` | `422` |

Además del filtro de errores de dominio, el filtro global convierte:

- los errores de `class-validator` en `VALIDATION_FAILED` con `errors[]`;
- las excepciones HTTP de NestJS y del *throttler* en sus códigos del catálogo;
- cualquier error inesperado en `INTERNAL_ERROR`, **sin exponer detalles internos**, y lo registra con su `correlationId`.

### Correlación

Un *middleware* (`common`) lee `X-Correlation-Id`: si es un UUID válido lo conserva; si falta o no es válido, genera uno. Lo guarda en el contexto de la petición (para `pino` y para los eventos que se publiquen) y lo devuelve en la cabecera de la respuesta.

## 7. Configuración

- Todas las variables se validan **al arrancar**. Si falta una o es inválida, el servicio no arranca y dice cuál.
- Variables de referencia: `DATABASE_URL`, `PORT`, ruta de la clave privada de firma, identificador `kid` activo, emisor (`iss`) de los tokens, orígenes de cliente permitidos, `SESSION_MODE`, `SEED_DEMO_DATA`, `INITIAL_ADMIN_EMAIL`, `INITIAL_ADMIN_PASSWORD` y `DEMO_PASSWORD`.
- Las variables no secretas vienen de `envs/<modo>.env` y los secretos de `secrets/` de la plataforma (documento 7). `INITIAL_ADMIN_PASSWORD` es la contraseña pública `DEMO_PASSWORD` cuando hay datos de demostración, y la generada por `make setup` cuando no los hay.
- La clave privada se lee de un archivo montado de solo lectura; nunca se escribe en los registros.

## 8. Migraciones y datos iniciales

- Migraciones con **Prisma Migrate**, aplicadas al arrancar en demo (documento 7).
- Dos scripts separados, ambos **idempotentes**:
  - `essential`: catálogo de roles y primera cuenta `admin`. Siempre.
  - `demo`: usuarios de ejemplo de cada rol. Solo con `SEED_DEMO_DATA=true`.
- Los UUID v7 se generan en la aplicación, no en la base.

### Usuarios de demostración

Todos usan la contraseña pública `DEMO_PASSWORD`. Los emails usan el dominio reservado `example.com`.

| Email | Roles | Datos de empleado | Para qué sirve |
|---|---|---|---|
| `admin@example.com` | `admin` | No (primera cuenta, esencial) | Gestión de usuarios; no comparte sesión |
| `inventory.manager@example.com` | `employee`, `inventory_manager` | Ana Pérez, Encargada de almacén, Logística, 2025-03-15 | Usuario de la prueba de humo |
| `warehouse.clerk@example.com` | `employee` | Luis Gómez, Auxiliar de almacén, Logística, 2025-06-02 | Empleado sin rol de área |
| `support.agent@example.com` | `employee`, `support_agent` | Marta Ruiz, Agente de soporte, Soporte, 2024-11-20 | Rol de área de Tickets |
| `store.manager@example.com` | `employee`, `store_manager` | Diego Herrera, Encargado de tienda, Ventas, 2024-09-10 | Rol de área de Store |
| `multi.area@example.com` | `employee`, `inventory_manager`, `support_agent` | Carla Soto, Coordinadora de operaciones, Operaciones, 2023-05-08 | Roles de área apilados |
| `customer@example.com` | `customer` | No | Cliente de Store |
| `disabled.customer@example.com` | `customer`, con estado `disabled` | No | Prueba de login y refresh de una cuenta desactivada |

La lista se amplía en las fases siguientes cuando cada sistema necesite más casos.

## 9. Pruebas

| Nivel | Qué prueba | Cómo |
|---|---|---|
| **Unitarias** | Las clases de dominio y los servicios, con repositorios en memoria | Jest, sin base de datos ni NestJS |
| **Integración** | La API completa contra PostgreSQL real | Supertest y Testcontainers |
| **Contrato** | Que el JWKS y los tokens cumplen lo que promete el documento 4 | Verifica la firma con **solo** el JWKS, igual que la prueba de humo del documento 7 |

Cada invariante de los documentos 2 a 5 tiene al menos una prueba, y el **número de la invariante aparece en el nombre del test** para poder rastrearlas.

Las pruebas de integración usan una base limpia por ejecución y no dependen de los datos de demostración.

## 10. Contenedor y ejecución

- El `Dockerfile` es de **varias etapas**: construye con todas las dependencias y la imagen final solo lleva lo necesario para ejecutar.
- Se ejecuta como usuario sin privilegios.
- El servicio expone el endpoint de salud que usa el `healthcheck` del documento 7.
- La imagen se publica desde la rama principal tras pasar el CI (documento 7).

## 11. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | El código se organiza por funcionalidad. | Cada módulo funcional contiene su propio controlador, servicio y DTOs. |
| 2 | Los servicios no usan Prisma directamente. | Ningún archivo fuera de `prisma/` y de los repositorios Prisma importa el cliente de Prisma (comprobado con una regla de lint); la única excepción es el indicador de salud de `health`. |
| 3 | El dominio no depende de NestJS ni de Prisma. | Ningún archivo de `domain/` importa esos paquetes (regla de lint). |
| 4 | Un módulo no usa el repositorio de otro. | Las dependencias entre módulos pasan por servicios exportados. |
| 5 | `keys` no conoce usuarios ni sesiones. | El módulo no importa clases de `users` ni de `auth`. |
| 6 | Las reglas de negocio lanzan errores de dominio sin HTTP. | Las clases de `domain/` no mencionan códigos de estado. |
| 7 | Todo error de la API sale en formato Problem Details con `code` estable. | Una prueba de integración recorre cada caso del catálogo y verifica el formato. |
| 8 | Un error inesperado no expone detalles internos. | Forzar un fallo devuelve `INTERNAL_ERROR` sin pila ni mensajes de base de datos. |
| 9 | El servicio no arranca con configuración inválida. | Omitir una variable obligatoria detiene el arranque indicando cuál falta. |
| 10 | La clave privada no aparece en los registros ni en el repositorio. | Una búsqueda en los registros de una ejecución y en Git no la encuentra. |
| 11 | Los datos iniciales son idempotentes. | Ejecutar `essential` y `demo` dos veces no duplica roles ni usuarios. |
| 12 | Cada invariante de los documentos 2 a 5 tiene una prueba rastreable. | El número de la invariante aparece en el nombre de al menos un test. Las que dependen de otros sistemas se prueban en Identity con un cliente simulado y se completan en la fase de cada sistema. |
| 13 | Las pruebas unitarias del dominio no requieren base de datos. | Se ejecutan con la base detenida. |
| 14 | La imagen no se ejecuta como administrador. | El contenedor corre con un usuario sin privilegios. |
| 15 | El `correlationId` de cada petición se conserva o se genera y se devuelve. | Con `X-Correlation-Id` válido, la respuesta y las líneas de registro llevan ese valor; sin él, se genera un UUID. Los errores también lo devuelven. |

## 12. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Organizar por funcionalidad | Por tipo de archivo | Cada módulo se entiende de un vistazo; es lo que recomienda NestJS y escala mejor. |
| Repository propio sobre Prisma | Servicios con Prisma directo | Permite probar los servicios sin simular Prisma y separa reglas de consultas. |
| DDD ligero en zonas con invariantes | Sin DDD / DDD completo | Sin DDD dejaría las invariantes dispersas; completo añade mapeos y ceremonia que Identity no justifica. |
| `class-validator` con DTOs | Zod | Es el estándar en NestJS y el más conocido; Zod exige una integración extra. |
| `jose` para JWT y JWKS | `@nestjs/jwt` con Passport | Soporte nativo de RS256, `kid` y JWKS; el mismo estilo servirá en otros servicios. |
| Guards propios | Passport | Nuestra verificación es simple y Passport añade capas innecesarias. |
| Módulo `keys` separado | Criptografía dentro de `auth` | Aísla la criptografía y facilita la rotación futura de claves. |
| Validar la configuración al arrancar | Validar al usarla | Un servicio mal configurado falla de inmediato y con un mensaje claro. |
| Errores de dominio traducidos por un filtro | Lanzar excepciones HTTP desde el dominio | El dominio no depende de HTTP y el formato de error vive en un solo lugar. |
| Testcontainers para integración | Base en memoria o simulada | Prueba contra el mismo motor que se usa de verdad. |
| `pnpm` | `npm` | Más rápido y con un almacén de dependencias eficiente. |

## 13. Fuera de alcance (por ahora)

- CQRS, event sourcing y eventos de dominio internos.
- Capa de aplicación separada por módulo (arquitectura hexagonal completa).
- Publicación de eventos y `outbox` en Identity (llegará con `user.disabled`).
- Rotación automática de claves de firma.
- Métricas y trazas distribuidas (OpenTelemetry).
- Un monorepo con paquetes compartidos entre servicios NestJS.
- Pruebas de carga y de mutación.
