SHELL := /bin/bash

MODE ?= base
ENV_FILE ?= envs/$(MODE).env
SECRETS_ENV := secrets/compose.env
COMPOSE := docker compose --env-file $(ENV_FILE) --env-file $(SECRETS_ENV)

.DEFAULT_GOAL := help

.PHONY: help setup base debug down reset logs validate check

help: ## Muestra esta ayuda
	@echo "Objetivos disponibles:"
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-9s %s\n", $$1, $$2}'

setup: ## Genera los secretos locales si faltan (idempotente)
	@ENV_FILE=$(ENV_FILE) bash scripts/setup.sh

base: setup ## Levanta PostgreSQL y RabbitMQ y espera a que estén sanos
	@$(COMPOSE) up -d --wait

debug: setup ## Levanta el modo base y expone PostgreSQL en localhost
	@$(COMPOSE) -f docker-compose.yml -f compose.debug.yml up -d --wait

down: setup ## Detiene y elimina los contenedores
	@$(COMPOSE) down --remove-orphans

reset: setup ## Detiene todo y borra los datos
	@$(COMPOSE) down --remove-orphans --volumes

logs: setup ## Sigue los registros de los servicios
	@$(COMPOSE) logs --follow --tail=100

validate: setup ## Valida el archivo de Compose sin mostrar secretos
	@$(COMPOSE) config --quiet && echo "docker-compose.yml válido"

check: setup ## Comprueba salud, exchanges y aislamiento de las bases
	@bash scripts/check-platform.sh
