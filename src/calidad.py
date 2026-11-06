"""Controles de calidad que se corren desde Python (el ETL y el notebook de EDA los usan).

Las REGLAS de calidad viven en SQL (dbt/models/01_staging/stg_aire_validado.sql y la carpeta
04_calidad). Este módulo hace dos cosas complementarias:
  * perfil_raw: perfila el CSV crudo ANTES de transformarlo (filas, columnas, fechas, nulos,
    duplicados y valores no numéricos), para dejar registro de con qué se arrancó.
  * resumen_post_etl: después de la carga, junta los números de calidad que hay que mirar
    (valores descartados, completitud, indicadores anuales no válidos, outliers).
"""

from pathlib import Path

import duckdb
import pandas as pd


def perfil_raw(ruta_csv: Path) -> dict:
    """Perfil del CSV crudo, leído todo como texto (igual que lo lee el staging)."""
    con = duckdb.connect()
    con.execute(
        "create table crudo as select * from read_csv(?, header = true, all_varchar = true)",
        [ruta_csv.as_posix()],
    )
    columnas = [c[0] for c in con.execute("describe crudo").fetchall()]
    (filas, fecha_min, fecha_max, n_estaciones, n_archivos) = con.execute(
        """
        select count(*), min(fecha), max(fecha), count(distinct estacion), count(distinct archivo)
        from crudo
        """
    ).fetchone()
    # Duplicados: la clave natural es estación + fecha + contaminante + estadístico
    duplicados = con.execute(
        """
        select count(*) from (
            select estacion, fecha, contaminante, estadistico
            from crudo group by all having count(*) > 1
        )
        """
    ).fetchone()[0]
    nulos = {
        c: con.execute(f'select count(*) from crudo where "{c}" is null').fetchone()[0]
        for c in columnas
    }
    # Textos que no son números (s/d, DND, <LD, otros)
    no_numericos = con.execute(
        r"""
        select
            case
                when lower(valor_crudo) in ('s/d', 'dnd') then lower(valor_crudo)
                when valor_crudo like '<%' then '<límite de detección'
                else 'otro texto: ' || valor_crudo
            end as tipo,
            count(*) as n
        from crudo
        where not regexp_matches(valor_crudo, '^-?[0-9]+(,[0-9]+)?$')
        group by 1
        order by n desc
        """
    ).fetchall()
    fechas_invalidas = con.execute(
        "select count(*) from crudo where try_cast(fecha as date) is null"
    ).fetchone()[0]
    con.close()
    return {
        "archivo": ruta_csv.name,
        "filas": filas,
        "columnas": columnas,
        "fecha_min": fecha_min,
        "fecha_max": fecha_max,
        "estaciones": n_estaciones,
        "pdf_de_origen": n_archivos,
        "duplicados_clave": duplicados,
        "fechas_invalidas": fechas_invalidas,
        "nulos_por_columna": nulos,
        "valores_no_numericos": dict(no_numericos),
    }


def resumen_post_etl(ruta_base: Path) -> dict[str, pd.DataFrame]:
    """Tablas chicas con lo que hay que revisar después de cada corrida del ETL."""
    con = duckdb.connect(ruta_base.as_posix(), read_only=True)
    resumen = {
        # Qué pasó con cada celda de los PDF
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
            where ventana = '24h'
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
            select id_contaminante, ventana, count(*) as n_outliers
            from calidad.calidad_outliers
            group by all
            order by all
            """
        ).df(),
    }
    con.close()
    return resumen
