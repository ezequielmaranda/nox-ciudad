"""Tests del pipeline y del código Python (pytest). Se corren con `make test` o `python -m pytest -q`.

División del trabajo:
  * dbt prueba los DATOS (claves, nulos, relaciones, reglas físicas, regla del 75%...) en cada
    `dbt build`: ver dbt/models/**/_*.yml y dbt/tests/.
  * pytest prueba lo que dbt no puede: el pipeline completo (idempotencia), las consultas de
    análisis que viven fuera de dbt (sql/99) y el código Python del extractor de PDF.
"""

import hashlib
import shutil
import subprocess
import sys

import duckdb
import pytest

from src import config
from src.extract import estacion_de_texto, mes_anio_de_texto, tipo_de_archivo


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


def test_consultas_de_analisis_corren(tmp_path):
    # Se corren sobre una copia de la base, porque el archivo crea vistas
    copia = tmp_path / "aire.duckdb"
    shutil.copy(config.BASE_DUCKDB, copia)
    c = duckdb.connect(copia.as_posix())
    texto = (config.DIR_SQL / "99_consultas_analisis.sql").read_text(encoding="utf-8")
    sentencias = duckdb.extract_statements(texto)
    for s in sentencias:
        c.execute(s.query)
    assert len(sentencias) > 20
    assert c.execute("select count(*) from analisis.v_resumen_estacion").fetchone()[0] == 9
    c.close()


# --- Extractor (funciones puras, no necesitan red) ---------------------------------------------

@pytest.mark.parametrize("nombre, esperado", [
    ("pm10_la%20boca_mayo_2025.pdf", "LA BOCA"),
    ("nox_laboca_enero_2024.pdf", "LA BOCA"),
    ("co_centenaeio_marzo_2025.pdf", "CENTENARIO"),   # nombre mal escrito en la fuente
    ("nox_córdoba_julio_2024.pdf", "CORDOBA"),
    ("informe.pdf", None),
])
def test_extractor_reconoce_estacion(nombre, esperado):
    assert estacion_de_texto(nombre) == esperado


def test_extractor_reconoce_mes_y_tipo():
    assert mes_anio_de_texto("nox_cordoba_septiembre_2024.pdf") == (9, 2024)
    assert mes_anio_de_texto("PM10 - Febrero 2026") == (2, 2026)
    assert tipo_de_archivo("pm10_cordoba_enero_2025.pdf") == "pm10"
    assert tipo_de_archivo("nox_cordoba_enero_2025.pdf") == "nox"
    assert tipo_de_archivo("co_cordoba_enero_2025.pdf") == "co"
    assert tipo_de_archivo("calendario.pdf") is None
