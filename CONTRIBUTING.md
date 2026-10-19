# Cómo contribuir

Repositorio personal de portafolio, pero con las reglas de trabajo de un equipo.

## Idioma

- Código, nombres de archivo, ramas y commits en inglés.
- La documentación se redacta en español.

## Commits

Se siguen *Conventional Commits* en inglés. Tipos usados: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

- Mensaje en imperativo y en minúscula: `feat: add jwks endpoint`.
- El repositorio admite solo *squash merge*, así que el **título del pull request** es el mensaje que queda en `main`. El CI lo valida (`commitlint`).

Ejemplos válidos:

- `feat(identity): add login endpoint`
- `docs: resolve store clients open question`
- `ci: add reusable workflow`

## Ramas

- `feature/<hito>-<tema>`, por ejemplo `feature/1-plataforma-base`.
- `fix/<tema>`, `docs/<tema>`, `chore/<tema>`.
- Ramas cortas, una por cambio, integradas pronto.

## Pull requests

- Título en *Conventional Commits*; descripción con la plantilla del repositorio.
- CI en verde antes de fusionar.
- La rama `main` está protegida: no admite *push* directo, *force-push* ni borrado.
- Si el cambio altera el comportamiento, se actualiza en el mismo PR el documento afectado (regla del plan de hitos, sección 1).

## Antes de abrir el pull request

```bash
npx --yes markdownlint-cli2@0.18.0
npx --yes yaml-lint@1.7.0 '.github/**/*.{yml,yaml}' docker-compose.yml compose.debug.yml
node scripts/check-repo.mjs
```

Solo en `platform`, con Docker en marcha, además:

```bash
make setup && make validate && make base && make check && make reset
```

## Hitos

El trabajo se organiza por hitos verticales. Ver [docs/09-phase-1-implementation-plan.md](docs/09-phase-1-implementation-plan.md).
