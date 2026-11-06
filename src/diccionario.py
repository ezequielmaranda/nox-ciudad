"""Genera docs/diccionario_datos.md: cada columna de las tablas finales con su tipo y descripción.

Las descripciones se escriben UNA sola vez, en los .yml de dbt (dbt/models/**/_*.yml). De ahí
salen la documentación navegable de dbt (`make docs`) y este diccionario, así que no se
desincronizan. Los tipos se leen de la base DuckDB ya construida.
"""

import json

import duckdb

from src import config


def generar() -> None:
    manifest = json.loads((config.DIR_DBT / "target" / "manifest.json").read_text(encoding="utf-8"))
    nodos = {
        n["name"]: n
        for n in manifest["nodes"].values()
        if n["resource_type"] in ("model", "seed")
    }
    con = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)

    lineas = [
        "# Diccionario de datos",
        "",
        "> Archivo generado por `python -m src.etl` a partir de las descripciones de los `.yml` de dbt.",
        "> No editar a mano: cambiar la descripción en `dbt/models/` y volver a correr el ETL.",
        "",
        "Tablas finales que se exportan a `data/final/` (CSV y Parquet) y se cargan en Power BI.",
        "",
        "| Tabla | Schema | Filas | Descripción |",
        "|---|---|---|---|",
    ]
    detalle = []
    for tabla in config.TABLAS_FINALES:
        schema, nombre = tabla.split(".")
        nodo = nodos.get(nombre, {})
        filas = con.execute(f"select count(*) from {tabla}").fetchone()[0]
        descripcion = " ".join(nodo.get("description", "").split())
        filas_txt = f"{filas:,}".replace(",", ".")  # separador de miles a la argentina
        lineas.append(f"| [`{nombre}`](#{nombre}) | {schema} | {filas_txt} | {descripcion} |")

        columnas = con.execute(
            """
            select column_name, data_type
            from information_schema.columns
            where table_schema = ? and table_name = ?
            order by ordinal_position
            """,
            [schema, nombre],
        ).fetchall()
        desc_cols = nodo.get("columns", {})
        detalle += ["", f"## {nombre}", "", descripcion, "", "| Columna | Tipo | Descripción |", "|---|---|---|"]
        for columna, tipo in columnas:
            texto = " ".join(desc_cols.get(columna, {}).get("description", "").split())
            detalle.append(f"| `{columna}` | {tipo} | {texto.replace('|', '/')} |")
    con.close()

    salida = config.DIR_DOCS / "diccionario_datos.md"
    salida.write_text("\n".join(lineas + detalle) + "\n", encoding="utf-8")
