"""Genera el proyecto de Power BI (PBIP) del dashboard: modelo semántico + informe base.

    dashboard/AireOMS.pbip                 se abre con Power BI Desktop (agosto 2026 o posterior)
    dashboard/AireOMS.SemanticModel/       modelo en TMDL: tablas, relaciones y medidas DAX
    dashboard/AireOMS.Report/              informe en PBIR: 3 páginas vacías + tema de colores

El modelo sale de lo que ya existe en el repo, así no se desincroniza:
  * tablas y tipos: la base DuckDB que arma el ETL (los datos se cargan de los CSV de data/final);
  * descripciones de tablas y columnas: los .yml de dbt (dbt/target/manifest.json);
  * relaciones y medidas: definidas abajo, en este archivo.
Los gráficos se arman a mano en Power BI Desktop siguiendo docs/powerbi_spec.md.

Uso (después del ETL):  python -m src.generar_pbip
Si el informe ya tiene gráficos armados, no hace nada (para no perderlos); --forzar regenera igual.
"""

import json
import shutil
import sys
import uuid

import duckdb

from src import config, diccionario

NOMBRE = "AireOMS"
DIR_DASH = config.RAIZ / "dashboard"
DIR_MODELO = DIR_DASH / f"{NOMBRE}.SemanticModel"
DIR_INFORME = DIR_DASH / f"{NOMBRE}.Report"
TEMA_BASE = "Fluent2-CY26SU08"  # tema base de Power BI (copiado de un proyecto oficial de Microsoft, licencia MIT)
TEMA_PROPIO = "TemaAireOMS.json"
RUTA_POR_DEFECTO = r"C:\nox-ciudad\data\final" + "\\"

# Tablas del modelo: toda la capa gold (config.TABLAS_FINALES), en el mismo orden
TABLAS = [t.split(".")[1] for t in config.TABLAS_FINALES]

# Columnas con categoría de datos (para que el visual de mapa las reconozca)
CATEGORIA = {("dim_estacion", "latitud"): "Latitude", ("dim_estacion", "longitud"): "Longitude"}

# Columnas de texto que se ordenan por otra columna (Herramientas de columna → Ordenar por columna)
ORDENAR_POR = {
    ("dim_estacion", "nombre"): "orden",
    ("dim_contaminante", "nombre"): "orden",
    ("dim_contaminante", "codigo_fuente"): "orden",
    ("dim_calendario", "nombre_mes"): "mes",
    ("dim_calendario", "nombre_dia"): "dia_semana",
    ("dim_calendario", "tipo_dia_etiqueta"): "orden_tipo_dia",
    ("dim_calendario", "estacion_del_anio"): "orden_estacion_del_anio",
    ("guia_oms", "nivel"): "orden_exigencia",
    ("guia_oms", "nivel_etiqueta"): "orden_exigencia",
    ("fact_medicion_diaria", "nivel_oms"): "orden_nivel_oms",
    ("agg_anual", "periodo"): "orden_periodo",
    ("agg_anual", "nivel_oms"): "orden_nivel_oms",
}

# Columnas que se muestran como porcentaje
PORCENTAJES = {"completitud", "completitud_peor_trimestre", "pct_dias_supera_24h", "pct_cumple_guia_24h",
               "pct_cumple_it4_24h", "pct_cumple_it3_24h", "pct_cumple_it2_24h", "pct_cumple_it1_24h",
               "proporcion"}

# Relaciones 1 a varios: (tabla del lado "varios", columna) → (dimensión, columna). Filtro en una dirección.
RELACIONES = [
    ("fact_medicion_diaria", "fecha", "dim_calendario", "fecha"),
    ("fact_medicion_diaria", "id_estacion", "dim_estacion", "id_estacion"),
    ("fact_medicion_diaria", "id_contaminante", "dim_contaminante", "id_contaminante"),
    ("fact_medicion_horaria", "fecha", "dim_calendario", "fecha"),
    ("fact_medicion_horaria", "id_estacion", "dim_estacion", "id_estacion"),
    ("fact_medicion_horaria", "id_contaminante", "dim_contaminante", "id_contaminante"),
    ("agg_anual", "id_estacion", "dim_estacion", "id_estacion"),
    ("agg_anual", "id_contaminante", "dim_contaminante", "id_contaminante"),
    ("guia_oms", "id_contaminante", "dim_contaminante", "id_contaminante"),
    ("calidad_resumen", "id_contaminante", "dim_contaminante", "id_contaminante"),
]

# Filtro "días con dato" de la fact diaria (las filas sin dato existen porque la fact es una grilla completa)
CON_DATO = "fact_medicion_diaria[tiene_dato] = TRUE ()"

# Medidas DAX: (nombre, formato, descripción, expresión)
MEDIDAS = [
    ("Días válidos", "#,0",
     "Días con dato válido del promedio de 24 h. Mostrar siempre junto a un porcentaje.",
     f"""CALCULATE ( COUNTROWS ( fact_medicion_diaria ), {CON_DATO} )"""),
    ("Completitud %", "0.0%",
     "Días con dato / días del calendario (la fact es una grilla completa). Con dim_calendario[anio_mes] en "
     "columnas arma el heatmap de completitud mensual.",
     """DIVIDE ( [Días válidos], COUNTROWS ( fact_medicion_diaria ) )"""),
    ("Días sobre guía", "#,0",
     "Días cuyo promedio de 24 h supera la guía OMS.",
     """CALCULATE ( COUNTROWS ( fact_medicion_diaria ), fact_medicion_diaria[supera_guia] = TRUE () )"""),
    ("% Días sobre guía", "0.0%",
     "Días sobre la guía / días con dato (un día sin dato no cuenta como día limpio).",
     """DIVIDE ( [Días sobre guía], [Días válidos] )"""),
    ("% Días que cumplen IT2", "0.0%",
     "Días que cumplen el objetivo intermedio IT2 diario o uno más exigente (NO2: 50 µg/m³). No aplica al CO.",
     f"""DIVIDE (
    CALCULATE ( COUNTROWS ( fact_medicion_diaria ), fact_medicion_diaria[orden_nivel_oms] <= 4, {CON_DATO} ),
    [Días válidos]
)"""),
    ("Promedio diario", "#,0.0",
     "Promedio de los valores diarios en la unidad de la guía (µg/m³; mg/m³ para el CO).",
     """AVERAGE ( fact_medicion_diaria[valor_masa] )"""),
    ("Promedio anual", "#,0.0",
     "Promedio anual de agg_anual con la regla del 75% aplicada. Usar con una estación, un contaminante y un "
     "período (agg_anual[periodo]); sirve también para la serie de contexto 2010-2025.",
     """CALCULATE ( AVERAGE ( agg_anual[promedio_anual] ), agg_anual[es_valido] = TRUE () )"""),
    ("Veces sobre guía anual", "0.0",
     "Promedio anual / guía anual de la OMS.",
     """DIVIDE ( [Promedio anual], AVERAGE ( agg_anual[guia_anual] ) )"""),
    ("Nivel OMS anual", None,
     "Escalón OMS del promedio anual (AQG, IT4 … IT1, > IT1).",
     """SELECTEDVALUE ( agg_anual[nivel_oms], "—" )"""),
    ("Percentil 99", "#,0.0",
     "Percentil 99 de los valores diarios (definición formal de la guía de 24 h). Vacío si la completitud es menor a 75%.",
     f"""IF (
    [Completitud %] >= 0.75,
    CALCULATE ( PERCENTILE.INC ( fact_medicion_diaria[valor_masa], 0.99 ), {CON_DATO} )
)"""),
    ("Guía OMS 24 h", "#,0.##",
     "Guía OMS de 24 h del contaminante filtrado.",
     """CALCULATE ( MAX ( guia_oms[umbral] ), guia_oms[promedio] = "24h", guia_oms[nivel] = "AQG" )"""),
    ("Guía OMS anual", "#,0.##",
     "Guía OMS anual del contaminante filtrado (vacía para el CO).",
     """CALCULATE ( MAX ( guia_oms[umbral] ), guia_oms[promedio] = "anual", guia_oms[nivel] = "AQG" )"""),
    ("P99 veces la guía", "0.00",
     "Percentil 99 / guía de 24 h.",
     """DIVIDE ( [Percentil 99], [Guía OMS 24 h] )"""),
    ("Racha máxima", "#,0",
     "Racha más larga de días con dato seguidos sobre la guía en el período de estudio (gaps and islands en SQL; "
     "huecos de hasta 7 días sin dato no la cortan).",
     """CALCULATE ( MAX ( agg_anual[racha_maxima_dias] ), agg_anual[es_periodo_estudio] = TRUE () )"""),
    ("Variación vs. hábil", "+0.0%;-0.0%;0.0%",
     "Diferencia del promedio diario contra el día hábil, para la matriz por tipo de día.",
     """VAR habil =
    CALCULATE (
        [Promedio diario],
        REMOVEFILTERS ( dim_calendario[tipo_dia_etiqueta], dim_calendario[orden_tipo_dia] ),
        dim_calendario[tipo_dia] = "habil"
    )
RETURN
    DIVIDE ( [Promedio diario] - habil, habil )"""),
    ("Estación más comprometida", None,
     "Estación con mayor % de días sobre la guía en el contexto filtrado.",
     """VAR t =
    ADDCOLUMNS ( VALUES ( dim_estacion[nombre] ), "@pct", [% Días sobre guía] )
RETURN
    MAXX ( TOPN ( 1, t, [@pct], DESC ), dim_estacion[nombre] )"""),
    ("% Días sobre guía (texto)", None,
     "Texto para tarjetas, por ejemplo: 95,0% de 900 días.",
     'FORMAT ( [% Días sobre guía], "0.0%" ) & " de " & FORMAT ( [Días válidos], "#,0" ) & " días"'),
    ("NO₂ horario promedio", "#,0.0",
     "Promedio de las horas válidas de NO2 en µg/m³ (perfil horario por tipo de día, eje = fact_medicion_horaria[hora]).",
     """CALCULATE ( AVERAGE ( fact_medicion_horaria[valor_masa] ), fact_medicion_horaria[es_valido] = TRUE () )"""),
]

TIPOS = {"VARCHAR": "string", "BIGINT": "int64", "INTEGER": "int64", "DOUBLE": "double",
         "BOOLEAN": "boolean", "DATE": "dateTime"}
# Cómo se le dice a Power Query cada tipo del modelo al leer el CSV
TIPOS_M = {"string": "type text", "int64": "Int64.Type", "double": "type number",
           "boolean": "type logical", "dateTime": "type date"}
ESQUEMAS = {t.split(".")[1]: t for t in config.TABLAS_FINALES}  # dim_estacion -> gold.dim_estacion


def guid(*partes) -> str:
    # Identificadores estables: el mismo objeto recibe siempre el mismo lineageTag (archivos idénticos en cada corrida)
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "nox-ciudad/" + "/".join(partes)))


def nombre_tmdl(n: str) -> str:
    # Entre comillas simples si tiene espacios o caracteres especiales; la comilla se duplica
    if any(c in n for c in " .=:'\"%()/-+#&") or n[0].isdigit():
        return "'" + n.replace("'", "''") + "'"
    return n


def descripcion(texto: str, sangria: str) -> list[str]:
    texto = " ".join((texto or "").split())
    return [f"{sangria}/// {texto}"] if texto else []


def escribir(ruta, texto: str) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    # UTF-8 sin BOM y fin de línea CRLF, como guarda Power BI Desktop
    if ruta.suffix == ".tmdl" and not texto.endswith("\n\n"):
        texto = texto.rstrip("\n") + "\n\n"  # Power BI termina cada .tmdl con una línea vacía
    ruta.write_bytes(texto.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def escribir_json(ruta, datos) -> None:
    escribir(ruta, json.dumps(datos, indent=2, ensure_ascii=False) + "\n")


def tabla_tmdl(con, tabla: str, nodo: dict) -> str:
    columnas = con.execute(f"describe {ESQUEMAS[tabla]}").fetchall()
    tipos_m = ", ".join(f'{{"{col}", {TIPOS_M[TIPOS[tipo]]}}}' for col, tipo, *_ in columnas)
    desc_cols = nodo.get("columns", {})
    L = descripcion(nodo.get("description", ""), "")
    L += [f"table {nombre_tmdl(tabla)}", f"\tlineageTag: {guid('tabla', tabla)}", ""]
    for col, tipo_duck, *_ in columnas:
        tipo = TIPOS[tipo_duck]
        L += descripcion(desc_cols.get(col, {}).get("description", ""), "\t")
        L.append(f"\tcolumn {nombre_tmdl(col)}")
        L.append(f"\t\tdataType: {tipo}")
        if col.startswith("id_"):
            L.append("\t\tisHidden")
        if tipo == "dateTime":
            L.append("\t\tformatString: Short Date")
        elif col in PORCENTAJES:
            L.append("\t\tformatString: 0.0%")
        elif tipo == "int64":
            L.append("\t\tformatString: 0")
        L.append(f"\t\tlineageTag: {guid('columna', tabla, col)}")
        if (tabla, col) in CATEGORIA:
            L.append(f"\t\tdataCategory: {CATEGORIA[(tabla, col)]}")
        L.append("\t\tsummarizeBy: none")
        L.append(f"\t\tsourceColumn: {col}")
        if (tabla, col) in ORDENAR_POR:
            L.append(f"\t\tsortByColumn: {nombre_tmdl(ORDENAR_POR[(tabla, col)])}")
        L += ["", "\t\tannotation SummarizationSetBy = User"]
        if tipo == "dateTime":
            L += ["", "\t\tannotation UnderlyingDateTimeDataType = Date"]
        L.append("")
    L += [
        f"\tpartition {nombre_tmdl(tabla)} = m",
        "\t\tmode: import",
        "\t\tsource =",
        "\t\t\t\tlet",
        f'\t\t\t\t    Origen = Csv.Document(File.Contents(RutaDatos & "{tabla}.csv"), '
        '[Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),',
        "\t\t\t\t    Encabezados = Table.PromoteHeaders(Origen, [PromoteAllScalars = true]),",
        # En el CSV un nulo es una celda vacía: se vuelve a null para que no quede como texto vacío
        '\t\t\t\t    SinVacios = Table.ReplaceValue(Encabezados, "", null, Replacer.ReplaceValue, '
        "Table.ColumnNames(Encabezados)),",
        # "en-US" porque el CSV usa punto decimal; con la configuración en español, 0.229 se leería como 229
        f'\t\t\t\t    Tipos = Table.TransformColumnTypes(SinVacios, {{{tipos_m}}}, "en-US")',
        "\t\t\t\tin",
        "\t\t\t\t    Tipos",
        "",
        "\tannotation PBI_ResultType = Table",
        "",
    ]
    return "\n".join(L)


def medidas_tmdl() -> str:
    L = ["/// Medidas DAX del dashboard.", "table _Medidas",
         f"\tlineageTag: {guid('tabla', '_Medidas')}", ""]
    for nombre, formato, desc, expr in MEDIDAS:
        L += descripcion(desc, "\t")
        if "\n" in expr:  # expresión de varias líneas: va abajo, un nivel más adentro
            L.append(f"\tmeasure {nombre_tmdl(nombre)} =")
            L += ["\t\t\t" + linea for linea in expr.split("\n")]
        else:  # una sola línea: en la misma línea, como lo guarda Power BI
            L.append(f"\tmeasure {nombre_tmdl(nombre)} = {expr}")
        if formato:
            L.append(f"\t\tformatString: {formato}")
        L += [f"\t\tlineageTag: {guid('medida', nombre)}", ""]
    L += [
        "\tcolumn Columna",
        "\t\tdataType: string",
        "\t\tisHidden",
        f"\t\tlineageTag: {guid('columna', '_Medidas', 'Columna')}",
        "\t\tsummarizeBy: none",
        "\t\tsourceColumn: Columna",
        "",
        "\t\tannotation SummarizationSetBy = Automatic",
        "",
        "\tpartition _Medidas = m",
        "\t\tmode: import",
        "\t\tsource =",
        "\t\t\t\tlet",
        "\t\t\t\t    Origen = #table(type table [Columna = text], {})",
        "\t\t\t\tin",
        "\t\t\t\t    Origen",
        "",
        "\tannotation PBI_ResultType = Table",
        "",
    ]
    return "\n".join(L)


def generar_modelo() -> None:
    nodos = diccionario.nodos_dbt()
    d = DIR_MODELO / "definition"
    if d.exists():
        shutil.rmtree(d)
    escribir_json(DIR_MODELO / "definition.pbism", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
        "version": "4.2",
        "settings": {},
    })
    escribir(d / "database.tmdl", "database\n\tcompatibilityLevel: 1606\n\n")
    todas = ["_Medidas"] + TABLAS
    orden = json.dumps(["RutaDatos"] + todas, ensure_ascii=False)
    escribir(d / "model.tmdl", "\n".join([
        "model Model",
        "\tculture: es-AR",
        "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
        "\tsourceQueryCulture: es-AR",
        "\tdataAccessOptions",
        "\t\tlegacyRedirects",
        "\t\treturnErrorValuesAsNull",
        "",
        "annotation __PBI_TimeIntelligenceEnabled = 0",
        "",
        f"annotation PBI_QueryOrder = {orden}",
        "",
        'annotation PBI_ProTooling = ["DevMode"]',
        "",
    ] + [f"ref table {nombre_tmdl(t)}" for t in todas]) + "\n\n")
    escribir(d / "expressions.tmdl", "\n".join([
        "/// Carpeta data/final del repo, con la barra final. Cambiarla en Transformar datos > Administrar parámetros.",
        f'expression RutaDatos = "{RUTA_POR_DEFECTO}" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
        f"\tlineageTag: {guid('expresion', 'RutaDatos')}",
        "",
        "\tannotation PBI_ResultType = Text",
        "",
    ]) + "\n")
    rel = []
    for desde, cd, hacia, ch in RELACIONES:
        rel += [f"relationship {guid('relacion', desde, cd, hacia, ch)}",
                f"\tfromColumn: {nombre_tmdl(desde)}.{nombre_tmdl(cd)}",
                f"\ttoColumn: {nombre_tmdl(hacia)}.{nombre_tmdl(ch)}", ""]
    escribir(d / "relationships.tmdl", "\n".join(rel) + "\n")
    con = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)
    escribir(d / "tables" / "_Medidas.tmdl", medidas_tmdl())
    for t in TABLAS:
        escribir(d / "tables" / f"{t}.tmdl", tabla_tmdl(con, t, nodos.get(t, {})))
    con.close()


def generar_informe() -> None:
    d = DIR_INFORME / "definition"
    if d.exists():
        shutil.rmtree(d)
    escribir_json(DIR_INFORME / "definition.pbir", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json",
        "version": "4.0",
        "datasetReference": {"byPath": {"path": f"../{NOMBRE}.SemanticModel"}},
    })
    escribir_json(d / "version.json", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json",
        "version": "2.0.0",
    })
    version = {"visual": "2.12.0", "report": "3.4.0", "page": "2.3.1"}
    escribir_json(d / "report.json", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json",
        "themeCollection": {
            "baseTheme": {"name": TEMA_BASE, "reportVersionAtImport": version, "type": "SharedResources"},
            "customTheme": {"name": TEMA_PROPIO, "reportVersionAtImport": version, "type": "RegisteredResources"},
        },
        "resourcePackages": [
            {"name": "SharedResources", "type": "SharedResources",
             "items": [{"name": TEMA_BASE, "path": f"BaseThemes/{TEMA_BASE}.json", "type": "BaseTheme"}]},
            {"name": "RegisteredResources", "type": "RegisteredResources",
             "items": [{"name": TEMA_PROPIO, "path": TEMA_PROPIO, "type": "CustomTheme"}]},
        ],
        "settings": {
            "useStylableVisualContainerHeader": True,
            "exportDataMode": "AllowSummarized",
            "defaultDrillFilterOtherVisuals": True,
            "allowChangeFilterTypes": True,
            "useEnhancedTooltips": True,
            "useDefaultAggregateDisplayName": True,
        },
    })
    paginas = [("resumen", "Resumen"), ("detalle", "Detalle"), ("calidad", "Calidad de datos")]
    escribir_json(d / "pages" / "pages.json", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json",
        "pageOrder": [p for p, _ in paginas],
        "activePageName": paginas[0][0],
    })
    for nombre, titulo in paginas:
        escribir_json(d / "pages" / nombre / "page.json", {
            "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json",
            "name": nombre,
            "displayName": titulo,
            "displayOption": "FitToPage",
            "height": 720,
            "width": 1280,
        })
    # Temas: el base (de Power BI) y el propio (colores del TP, docs/powerbi_tema.json)
    base = DIR_INFORME / "StaticResources" / "SharedResources" / "BaseThemes" / f"{TEMA_BASE}.json"
    base.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(config.RAIZ / "src" / "recursos" / f"{TEMA_BASE}.json", base)
    tema = json.loads((config.DIR_DOCS / "powerbi_tema.json").read_text(encoding="utf-8"))
    tema["name"] = TEMA_PROPIO
    escribir_json(DIR_INFORME / "StaticResources" / "RegisteredResources" / TEMA_PROPIO, tema)


def main() -> None:
    # Protección: si el equipo ya armó gráficos en Power BI, no se pisa nada (salvo con --forzar)
    con_graficos = list((DIR_INFORME / "definition" / "pages").glob("*/visuals/*"))
    if con_graficos and "--forzar" not in sys.argv:
        sys.exit(f"El informe ya tiene {len(con_graficos)} gráficos armados en Power BI: no se regenera para no "
                 "perderlos. Los cambios del modelo se hacen en Power BI (o usar --forzar, que borra los gráficos).")
    generar_modelo()
    generar_informe()
    escribir_json(DIR_DASH / f"{NOMBRE}.pbip", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/pbip/pbipProperties/1.0.0/schema.json",
        "version": "1.0",
        "artifacts": [{"report": {"path": f"{NOMBRE}.Report"}}],
        "settings": {"enableAutoRecovery": True},
    })
    print(f"Proyecto de Power BI generado en {DIR_DASH.relative_to(config.RAIZ)}/{NOMBRE}.pbip")


if __name__ == "__main__":
    main()
