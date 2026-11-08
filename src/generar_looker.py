"""Tablas planas para el dashboard de Looker Studio: dashboard/looker/*.csv.

Looker Studio no tiene relaciones entre tablas como un modelo estrella: cada fuente de datos es una tabla
sola. Por eso, en lugar de las 8 tablas de gold, se arman 5 tablas ya unidas (estación, contaminante,
calendario y guía de la OMS pegados a cada fila). Salen de los CSV de data/final (la capa gold exportada), sin
recalcular nada: el dashboard comunica los resultados del ETL. No usa la base DuckDB, así que corre aunque
otro programa (DBeaver) la tenga abierta.

Convenciones pensadas para que Looker Studio detecte bien las columnas:
- fechas como YYYYMMDD y meses como YYYYMM (tipos nativos "Fecha (AAAAMMDD)" y "Año y mes (AAAAMM)");
- banderas verdadero/falso como 1/0 (se suman y se promedian sin fórmulas de texto);
- separador ',' y decimal '.', UTF-8.

Uso (desde la raíz del repo, después del ETL):  python -m src.generar_looker
El ETL (python -m src.etl) también lo corre. Es idempotente: sobrescribe los archivos.
"""

import logging

import duckdb

from src import config

log = logging.getLogger("looker")

DIR_LOOKER = config.RAIZ / "dashboard" / "looker"

# Guía OMS (umbral) del contaminante en la unidad de valor_masa, para líneas de referencia y cálculos.
GUIAS = """
    guias as (
        select id_contaminante,
               max(umbral) filter (where promedio = '24h'   and nivel = 'AQG') as guia_24h,
               max(umbral) filter (where promedio = 'anual' and nivel = 'AQG') as guia_anual,
               max(unidad) filter (where promedio = '24h'   and nivel = 'AQG') as unidad_guia
        from gold.guia_oms
        group by id_contaminante
    )"""

# nombre del archivo -> consulta. Siempre order by all: mismo archivo en cada corrida.
CONSULTAS = {
    # Una fila por día × estación × contaminante (grilla completa, igual que la fact de gold).
    "looker_diaria": f"""
        with {GUIAS}
        select strftime(f.fecha, '%Y%m%d')       as fecha,
               strftime(c.anio_mes, '%Y%m')      as anio_mes,
               c.anio,
               c.estacion_del_anio, c.orden_estacion_del_anio,
               c.tipo_dia, c.tipo_dia_etiqueta, c.orden_tipo_dia,
               e.nombre                          as estacion,
               e.flujo_vehicular, e.fuentes_fijas,
               e.latitud::varchar || ',' || e.longitud::varchar as ubicacion,
               k.nombre                          as contaminante,
               k.codigo_fuente,
               f.n_horas_validas,
               f.tiene_dato::int                 as tiene_dato,
               f.motivo_sin_dato,
               f.valor_masa,
               g.unidad_guia,
               g.guia_24h,
               f.supera_guia::int                as supera_guia,
               f.nivel_oms, f.orden_nivel_oms,
               f.es_outlier::int                 as es_outlier
        from gold.fact_medicion_diaria f
        join gold.dim_calendario c using (fecha)
        join gold.dim_estacion e using (id_estacion)
        join gold.dim_contaminante k using (id_contaminante)
        join guias g using (id_contaminante)
        order by all""",

    # Una fila por hora válida de NO2 (la fact horaria de gold solo tiene NO2).
    "looker_horaria": """
        select strftime(f.fecha, '%Y%m%d') as fecha,
               f.hora,
               c.tipo_dia, c.tipo_dia_etiqueta, c.orden_tipo_dia,
               e.nombre                    as estacion,
               f.valor_masa
        from gold.fact_medicion_horaria f
        join gold.dim_calendario c using (fecha)
        join gold.dim_estacion e using (id_estacion)
        where f.es_valido
        order by all""",

    # Una fila por estación × contaminante × período (años, 2026 parcial y últimos 12 meses).
    "looker_anual": f"""
        with {GUIAS}
        select e.nombre                      as estacion,
               k.nombre                      as contaminante,
               k.codigo_fuente,
               a.periodo, a.orden_periodo, a.tipo_periodo, a.anio,
               a.es_periodo_estudio::int     as es_periodo_estudio,
               a.n_dias_periodo, a.n_dias_con_dato, a.completitud,
               a.es_valido::int              as es_valido,
               a.promedio_anual, a.promedio_referencial,
               g.unidad_guia, g.guia_24h, g.guia_anual,
               a.veces_guia_anual, a.nivel_oms, a.orden_nivel_oms,
               a.p99_24h, a.p99_veces_guia_24h,
               a.pct_dias_supera_24h, a.pct_cumple_guia_24h, a.pct_cumple_it4_24h,
               a.pct_cumple_it3_24h, a.pct_cumple_it2_24h, a.pct_cumple_it1_24h,
               a.racha_maxima_dias,
               strftime(a.racha_desde, '%Y%m%d') as racha_desde,
               strftime(a.racha_hasta, '%Y%m%d') as racha_hasta
        from gold.agg_anual a
        join gold.dim_estacion e using (id_estacion)
        join gold.dim_contaminante k using (id_contaminante)
        join guias g using (id_contaminante)
        order by all""",

    # Una fila por estación × contaminante × tipo de día. Looker Studio no puede calcular "contra el día
    # hábil" con una fórmula (no hay funciones de contexto), así que la variación viene hecha.
    "looker_tipo_dia": f"""
        with {GUIAS},
        por_tipo as (
            select f.id_estacion, f.id_contaminante, c.tipo_dia, c.tipo_dia_etiqueta, c.orden_tipo_dia,
                   count(*)                       as n_dias,
                   avg(f.valor_masa)              as promedio_diario,
                   avg(f.supera_guia::int)        as pct_dias_supera_24h
            from gold.fact_medicion_diaria f
            join gold.dim_calendario c using (fecha)
            where f.tiene_dato
            group by all
        )
        select e.nombre as estacion, k.nombre as contaminante, k.codigo_fuente,
               t.tipo_dia_etiqueta, t.orden_tipo_dia, t.n_dias,
               t.promedio_diario, g.guia_24h, t.pct_dias_supera_24h,
               t.promedio_diario / h.promedio_diario - 1 as variacion_vs_habil
        from por_tipo t
        join por_tipo h on h.id_estacion = t.id_estacion and h.id_contaminante = t.id_contaminante
                       and h.tipo_dia = 'habil'
        join gold.dim_estacion e on e.id_estacion = t.id_estacion
        join gold.dim_contaminante k on k.id_contaminante = t.id_contaminante
        join guias g on g.id_contaminante = t.id_contaminante
        order by all""",

    # Valores horarios por categoría de calidad (página de calidad de datos).
    "looker_calidad": """
        select k.nombre as contaminante, r.categoria, r.n_valores, r.proporcion, r.n_dias,
               strftime(r.primera_fecha, '%Y%m%d') as primera_fecha,
               strftime(r.ultima_fecha, '%Y%m%d')  as ultima_fecha
        from gold.calidad_resumen r
        join gold.dim_contaminante k using (id_contaminante)
        order by all""",
}


def generar() -> None:
    """Escribe los CSV de dashboard/looker/ desde los CSV de data/final."""
    DIR_LOOKER.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()  # en memoria: las tablas de gold son vistas sobre los CSV de data/final
    con.execute("create schema gold")
    for tabla in config.TABLAS_FINALES:
        csv = (config.DIR_FINAL / f"{tabla.split('.')[1]}.csv").as_posix()
        con.execute(f"create view {tabla} as select * from read_csv('{csv}')")
    for nombre, consulta in CONSULTAS.items():
        csv = (DIR_LOOKER / f"{nombre}.csv").as_posix()
        con.execute(f"copy ({consulta}) to '{csv}' (header, delimiter ',')")
        filas = con.execute(f"select count(*) from read_csv('{csv}')").fetchone()[0]
        log.info("  %-16s %7s filas -> dashboard/looker/%s.csv", nombre, f"{filas:,}".replace(",", "."), nombre)
    con.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    if not config.DIR_FINAL.exists():
        raise SystemExit("Falta data/final: correr primero python -m src.etl")
    generar()


if __name__ == "__main__":
    main()
