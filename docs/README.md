# Documentación de la Fase 1

Índice de los documentos de diseño. Todos están en estado **borrador para revisión**; el plan de hitos los convierte en código y los aprueba al cerrar la fase.

## Documentos oficiales (1 a 9)

| # | Documento | Tema | Repositorio destino |
|:-:|---|---|---|
| 1 | [01-vision-and-scope.md](01-vision-and-scope.md) | Visión, alcance, convenciones y mejoras futuras | `platform` |
| 2 | [02-identity-roles-and-permissions.md](02-identity-roles-and-permissions.md) | Catálogo de roles, invariantes y permisos por sistema | `identity` |
| 3 | [03-identity-data-model.md](03-identity-data-model.md) | Entidades, relaciones y borrado lógico | `identity` |
| 4 | [04-identity-authentication-flow.md](04-identity-authentication-flow.md) | Tokens, sesiones, cookies y JWKS | `identity` |
| 5 | [05-identity-api.md](05-identity-api.md) | Convenciones, errores y endpoints | `identity` |
| 6 | [06-event-contracts.md](06-event-contracts.md) | Sobre, versionado y catálogo de eventos | `event-contracts` |
| 7 | [07-platform-infrastructure.md](07-platform-infrastructure.md) | Modos de ejecución, bases de datos, broker, secretos y CI | `platform` |
| 8 | [08-identity-project-structure.md](08-identity-project-structure.md) | Estructura del código de Identity (NestJS) | `identity` |
| 9 | [09-phase-1-implementation-plan.md](09-phase-1-implementation-plan.md) | Hitos de implementación y trazabilidad de invariantes | `platform` |

## Visión general

| Documento | Tema |
|---|---|
| [portfolio-architecture.md](portfolio-architecture.md) | Arquitectura completa del portafolio y alcance del MVP |

## Dónde vive cada documento

En el hito 0 los nueve documentos viven en `platform/docs`, como pide el plan. El documento 1 define que los documentos de un servicio viven en `<servicio>/docs`, así que se moverán a su repositorio al crear cada componente:

- Documentos 2, 3, 4, 5 y 8 → `identity/docs` (hito 2).
- Documento 6 → `event-contracts` (hito 8).
