COMPOSE := docker compose
PSQL := $(COMPOSE) exec -T db psql -X -U sqlazy -d sqlazy_poc -v ON_ERROR_STOP=1

.PHONY: up init verify down

up:
	$(COMPOSE) up -d --wait

init:
	$(PSQL) -f /work/schema/01_schema.sql
	$(PSQL) -f /work/schema/02_seed.sql
	$(PSQL) -f /work/native/reference_postgresql.sql
	$(PSQL) -f /work/sqlazy/generated_postgresql.sql

verify: init
	$(PSQL) -f /work/tests/verification.sql
	$(PSQL) -f /work/tests/edge_cases.sql

down:
	$(COMPOSE) down

