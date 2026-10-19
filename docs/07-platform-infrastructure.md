# Infraestructura de la plataforma

Documento 7 de la Fase 1. Define cómo se ejecuta y se conecta todo: modos de ejecución, servicios y red, bases de datos, broker, outbox, configuración y secretos, datos de demostración y CI. A diferencia de los anteriores, **este documento sí menciona tecnologías concretas** (Docker Compose, PostgreSQL, RabbitMQ, GitHub Actions).

Vive en el repositorio `platform`, junto con el `docker-compose`, el `Makefile` y el resto de la configuración compartida.

Estado: **borrador para revisión**.

## 1. Principios

- **Un solo comando por modo.** Cualquiera debe ver el sistema funcionando en minutos, clonando solo `platform`.
- **Cada sistema funciona solo.** La plataforma (PostgreSQL, RabbitMQ, Identity) es lo único de lo que dependen los sistemas; ninguno depende de otro sistema principal.
- **La integración es opcional.** En los modos de un solo sistema no hay suscriptores para los eventos de los demás, y nada falla.
- **Ningún secreto real en Git.**
- **Todo lo que afecta a varios servicios se define aquí**, salvo los contratos de eventos, que viven en su propio repositorio (`event-contracts`); lo que es de un servicio vive en su repositorio.

## 2. Modos de ejecución

El `docker-compose` usa **perfiles** para decidir qué servicios arrancan. Un servicio sin perfil arranca siempre; uno con perfil arranca solo si ese perfil está activo.

| Perfil | Qué levanta |
|---|---|
| *(sin perfil, siempre)* | PostgreSQL, RabbitMQ e Identity |
| `inventory` | Inventory (API y frontend) |
| `tickets` | Tickets (API y frontend) |
| `store` | Store (API y frontend) |
| `reports` | Reports |
| `notifications` | Notifications y n8n |
| `full` | Todo lo anterior, con integración y sesión compartida |

Los perfiles `inventory`, `tickets` y `store` son **sistemas autónomos**. Los perfiles `reports` y `notifications` son **complementos**: se suman a cualquier sistema y también funcionan con la plataforma base sola, aunque sin eventos que procesar. Se pueden activar varios perfiles a la vez.

Qué existe en cada fase:

| Servicio | Fase | Perfil |
|---|:-:|---|
| PostgreSQL, RabbitMQ, Identity | 1 | Siempre |
| Inventory (API y Angular) | 2 | `inventory`, `full` |
| Store (API y Next.js) | 3 | `store`, `full` |
| Reports | 4 | `reports`, `full` |
| Tickets (API y Angular) | 5 | `tickets`, `full` |
| Notifications y n8n | 6 | `notifications`, `full` |

Cada complemento **solo procesa los eventos que existan en el modo en que corre**. Reports con solo Inventory recibe eventos de stock; si luego se levanta Store, empieza a recibir también los de pedidos. Un sistema ausente simplemente no publica, y nada falla.

### Cómo se cambia la configuración de cada modo

Un perfil **decide qué servicios arrancan, pero no cambia su configuración**. Hay variables que dependen del modo (sesión compartida, integración entre sistemas), así que cada modo tiene su archivo de variables y un `Makefile` los une en un solo comando:

```text
make base                                  # solo PostgreSQL, RabbitMQ e Identity (Fase 1)
make inventory                             # base + inventory
make tickets                               # base + tickets
make store                                 # base + store
make inventory WITH="reports"              # sistema + complemento
make inventory WITH="reports notifications"
make full                                  # todo, con integración y sesión compartida
make down                                  # detiene todo
make reset                                 # detiene todo y borra los datos
make logs                                  # sigue los registros
```

Cada objetivo de arranque ejecuta, por dentro, `docker compose --env-file envs/<modo>.env --profile <modo> [--profile <complemento>] up` y antes ejecuta `make setup`, que genera los secretos si no existen (sección 7). Los complementos de `WITH` solo añaden perfiles; no cambian el archivo de variables, que lo decide el sistema.

Variables que cambian entre modos (nombres de referencia):

| Variable | Modos de un solo sistema | `full` |
|---|---|---|
| `SESSION_MODE` | `separate`: cada panel con su cookie | `shared`: inventory y tickets comparten cookie (ver documento de flujo de autenticación) |
| `INTEGRATION_MODE` | `standalone`: cada sistema usa sus adaptadores locales | `integrated`: los sistemas se comunican por eventos |
| `SEED_DEMO_DATA` | `true` | `true` |

## 3. Servicios y red

- Todos los servicios comparten una **red interna** de Docker. Se comunican por nombre de servicio (`postgres`, `rabbitmq`, `identity`).
- Solo se publican hacia el equipo anfitrión los puertos que un humano necesita: las APIs y frontends, y la consola web de RabbitMQ. **PostgreSQL no se publica por defecto.** Un archivo adicional de Compose lo expone en `localhost` para depuración.
- Cada servicio tiene un **control de salud** (*healthcheck*) y sus dependientes esperan a que esté sano antes de arrancar (`depends_on` con `condition: service_healthy`):

| Servicio | Comprobación |
|---|---|
| PostgreSQL | `pg_isready` |
| RabbitMQ | `rabbitmq-diagnostics -q ping` |
| Identity | Endpoint de salud propio |

- Las imágenes de terceros (PostgreSQL, RabbitMQ) se fijan a una **versión mayor concreta**, nunca a `latest`.
- Los datos de PostgreSQL y RabbitMQ se guardan en **volúmenes** de Docker. `make reset` los borra.

## 4. Bases de datos

Una **única instancia de PostgreSQL** con **una base de datos por servicio**.

| Base | Servicio | Fase |
|---|---|:-:|
| `identity` | Identity | 1 |
| `inventory` | Inventory | 2 |
| `store` | Store | 3 |
| `reports` | Reports | 4 |
| `tickets` | Tickets | 5 |

Reglas:

- Cada base tiene su **propio usuario**, con permisos solo sobre esa base. Se retira el permiso de conexión público a todas las bases, de modo que el usuario de un servicio no puede conectarse a la base de otro.
- Un script de inicialización crea las bases y los usuarios la **primera vez** que arranca la instancia. Lo hace aunque el perfil del servicio no esté activo: una base vacía no cuesta nada. Un servicio nuevo añade su entrada al script.
- Cada servicio gestiona sus **propias migraciones** y las aplica al arrancar. Es válido para demo y desarrollo; no lo sería para producción.
- Ningún servicio lee la base de otro. La regla se mantiene en lo lógico por los usuarios separados, aunque la instancia sea compartida.

Consecuencias de compartir instancia:

- Un fallo o una saturación de la instancia afecta a todos los servicios.
- Todos usan la misma versión de PostgreSQL.
- Cambiar el motor de un servicio concreto requeriría un contenedor propio para él.

## 5. Broker (RabbitMQ)

### 5.1 Topología

```text
Publicador ──► exchange "events" (topic) ──► cola "<consumidor>.events" ──► Consumidor
                       │                              │
                       │                              └─ tras N intentos fallidos
                       │                                          ▼
                       └─ exchange "events.dlx" ──► cola "<consumidor>.events.dlq"
```

| Pieza | Regla |
|---|---|
| **Exchange `events`** | De tipo *topic*, duradero. Lo crea la **plataforma** al arrancar el broker, para que exista aunque no haya ningún consumidor. |
| **Routing key** | El `type` del evento, tal cual (`stock.reserved`). La versión va en el sobre, no en la routing key. |
| **Cola por consumidor** | Una por servicio consumidor, `<consumidor>.events` (por ejemplo, `store.events`). La declara **el propio consumidor al arrancar**, junto con sus *bindings*. |
| **Bindings** | Con patrones (`stock.*` recibe todos los eventos de stock, `order.paid` solo ese). |
| **Tipo de cola** | Duradera y de tipo *quorum*, con límite de entregas. |
| **Mensajes** | Persistentes. El publicador espera la **confirmación del broker** (*publisher confirms*) y el consumidor confirma (*ack*) manualmente tras procesar. |
| **Exchange `events.dlx`** | Recibe los mensajes que se rinden tras N intentos. Cada consumidor declara su cola `<consumidor>.events.dlq` enlazada a él. |

Ejemplo de bindings (referencia):

| Consumidor | Bindings |
|---|---|
| `store.events` | `stock.reserved`, `stock.failed` |
| `reports.events` | `stock.*`, `order.*`, `ticket.*` |
| `notifications.events` | `stock.low`, `order.paid`, `ticket.*` |

### 5.2 Qué ocurre con los mensajes

- Un evento publicado cuando **no hay ninguna cola enlazada** se descarta: no tenía interesados. Eso es lo que hace opcional la integración.
- Si un consumidor está caído, su cola conserva los mensajes hasta que vuelva.
- Los eventos publicados **antes de que un consumidor arranque por primera vez** no se conservan, porque su cola todavía no existía.
- Una cola cuyo consumidor deja de ejecutarse (por ejemplo, al cambiar de modo) sigue acumulando mensajes. Se limita al implementar el primer consumidor (ver sección 11).

### 5.3 Reintentos y mensajes fallidos

| Situación | Qué hace el consumidor |
|---|---|
| Error transitorio (la base no responde, un fallo puntual) | Rechaza el mensaje para que se reentregue. Tras **N intentos** (referencia: 5), el broker lo envía a la cola de fallidos |
| Mensaje inválido para un `type` y `version` que sí soporta (no cumple el esquema) | Lo rechaza **sin reintentar**: va directo a la cola de fallidos |
| `type` o `version` que no soporta | Lo confirma, lo ignora y lo registra en el log (ver documento de eventos) |

Los mensajes fallidos se **revisan a mano** desde la consola de RabbitMQ en el MVP. Reenviarlos de forma automática queda fuera de alcance.

## 6. Outbox e inbox

Un servicio no puede guardar en su base de datos y publicar en el broker en una sola transacción. Para no perder eventos ni publicar eventos de cambios que se revirtieron, se usa el patrón **outbox**.

### 6.1 Outbox (servicios que publican)

Cada servicio publicador tiene una tabla `outbox` en **su propia base**. El evento se inserta **en la misma transacción** que el cambio de datos que lo origina.

| Columna | Descripción |
|---|---|
| `id` | `id` del evento (UUID v7). Clave primaria. |
| `type`, `version` | Tipo y versión del evento. |
| `occurredAt` | Cuándo ocurrió el hecho. |
| `correlationId`, `causationId` | Trazabilidad (`causationId` puede estar vacío). |
| `payload` | Contenido del evento (JSON). |
| `createdAt` | Cuándo se insertó. |
| `publishedAt` | Vacío hasta que el broker confirma la publicación. |

El `source` del sobre no se guarda: lo añade el publicador a partir de su propia configuración.

**Publicador (proceso dentro del propio servicio):**

1. Cada segundo, aproximadamente, toma un lote de eventos pendientes (`publishedAt` vacío), ordenados por `id`, con `FOR UPDATE SKIP LOCKED` para que varias instancias del servicio no tomen las mismas filas.
2. Publica cada uno en el exchange `events` y espera la confirmación del broker.
3. Solo entonces marca la fila como publicada.
4. Si el broker no está disponible, las filas siguen pendientes y el publicador reintenta con espera creciente. (Los reintentos de los consumidores, en cambio, son inmediatos; ver 5.3.)

Si el proceso se cae después de publicar y antes de marcar, el evento se publica **otra vez**. La entrega es "al menos una vez" y los consumidores deben ser idempotentes.

Identity no publica eventos en la Fase 1, por lo que todavía no tiene `outbox`.

### 6.2 Inbox (servicios que consumen)

Cada consumidor tiene una tabla `processed_events`, en su propia base:

| Columna | Descripción |
|---|---|
| `eventId` | `id` del evento procesado. |
| `handler` | Manejador que lo procesó (un servicio puede tener varios para el mismo evento). |
| `processedAt` | Cuándo se procesó. |

La pareja (`eventId`, `handler`) es única. El consumidor inserta la fila **en la misma transacción** que el efecto del evento. Si el evento llega repetido, la inserción falla y se descarta sin repetir el efecto.

### 6.3 Retención

Las filas de `outbox` ya publicadas y las de `processed_events` se borran pasados **7 días**, con una tarea periódica. Un duplicado que llegue después de ese plazo no se reconocería; solo ocurriría al reprocesar a mano un mensaje de la cola de fallidos muy antiguo.

## 7. Configuración y secretos

### 7.1 Estructura de `platform`

```text
platform/
├── docker-compose.yml        # servicios y perfiles
├── compose.dev.yml           # construye las imágenes desde carpetas locales
├── compose.debug.yml         # expone PostgreSQL en localhost
├── Makefile
├── envs/                     # versionado, sin secretos
│   ├── base.env
│   ├── inventory.env
│   ├── tickets.env
│   ├── store.env
│   └── full.env
├── .env.example
├── db/init/                  # crea bases y usuarios
├── broker/                   # definición de los exchanges
├── secrets/                  # IGNORADO por Git; lo genera make setup
└── docs/                     # esta documentación
```

### 7.2 Reglas

- Cada servicio recibe su configuración por **variables de entorno**. Las no secretas (puertos, modos, banderas) viven en `envs/<modo>.env`, versionadas.
- Los **secretos se generan en el primer arranque** con `make setup`, que se ejecuta automáticamente y solo crea lo que falta (es idempotente): contraseñas de las bases de datos y del broker, el par de claves de firma de Identity y, cuando no hay datos de demostración, la contraseña del primer `admin`.
- La **clave privada de Identity** nunca se versiona. Se monta como archivo de solo lectura en el contenedor; la clave pública se publica por el JWKS.
- La carpeta `secrets/` está en `.gitignore`.

### 7.3 Credenciales de demostración

Los usuarios de demostración, incluida la cuenta `admin` inicial de los modos de demo, tienen contraseñas **públicas por diseño**, documentadas en el README. Cumplen las reglas de contraseña de la API (12 caracteres como mínimo y no son contraseñas comunes). **No deben usarse nunca fuera de la demo local.** La contraseña pública se define en `DEMO_PASSWORD`, versionada en `envs/`.

Con `SEED_DEMO_DATA=false` no existe ninguna contraseña conocida: `make setup` genera una contraseña aleatoria para el primer `admin`, la guarda en `secrets/` y la muestra una sola vez en la terminal.

## 8. Datos iniciales y de demostración

| Tipo | Contenido | Cuándo se carga |
|---|---|---|
| **Esenciales** | El catálogo de roles y la primera cuenta `admin` (`INITIAL_ADMIN_EMAIL` e `INITIAL_ADMIN_PASSWORD`). Con datos de demostración, la contraseña es la pública (`DEMO_PASSWORD`); sin ellos, la generada por `make setup` | Siempre |
| **Demostración** | Usuarios de ejemplo de cada rol y, en Inventory, productos y movimientos | Solo con `SEED_DEMO_DATA=true` |

- Los datos se cargan al arrancar y son **idempotentes**: reiniciar el servicio no duplica nada.
- Cada servicio carga sus propios datos. Ninguno depende de los datos de demostración de otro.

## 9. CI

**GitHub Actions** en cada repositorio, en cada *push* y *pull request*. La rama principal exige que el CI pase.

| Repositorio | Qué ejecuta |
|---|---|
| **Servicios y sistemas** | Lint, compilación, tests unitarios y de integración (con contenedores de prueba). En la rama principal, construye la imagen de Docker y la publica en **GitHub Container Registry**, etiquetada con `latest` y con el *hash* del commit |
| **Contratos de eventos** | Valida que cada esquema sea un esquema válido y que cada ejemplo cumpla el suyo |
| **platform** | Valida los archivos de Compose y ejecuta la **prueba de humo de la Fase 1** (ver abajo). También comprueba que no se haya versionado ningún secreto |

### Prueba de humo de la Fase 1

Es el criterio de "listo cuando" del plan, automatizado:

1. Levanta el modo base.
2. Espera a que PostgreSQL, RabbitMQ e Identity estén sanos.
3. Inicia sesión con el empleado demo de Inventory (`inventory.manager@example.com`, cliente `inventory`).
4. Descarga el JWKS.
5. Verifica la firma del access token usando **solo** el JWKS, y comprueba su emisor, su vigencia y sus roles.

### Cómo llegan los servicios al `docker-compose`

`docker-compose.yml` descarga las **imágenes publicadas** en GitHub Container Registry, así que quien clone solo `platform` lo ve funcionando. Para desarrollo, `compose.dev.yml` construye las imágenes desde carpetas hermanas.

## 10. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Los servicios sin perfil arrancan siempre y los de un perfil solo con ese perfil. | Con `make base` solo corren PostgreSQL, RabbitMQ e Identity; desde la Fase 2, `make inventory` no levanta Tickets ni Store. |
| 2 | Cada modo se arranca con un solo comando. | `make <modo>` levanta el modo sin pasos previos manuales. |
| 3 | El modo `full` activa la sesión compartida y la integración; los demás, no. | `envs/full.env` define `SESSION_MODE=shared` e `INTEGRATION_MODE=integrated`; los otros definen los valores contrarios. |
| 4 | Ningún secreto real está en Git. | `secrets/` está en `.gitignore` y el CI falla si detecta claves o contraseñas versionadas. |
| 5 | `make setup` es idempotente: no regenera secretos existentes. | Ejecutarlo dos veces deja los mismos secretos. |
| 6 | Cada servicio tiene su propia base y su propio usuario. | El usuario de `inventory` no puede conectarse a la base `identity`. |
| 7 | PostgreSQL no se publica hacia el equipo anfitrión por defecto. | Sin `compose.debug.yml`, el puerto no responde desde el equipo. |
| 8 | Los servicios esperan a que sus dependencias estén sanas. | Identity no arranca hasta que PostgreSQL pasa su control de salud. |
| 9 | Los datos iniciales son idempotentes. | Reiniciar un servicio no duplica roles ni usuarios. |
| 10 | Los datos esenciales se cargan siempre; los de demostración, solo con `SEED_DEMO_DATA=true`. | Con la bandera en `false`, existen los roles y el `admin`, pero no los usuarios de ejemplo. |
| 11 | El exchange `events` existe aunque no haya consumidores. | Tras arrancar solo el broker, el exchange está declarado. |
| 12 | Cada consumidor declara su propia cola, duradera y con su cola de fallidos. | Tras arrancar un consumidor, existen `<consumidor>.events` y `<consumidor>.events.dlq`. |
| 13 | Un mensaje que falla N veces llega a la cola de fallidos. | Un consumidor que rechaza siempre un mensaje lo deja en `<consumidor>.events.dlq` tras N intentos. |
| 14 | El evento se guarda en el `outbox` en la misma transacción que el cambio. | Si el cambio se revierte, no queda ninguna fila en `outbox`. |
| 15 | Un evento solo se marca como publicado tras la confirmación del broker. | Con el broker detenido, las filas siguen con `publishedAt` vacío. |
| 16 | Dos instancias del publicador no toman las mismas filas a la vez. | Con dos publicadores concurrentes no se publica una fila al mismo tiempo desde ambos. |
| 17 | Un evento repetido se procesa una sola vez. | Entregar el mismo `id` dos veces produce un solo efecto y una sola fila en `processed_events`. |
| 18 | Las filas antiguas se purgan a los 7 días. | Tras la limpieza, no quedan filas publicadas ni procesadas con más de 7 días. |
| 19 | La prueba de humo de la Fase 1 pasa en cada cambio de `platform`. | El CI de `platform` ejecuta el inicio de sesión y la verificación del JWKS. |
| 20 | Las imágenes de los servicios se publican desde la rama principal. | Tras un cambio en `main`, la imagen con el *hash* del commit existe en GitHub Container Registry. |
| 21 | Con solo `platform` clonado, `make base` funciona. | Clonar únicamente ese repositorio y ejecutarlo levanta la plataforma. |
| 22 | Reports y Notifications se pueden activar con cualquier sistema o con la base sola. | `make inventory WITH="reports"` levanta Inventory y Reports; `make store WITH="notifications"` levanta Store y Notifications. |
| 23 | Un complemento sin eventos de un sistema ausente sigue funcionando. | Reports levantado solo con Inventory arranca sano y no falla por no recibir eventos de Store. |
| 24 | Sin datos de demostración no existe ninguna contraseña conocida. | Con `SEED_DEMO_DATA=false`, la contraseña del `admin` no coincide con `DEMO_PASSWORD` y está en `secrets/`. |

Cuándo se prueban: las invariantes 1 a 11, 19 a 21 y 24 en la Fase 1 (con `make base`; las que mencionan otros sistemas se amplían cuando existan). Las invariantes 12 a 18 se prueban con el primer publicador o consumidor (Fase 2), y las 22 y 23 cuando existan Reports y Notifications (Fases 4 y 6).

## 11. Preguntas que se resuelven en la implementación

- **Versiones de PostgreSQL y RabbitMQ**, fijadas a una versión mayor concreta.
- **Puertos publicados** de cada servicio.
- **Límite o caducidad de las colas** de consumidores que dejan de ejecutarse, para evitar que acumulen mensajes sin fin. Se define al implementar el primer consumidor.
- **Valor de N** (intentos antes de la cola de fallidos). Referencia: 5.
- **Nombres de repositorios y perfiles:** resuelto, van en inglés (`platform`, `identity`, `reports`, `inventory`, `store`, `tickets`, perfil `full`).

## 12. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Reports y Notifications como perfiles complementarios combinables | Disponibles solo en el modo `full` | Permite probar o mostrar un complemento con cualquier sistema; el costo es una variable `WITH` en el `Makefile`. |
| Perfiles de Compose y `Makefile` con archivos de entorno por modo | Archivos de Compose por modo / variables a mano | Un solo comando fácil de recordar y sin duplicar configuración; las variables a mano son frágiles. |
| Una instancia de PostgreSQL con una base y un usuario por servicio | Un contenedor por servicio / un esquema por servicio | Más ligero para la demo; el aislamiento lógico se mantiene con usuarios separados. Se acepta compartir el dominio de fallo. Los esquemas se descartan por aislamiento débil. |
| PostgreSQL para todos los servicios | SQL Server en Inventory | Más ligero y gratuito, funciona en cualquier equipo y comparte motor con Identity. SQL Server queda como segunda iteración. |
| Exchange compartido creado por la plataforma | Un exchange por publicador | Un enlace falla si el exchange no existe, y un publicador ausente rompería la integración opcional. |
| Colas y *bindings* declarados por cada consumidor | Definidos en la plataforma | Cada servicio se prueba solo; no depende de un archivo central. |
| Una cola por consumidor | Una cola por tipo de evento y consumidor | Más simple. |
| N intentos inmediatos de los consumidores y luego cola de fallidos | Reintentos de los consumidores con espera creciente | Suficiente para el MVP; menos colas y configuración. |
| Outbox por servicio publicador | Publicar directamente tras guardar | Evita perder eventos y publicar eventos de cambios revertidos. |
| Publicación por consulta periódica con `SKIP LOCKED` | `LISTEN/NOTIFY` / captura de cambios | Funciona igual en los tres lenguajes, y la ganancia en latencia no importa para estos eventos. |
| Tabla `processed_events` para idempotencia | Operaciones naturalmente idempotentes | Descontar stock no es idempotente por sí mismo. |
| Retención de 7 días | Retención indefinida | Evita el crecimiento sin límite; los duplicados llegan en minutos. |
| Secretos generados en el primer arranque | Valores fijos en el repositorio / gestor de secretos | Nada secreto en Git y sin la complejidad de un gestor. |
| Datos esenciales y de demostración separados | Un único conjunto de datos iniciales | El servicio necesita los esenciales siempre; los de demo son opcionales. |
| GitHub Actions con imágenes publicadas | Construir desde carpetas hermanas / submódulos de Git | Quien clone solo `platform` lo ve funcionando. |
| Migraciones al arrancar el servicio | Tarea de migración aparte | Más simple para demo; no es una práctica para producción. |

## 13. Fuera de alcance (por ahora)

- Usuarios y permisos distintos por servicio en RabbitMQ.
- Cifrado TLS entre servicios.
- Gestor de secretos y herramientas para rotar la clave de firma de Identity.
- Copias de seguridad de las bases de datos.
- Alta disponibilidad (PostgreSQL y RabbitMQ en varios nodos).
- Reintentos de los consumidores con espera creciente y reenvío automático de los mensajes fallidos.
- `LISTEN/NOTIFY` y captura de cambios para el outbox.
- Migraciones como tarea independiente.
- Observabilidad: métricas, trazas distribuidas y agregación de registros.
- Despliegue en la nube u orquestadores como Kubernetes.
- Firma de las imágenes y listas de materiales de software.
