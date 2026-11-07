"""Tests del pipeline y del código Python (pytest). Se corren con `python -m pytest -q`.

División del trabajo:
  * dbt prueba los DATOS (claves, nulos, relaciones, reglas físicas, regla del 75%...) en cada
    `dbt build`: ver dbt/models/**/_*.yml y dbt/tests/.
  * pytest prueba lo que dbt no puede: el pipeline completo (idempotencia), las consultas de
    análisis que viven fuera de dbt (sql/99) y el código Python del extractor.
"""

import hashlib
import subprocess
import sys

import duckdb
import pytest

from src import config
from src.extract import COLUMNAS_ESPERADAS, columnas_faltantes


def correr_etl() -> None:
    subprocess.run([sys.executable, "-m", "src.etl"], cwd=config.RAIZ, check=True, capture_output=True)


@pytest.fixture(scope="session", autouse=True)
def base_construida():
    if not config.BASE_DUCKDB.exists():
        correr_etl()


# --- Pipeline -----------------------------------------------------------------------------------

def huella_final() -> dict:
    """Hash de cada archivo de data/final: si dos corridas dan lo mismo, el ETL es idempotente."""
    return {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in sorted(config.DIR_FINAL.glob("*.csv"))}


def test_etl_es_idempotente():
    correr_etl()
    primera = huella_final()
    correr_etl()
    segunda = huella_final()
    assert len(primera) == len(config.TABLAS_FINALES)
    assert primera == segunda


def test_consultas_de_analisis_son_de_solo_lectura():
    # sql/99 se tiene que poder correr sobre la base sin modificarla (conexión de solo lectura)
    texto = (config.DIR_SQL / "99_consultas_analisis.sql").read_text(encoding="utf-8")
    c = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)
    sentencias = duckdb.extract_statements(texto)
    resultados = [c.execute(s.query).fetchall() for s in sentencias]
    c.close()
    assert len(sentencias) > 20
    assert len(resultados[-2]) == 9   # D1: 3 estaciones × 3 contaminantes


# --- Extractor (funciones puras, no necesitan red) ---------------------------------------------

def test_extractor_acepta_el_formato_de_ba_data():
    # Encabezado real del CSV (con BOM de UTF-8 y las columnas de Palermo, que se ignoran)
    encabezado = "\ufeff" + ",".join(COLUMNAS_ESPERADAS + ["CO_PALERMO", "NO2_PALERMO", "PM10_PALERMO"])
    contenido = (encabezado + "\n12FEB2011:00:00:00,19,s/d,s/d,s/d,0.20,22,28,0.08,21,s/d,,,\n").encode("utf-8")
    assert columnas_faltantes(contenido) == []


def test_extractor_detecta_un_cambio_de_formato():
    contenido = b"fecha,hora,no2_centenario\n2025-01-01,1,15\n"
    faltan = columnas_faltantes(contenido)
    assert "NO2_CORDOBA" in faltan and "PM10_LA_BOCA" in faltan
    assert "NO2_CENTENARIO" not in faltan   # mayúsculas o minúsculas da igual
