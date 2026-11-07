"""Controles de calidad que se corren desde Python (el ETL y el notebook de EDA los usan).

Las REGLAS de calidad viven en SQL (dbt/models/01_staging/stg_aire_horario_validado.sql y la
carpeta 04_calidad). Este módulo hace dos cosas complementarias:
  * perfil_raw: perfila el CSV crudo ANTES de transformarlo (filas, columnas, fechas, horas
    fuera de rango, duplicados y tipos de valor), para dejar registro de con qué se arrancó.
  * resumen_post_etl: después de la carga, junta los números de calidad que hay que mirar
    (valores descartados, completitud, indicadores anuales no válidos, outliers).
"""

from pathlib import Path

import duckdb
import pandas as pd


def perfil_raw(ruta_csv: Path) -> dict:
    """Perfil del CSV crudo de BA Data, leído todo como texto (igual que lo lee el staging).

    El CSV es ANCHO: una fila por fecha y hora, una columna por estación × contaminante.
    """
    con = duckdb.connect()
    con.execute(
        "create table crudo as select * from read_csv(?, header = true, all_varchar = true)",
        [ruta_csv.as_posix()],
    )
    columnas = [c[0] for c in con.execute("describe crudo").fetchall()]
    columnas_valor = [c for c in columnas if c.upper() not in ("FECHA", "HORA")]
    (filas, fecha_min, fecha_max, n_dias, horas_fuera) = con.execute(
        """
        with t as (
            select cast(strptime(trim(fecha), '%d%b%Y:%H:%M:%S') as date) as f, try_cast(hora as integer) as h
            from crudo
        )
        select count(*), min(f), max(f), count(distinct f), count(*) filter (where h not between 1 and 24)
        from t
        """
    ).fetchone()
    # Duplicados: la clave natural es fecha + hora
    duplicados = con.execute(
        "select count(*) from (select fecha, hora from crudo group by all having count(*) > 1)"
    ).fetchone()[0]
    # Celdas por tipo de valor, en todas las columnas de mediciones (formato largo con UNPIVOT)
    lista = ", ".join(f'"{c}"' for c in columnas_valor)
    tipos = con.execute(
        rf"""
        select
            case
                when v is null or trim(v) = ''                      then 'vacía'
                when lower(trim(v)) = 's/d'                         then 's/d'
                when trim(v) like '<%'                              then '<límite de detección'
                when regexp_matches(trim(v), '^-?[0-9]+(\.[0-9]+)?$') then 'número'
                else 'otro texto: ' || trim(v)
            end as tipo,
            count(*) as n
        from crudo unpivot include nulls (v for columna in ({lista}))
        group by 1
        order by n desc
        """
    ).fetchall()
    con.close()
    return {
        "archivo": ruta_csv.name,
        "filas": filas,
        "columnas": columnas,
        "fecha_min": fecha_min,
        "fecha_max": fecha_max,
        "dias": n_dias,
        "horas_fuera_de_rango": horas_fuera,
        "duplicados_clave": duplicados,
        "celdas_por_tipo": dict(tipos),
    }


def resumen_post_etl(ruta_base: Path) -> dict[str, pd.DataFrame]:
    """Tablas chicas con lo que hay que revisar después de cada corrida del ETL."""
    con = duckdb.connect(ruta_base.as_posix(), read_only=True)
    resumen = {
        # Qué pasó con cada valor horario del período (celdas del CSV)
        "categorias_de_valores": con.sql(
            """
            select categoria, sum(n_valores) as n_valores,
                   round(100.0 * sum(n_valores) / sum(sum(n_valores)) over (), 2) as pct
            from calidad.calidad_resumen
            group by categoria
            order by n_valores desc
            """
        ).df(),
        # Completitud del promedio de 24 h por estación y contaminante (todo el período)
        "completitud_periodo": con.sql(
            """
            select id_estacion, id_contaminante,
                   round(100.0 * avg(tiene_dato::int), 1) as completitud_pct
            from modelo.fact_medicion_diaria
            group by all
            order by all
            """
        ).df(),
        # Indicadores anuales que la regla del 75% deja afuera
        "indicadores_no_validos": con.sql(
            """
            select id_estacion, id_contaminante, id_periodo, round(100 * completitud, 1) as completitud_pct
            from indicadores.agg_anual
            where not es_valido
            order by all
            """
        ).df(),
        # Outliers marcados (no borrados)
        "outliers": con.sql(
            """
            select id_contaminante, count(*) as n_outliers
            from calidad.calidad_outliers
            group by all
            order by all
            """
        ).df(),
    }
    con.close()
    return resumen
