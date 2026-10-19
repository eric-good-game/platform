# Política de seguridad

## Versiones soportadas

El proyecto está en desarrollo (serie `0.x`). No hay versiones publicadas ni soporte para uso en producción: el único entorno previsto es la demo local descrita en la documentación.

## Cómo reportar una vulnerabilidad

- Usa los avisos de seguridad privados de GitHub: pestaña **Security**, opción **Report a vulnerability**.
- No abras un issue público ni un pull request con el detalle del fallo antes de que se corrija.
- Incluye, si puedes: descripción, impacto, pasos para reproducirlo y la versión o el commit afectado.

## Alcance

- El repositorio no contiene secretos reales. Las contraseñas de bases y del broker, y el par de claves de firma, se generan en el primer arranque y viven en `secrets/`, que está ignorado por Git.
- Las contraseñas de demostración son públicas por diseño y no deben usarse fuera de la demo local.
- Si encuentras una credencial versionada, repórtala como vulnerabilidad.

## Tiempo de respuesta

Es un proyecto personal de portafolio: se atiende lo antes posible, sin plazos garantizados.
