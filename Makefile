# Atajos para correr el TP. En Windows (sin make) usar los comandos de cada regla
# reemplazando .venv/bin/python por .venv\Scripts\python.

PY ?= .venv/bin/python

.PHONY: all install extract etl test eda docs clean

## make all: ETL completo + tests + notebook de EDA (todo desde los datos crudos)
all: etl test eda

## make install: crea el entorno virtual e instala las dependencias
install:
	python3 -m venv .venv
	$(PY) -m pip install --upgrade pip
	$(PY) -m pip install -r requirements.txt

## make extract: vuelve a bajar los PDF de la APrA y regenera data/raw/aire_publico.csv
## (opcional: el CSV crudo ya está en el repo)
extract:
	$(PY) -m src.extract

## make etl: raw -> DuckDB (dbt: staging, modelo, calidad, indicadores + tests) -> data/final
etl:
	$(PY) -m src.etl

## make test: tests de pytest sobre la base generada
test:
	$(PY) -m pytest -q

## make eda: ejecuta el notebook de EDA y regenera las figuras de reports/figures
eda:
	$(PY) -m jupyter nbconvert --to notebook --execute --inplace notebooks/eda.ipynb

## make docs: documentación navegable de dbt (linaje de tablas) en http://localhost:8080
docs:
	cd dbt && ../$(PY) -c "from dbt.cli.main import cli; cli()" docs generate --profiles-dir . && ../$(PY) -c "from dbt.cli.main import cli; cli()" docs serve --profiles-dir .

## make clean: borra la base y los artefactos de dbt (no toca data/raw ni data/final)
clean:
	rm -rf data/warehouse dbt/target dbt/logs
