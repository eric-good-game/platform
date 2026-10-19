# platform

Infraestructura y documentación transversal del portafolio. Este repositorio reúne lo que comparten todos los servicios: los modos de ejecución, PostgreSQL y RabbitMQ, los secretos, la prueba de humo de la Fase 1 y los documentos de diseño.

Estado: **hito 1 completado**. El siguiente es el hito 2 (esqueleto de Identity), en el repositorio `identity`.

## Qué habrá aquí

| Ruta | Contenido | Hito |
|---|---|---|
| `docs/` | Documentos 1 a 9 de la Fase 1 y visión general de la arquitectura | 0 |
| `docker-compose.yml` | Servicios, perfiles y controles de salud | 1 |
| `Makefile` | `make base`, `down`, `reset`, `logs` y `setup` | 1 |
| `envs/` | Variables por modo (`base`, `inventory`, `tickets`, `store`, `full`) | 1 |
| `db/init/` | Creación de bases y usuarios de PostgreSQL | 1 |
| `broker/` | Definición del exchange `events` y de `events.dlx` | 1 |
| `secrets/` | Secretos generados por `make setup`. **Ignorado por Git** | 1 |

## Cómo se usa

```bash
make setup   # genera los secretos en secrets/ (idempotente)
make base    # levanta PostgreSQL y RabbitMQ y espera a que estén sanos
make check   # comprueba salud, exchanges y aislamiento de las bases
make debug   # como base, con PostgreSQL expuesto en localhost:5432
make down    # detiene los contenedores
make reset   # detiene y borra los datos
make logs    # sigue los registros
```

La consola web de RabbitMQ queda en `http://localhost:15672` (usuario `portfolio`; la contraseña está en `secrets/rabbitmq_password`). Los datos de demostración usan la contraseña pública `Demo.Password.2026`.

## Para qué sirve

- Levantar la plataforma base con un solo comando, clonando solo este repositorio.
- Ejecutar la prueba de humo de la Fase 1: iniciar sesión con un usuario de demostración y validar el token usando solo el JWKS.
- Mantener la documentación que afecta a más de un servicio.

## Documentación

- [Índice de los documentos](docs/README.md)
- [Visión y alcance](docs/01-vision-and-scope.md)
- [Infraestructura](docs/07-platform-infrastructure.md)
- [Plan de hitos de la Fase 1](docs/09-phase-1-implementation-plan.md)

## Requisitos locales

Verificados en los hitos 0 y 1:

| Herramienta | Versión mínima | Comprobado con |
|---|---|---|
| Docker (con daemon en marcha) | 24 | 29.8 |
| Node.js | 22 | 26.8 |
| pnpm | 9 | 11.25 |
| GNU Make | 3.81 | 3.81 |
| Git | 2.40 | 2.54 |

## Convenciones

- Commits en inglés con *Conventional Commits*: `feat:`, `fix:`, `docs:`, `chore:`.
- Ramas cortas: `feature/<hito>-<tema>`, `fix/<tema>`, `docs/<tema>`, `chore/<tema>`.
- La rama `main` está protegida: no admite *push* directo y exige el CI en verde.
- Si un cambio de comportamiento deja un documento desfasado, se corrige en el mismo pull request.

Detalle: [CONTRIBUTING.md](CONTRIBUTING.md).

## Repositorios relacionados

| Repositorio | Contenido |
|---|---|
| `identity` | Servicio Identity (NestJS) |
| `event-contracts` | Esquemas JSON Schema de los eventos |

## Licencia

MIT. Ver [LICENSE](LICENSE).
