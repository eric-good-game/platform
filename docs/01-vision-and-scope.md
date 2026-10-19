# Visión y alcance de la Fase 1

Documento 1 de la Fase 1. Explica qué se construye, por qué, con qué principios y hasta dónde llega la Fase 1. Es el punto de entrada de la documentación: enlaza al resto y reúne en un solo lugar lo que queda para más adelante.

Vive en `platform/docs`.

Estado: **borrador para revisión**.

## 1. Visión

Construir un portafolio de backend empresarial y *fullstack* formado por **tres sistemas independientes** (inventario, tickets y tienda) apoyados en **servicios compartidos** (identidad, reportes, notificaciones).

No es un sistema gigante. Es una plataforma común más productos autónomos que:

- se pueden **probar cada uno por separado**;
- se **comunican de forma fluida** cuando se ejecutan juntos.

El objetivo es demostrar criterio de diseño: límites claros, contratos explícitos, integración opcional y documentación que explica las decisiones y no solo el resultado.

## 2. Principios

1. **Cada sistema es dueño de sus datos.** Tiene su propia base de datos y nadie lee la de otro.
2. **La integración es opcional.** Los sistemas se comunican por eventos asíncronos; si el otro sistema no está, el evento no tiene suscriptor y nada se rompe.
3. **Cada sistema depende solo de la plataforma** (Identity, broker), nunca de otro sistema principal.
4. **Los contratos de eventos son lo único compartido** entre sistemas; ninguno depende del código de otro.
5. **Primero se documenta, luego se implementa.** Cada documento se construye con sus invariantes verificables, que más tarde se convierten en pruebas.
6. **El diseño de cada servicio es proporcional a su complejidad** (ver sección 7).

## 3. Mapa de sistemas

| Pieza | Tecnología | Rol | Fase |
|---|---|---|:-:|
| Identity | NestJS | Usuarios, roles, empleados, emisión de JWT | 1 |
| Broker | RabbitMQ | Bus de eventos | 1 |
| Inventory | C# + .NET | Catálogo, stock, movimientos, reservas | 2 |
| Store | Por decidir | Catálogo público, pedidos, pagos | 3 |
| Reports | Python (FastAPI) | Reportes, exportaciones, predicciones | 4 |
| Tickets | Java + Spring | Tickets, garantías, devoluciones | 5 |
| Notifications y n8n | NestJS o n8n | Correo, alertas, automatizaciones | 6 |
| Frontends | Angular (Inventory, Tickets) y Next.js (Store) | Paneles internos y cara pública | 2, 3, 5 |

El detalle de la arquitectura completa está en `portfolio-architecture.md`.

## 4. Fases

| Fase | Entrega | Presentable por sí sola |
|:-:|---|---|
| 1 | Plataforma base: Identity, contratos de eventos e infraestructura | Inicio de sesión y validación de un token con solo el JWKS |
| 2 | Inventory (.NET + Angular) | Sistema de stock con reservas y alertas |
| 3 | Store (Next.js), sola y luego integrada con Inventory | Tienda con pedidos y pagos en sandbox |
| 4 | Reports (Python) | Reportes y exportaciones |
| 5 | Tickets (Spring + Angular), integrado con Store | Soporte, garantías y devoluciones |
| 6 | Notifications y n8n | Alertas y automatizaciones |

## 5. Alcance de la Fase 1

### Entra

| Entregable | Documento |
|---|---|
| Servicio **Identity**: usuarios, roles, empleados, tokens y JWKS | 2 a 5 y 8 |
| **Contratos de eventos** del sistema de inventario | 6 |
| **Infraestructura**: Docker Compose, PostgreSQL, RabbitMQ, secretos, datos de demostración y CI | 7 |

Esta fase **no tiene frontend**: se prueba con Swagger, Postman y la prueba de humo automatizada.

### No entra

- Cualquier sistema de negocio (Inventory, Store, Tickets) y sus frontends.
- Reports, Notifications y n8n (el diseño de infraestructura los contempla, pero no se construyen).
- Eventos de Identity: no publica ninguno en esta fase.
- Los contratos de los eventos de Store y Tickets: se definen en sus fases.

### Criterio de terminado

La fase termina cuando se cumple, de forma automatizada, lo siguiente:

1. `make base` levanta PostgreSQL, RabbitMQ e Identity en un equipo con solo `platform` clonado.
2. Un usuario de demostración inicia sesión y obtiene un JWT.
3. Un cliente externo **verifica el token usando solo el JWKS**, comprobando firma, emisor, vigencia y roles.
4. Los esquemas de los eventos de inventario están publicados y sus ejemplos cumplen su esquema.
5. Cada invariante de los documentos 2 a 8 tiene al menos una prueba rastreable, salvo las que dependen de componentes que aún no existen (otros sistemas, publicadores o consumidores de eventos). Esas se señalan en el documento que las contiene y se prueban en la fase de ese componente.

Los puntos 2 y 3 son la prueba de humo del documento 7.

## 6. Mapa de la documentación

| # | Documento | Tema |
|:-:|---|---|
| 1 | `01-vision-and-scope.md` | Este documento |
| 2 | `02-identity-roles-and-permissions.md` | Catálogo de roles, invariantes y permisos por sistema |
| 3 | `03-identity-data-model.md` | Entidades, relaciones y borrado lógico |
| 4 | `04-identity-authentication-flow.md` | Tokens, sesiones, cookies y JWKS |
| 5 | `05-identity-api.md` | Convenciones, errores y endpoints |
| 6 | `06-event-contracts.md` | Sobre, versionado y catálogo de eventos |
| 7 | `07-platform-infrastructure.md` | Modos de ejecución, bases de datos, broker, outbox, secretos y CI |
| 8 | `08-identity-project-structure.md` | Estructura del código de Identity (NestJS) |
| 9 | `09-phase-1-implementation-plan.md` | Hitos de implementación y trazabilidad de invariantes |

Los documentos 2 a 6 describen el diseño sin depender de la tecnología de implementación (el 1 incluye el mapa de tecnologías como contexto); el 7 y el 8 mencionan tecnologías concretas porque lo requieren.

### Dónde vive cada documento

| Tipo | Ubicación |
|---|---|
| Transversales (visión, eventos, infraestructura) | `platform/docs` |
| De un servicio (roles, modelo, flujo, API, estructura) | `<servicio>/docs` |

### Plantilla de cada documento

Todos siguen la misma estructura: propósito y estado, contenido, **reglas e invariantes** (con criterio verificable), **decisiones y alternativas descartadas** y **fuera de alcance**.

## 7. Convenciones

- **Idioma:** código, commits y términos técnicos en inglés; la documentación se redacta en español. Los nombres de archivos, repositorios y perfiles van en inglés.
- **Nombres:** el servicio de identidad se llama **Identity** en todos los documentos.
- **Datos:** identificadores UUID v7, fechas ISO 8601 en UTC, campos en `camelCase`.
- **Repositorios:** uno por servicio (`identity`, `reports`) y uno por sistema (`inventory`, `tickets`, `store`), más `platform` para la infraestructura y la documentación transversal y `event-contracts` para los esquemas de eventos.
- **Versionado y publicación:** versionado semántico; las versiones se generan a partir de los commits (*Conventional Commits*) y cada imagen se etiqueta con su versión.

### Criterio de DDD por servicio

Cada servicio evalúa **qué patrones tácticos de DDD aplica según la cantidad de invariantes que protege**. El DDD estratégico (límites entre servicios, lenguaje común, eventos como contrato) se aplica siempre.

| Servicio | Nivel esperado | Motivo |
|---|---|---|
| Identity | Ligero | Pocas zonas con reglas: usuario y roles, sesión, objetos de valor (documento 8) |
| Inventory | Alto | Movimientos como libro inmutable, stock derivado, reservas todo o nada y concurrencia |
| Store | Alto | Pedido como agregado, estados de pago y saga |
| Tickets | Medio | Ciclo de vida del ticket |
| Reports y Notifications | Ninguno | Lectura y entrega |

La tabla es el punto de partida; cada servicio la confirma en su propio documento de estructura.

## 8. Mejoras futuras

Reúne lo que cada documento dejó **fuera de alcance**. La fuente de verdad sigue siendo la sección "Fuera de alcance" de cada documento; esta lista sirve para verlo todo junto.

### Seguridad y cuentas

| Mejora | Documento |
|---|---|
| Autenticación de dos factores | 3, 4 |
| Verificación de email y de teléfono | 3, 4, 5 |
| Recuperación de contraseña por email | 4, 5 |
| Comprobar contraseñas contra listas de filtraciones externas | 5 |
| Inicio de sesión con proveedores externos (Google, etc.) | 4 |
| Revocación inmediata de access tokens | 4 |
| Evento `user.disabled` para avisar a los sistemas | 4, 6, 8 |
| Restringir tokens por sistema con el claim `aud` | 4 |
| Ventana de gracia para renovaciones simultáneas | 4 |
| Refresh token en el cuerpo para clientes que no son navegadores | 5 |
| Proxy inverso por frontend (sin el campo `client`) | 5 |

### Gestión de usuarios y roles

| Mejora | Documento |
|---|---|
| Crear y editar roles desde la API | 2 |
| Permisos a nivel de registro | 2 |
| Jerarquías entre roles | 2 |
| Lista de sesiones activas del usuario | 4, 5 |
| Auditoría de acciones administrativas e historial de cambios de roles | 3, 5 |
| Reactivar usuarios y reglas de reutilización de email | 3, 5 |
| Cambio de tipo de cuenta (`employee` ↔ `customer`) | 5 |
| Varios emails por usuario y teléfono del personal | 3 |
| Filtros avanzados y ordenamiento en `GET /v1/users` | 5 |

### Eventos e integración

| Mejora | Documento |
|---|---|
| Eventos "delgados" con consulta al publicador (requiere cuentas de servicio) | 6 |
| Documento AsyncAPI y catálogo navegable | 6 |
| Registro centralizado de esquemas | 6 |
| Firma o cifrado de eventos | 6 |
| Garantía de orden entre eventos | 6 |
| Varios almacenes y transferencias (cambio compatible en los eventos) | 6 |
| Eventos de Store y Tickets | 6 (en sus fases) |

### Infraestructura y operación

| Mejora | Documento |
|---|---|
| Reintentos con espera creciente y reenvío automático de mensajes fallidos | 7 |
| `LISTEN/NOTIFY` o captura de cambios para el outbox | 7 |
| Usuarios y permisos por servicio en RabbitMQ y TLS entre servicios | 7 |
| Gestor de secretos y rotación automática de claves de firma | 7, 8 |
| Copias de seguridad y alta disponibilidad | 7 |
| Migraciones como tarea independiente | 7 |
| Observabilidad: métricas, trazas distribuidas y registros agregados | 7, 8 |
| Despliegue en la nube o Kubernetes | 7 |
| Firma de imágenes y listas de materiales de software | 7 |
| Pruebas de contrato entre consumidor y publicador (Pact) | 7 |

### Arquitectura del código

| Mejora | Documento |
|---|---|
| CQRS, event sourcing y eventos de dominio internos | 8 |
| Arquitectura hexagonal completa con capa de aplicación | 8 |
| Monorepo con paquetes compartidos entre servicios NestJS | 8 |
| Pruebas de carga y de mutación | 8 |

## 9. Preguntas abiertas

| Pregunta | Se resuelve en |
|---|---|
| Framework del backend de Store (otro proyecto NestJS, FastAPI o Django) | Fase 3 |
| Pasarela de pagos (Stripe o Mercado Pago) | Fase 3 |
| Si Notifications es un servicio propio o un flujo de n8n | Fase 6 |
| Si el stock reservado cuenta como disponible en `stock.low` y en `availableQuantity` | Fase 2 |
| Valores de referencia de infraestructura (versiones, puertos, número de intentos antes de la cola de fallidos, límite de colas huérfanas) | Implementación de la Fase 1 |

## 10. Reglas e invariantes

| # | Invariante | Criterio verificable |
|---|---|---|
| 1 | Ningún servicio lee la base de otro. | Cada servicio tiene su usuario de base de datos y no puede conectarse a otra base (documento 7). |
| 2 | Ningún sistema depende del código de otro. | Los únicos artefactos compartidos son los contratos de eventos y los tokens. |
| 3 | Un sistema arranca y funciona sin los demás sistemas. | `make inventory` levanta Inventory con solo la plataforma base (se verifica desde la Fase 2). |
| 4 | Todo documento sigue la plantilla fija. | Cada documento tiene las secciones de reglas e invariantes, decisiones y fuera de alcance. |
| 5 | Toda invariante tiene un criterio verificable. | Ninguna fila de invariantes carece de criterio. |
| 6 | Cada mejora futura está registrada en el documento al que pertenece. | Todo elemento de la sección 8 aparece en la sección "Fuera de alcance" del documento indicado. |
| 7 | La documentación usa los mismos nombres en todos los documentos. | El servicio de identidad es siempre "Identity" y los archivos y perfiles están en inglés. |

## 11. Decisiones y alternativas descartadas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Documentar antes de implementar | Implementar y documentar sobre la marcha | Permite entender los marcos desconocidos paso a paso y detectar huecos antes de escribir código. |
| Tres sistemas independientes con integración opcional | Un único sistema grande | Cada sistema se prueba y se presenta por separado. |
| Una Fase 1 sin frontend | Incluir un panel de Identity | Reduce el alcance; Swagger y la prueba de humo bastan. |
| Contratos de eventos solo de Inventory en la Fase 1 | Definir los de todos los sistemas | Los de Store y Tickets dependen de decisiones aún abiertas. |
| Documentos agnósticos y tecnológicos separados | Todo en cada documento | Los conceptos se leen sin depender del framework. |
| Nivel de DDD proporcional a cada servicio | DDD completo en todos o en ninguno | Aplica los patrones donde hay reglas que proteger y evita ceremonia donde no. |
| Lista consolidada de mejoras en este documento | Solo en cada documento | Da una vista conjunta sin perder la fuente de verdad local. |

## 12. Fuera de alcance (por ahora)

- Documentación navegable publicada (un sitio generado desde estos archivos).
- Un documento de visión por cada sistema; se redactan al iniciar cada fase.
- Plan de pruebas de rendimiento y de seguridad de la plataforma completa.
