"""Tests del ETL (pytest). Se corren con `make test` o `python -m pytest -q`.

Revisan la base que arma `python -m src.etl` (si no existe, la construyen una vez al empezar).
Complementan a los tests de dbt: aquellos validan cada tabla en cada build; estos validan
propiedades del pipeline completo (idempotencia, consultas de análisis, extractor) y vuelven a
chequear desde Python las reglas centrales de la consigna.
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


@pytest.fixture
def con():
    # Conexión por test (y no por sesión) para no bloquear el archivo al re-correr el ETL
    c = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)
    yield c
    c.close()


def valor(con, sql: str):
    return con.execute(sql).fetchone()[0]


# --- Modelo -------------------------------------------------------------------------------------

def test_fact_sin_duplicados(con):
    duplicados = valor(con, """
        select count(*) from (
            select fecha, id_estacion, id_contaminante, ventana
            from modelo.fact_medicion_diaria
            group by all having count(*) > 1)
    """)
    assert duplicados == 0


def test_fact_es_grilla_completa(con):
    n_dias = valor(con, "select count(*) from modelo.dim_calendario")
    filas = valor(con, "select count(*) from modelo.fact_medicion_diaria")
    assert n_dias == 1004  # 2024-01-01 a 2026-09-30
    assert filas == n_dias * 3 * 5 * 2  # días × estaciones × contaminantes × ventanas


def test_fechas_de_la_fact_existen_en_calendario(con):
    huerfanas = valor(con, """
        select count(*) from modelo.fact_medicion_diaria f
        left join modelo.dim_calendario c using (fecha)
        where c.fecha is null
    """)
    assert huerfanas == 0


def test_staging_conserva_todas_las_filas_del_crudo(con):
    crudo = valor(con, f"select count(*) from read_csv('{config.RAW_AIRE.as_posix()}', all_varchar = true)")
    assert valor(con, "select count(*) from staging.stg_aire") == crudo


# --- Calidad ------------------------------------------------------------------------------------

def test_sin_valores_negativos(con):
    assert valor(con, "select count(*) from modelo.fact_medicion_diaria where valor < 0 or valor_masa < 0") == 0


def test_no_y_no2_no_superan_nox(con):
    violaciones = valor(con, """
        with d as (
            select fecha, id_estacion, ventana,
                   max(valor) filter (where id_contaminante = 'no')  as no_,
                   max(valor) filter (where id_contaminante = 'no2') as no2,
                   max(valor) filter (where id_contaminante = 'nox') as nox
            from modelo.fact_medicion_diaria where tiene_dato group by all)
        select count(*) from d where no_ > nox or no2 > nox
    """)
    assert violaciones == 0


def test_factor_no2_consistente(con):
    # 46,0055 g/mol / 24,45 L/mol = 1,8816 µg/m³ por ppb
    factor = valor(con, "select factor_masa from modelo.dim_contaminante where id_contaminante = 'no2'")
    assert factor == pytest.approx(1.88, abs=0.01)
    minimo, maximo = con.execute("""
        select min(valor_masa / valor), max(valor_masa / valor)
        from modelo.fact_medicion_diaria
        where id_contaminante = 'no2' and tiene_dato and valor >= 5
    """).fetchone()
    assert minimo == pytest.approx(1.88, abs=0.01) and maximo == pytest.approx(1.88, abs=0.01)


def test_ref_oms_tiene_todas_las_combinaciones_usadas(con):
    combinaciones = set(con.execute("select id_contaminante, promedio from modelo.ref_oms").fetchall())
    necesarias = {("no2", "24h"), ("no2", "anual"), ("pm10", "24h"), ("pm10", "anual"), ("co", "24h")}
    assert necesarias <= combinaciones


def test_regla_75_marca_no_validos(con):
    mal_marcados = valor(con, """
        select count(*) from indicadores.agg_anual
        where (completitud < 0.75 and (es_valido or promedio_anual is not null or p99_24h is not null))
           or (completitud >= 0.75 and not es_valido)
    """)
    assert mal_marcados == 0
    no_validos = set(con.execute(
        "select id_estacion, id_contaminante, id_periodo from indicadores.agg_anual where not es_valido"
    ).fetchall())
    # Los dos casos documentados en docs/calidad_datos.md
    assert ("centenario", "no2", "2024") in no_validos
    assert ("cordoba", "co", "2024") in no_validos


def test_outliers_se_marcan_pero_no_se_borran(con):
    marcados, con_valor = con.execute("""
        select count(*), count(valor) from modelo.fact_medicion_diaria where es_outlier
    """).fetchone()
    assert marcados > 0 and marcados == con_valor


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
