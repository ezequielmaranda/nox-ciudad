"""Genera el diccionario de datos de docs/modelo_datos.md a partir de la base y de los .yml de dbt.

Uso (desde la raíz, después de `uv run python run.py`):
    uv run python docs/generar_diccionario.py

- Tipos de dato y cantidad de filas: se leen de data/nox.duckdb (lo que hay de verdad en la base).
- Descripciones: primero las de los .yml de dbt (las mismas que muestra `dbt docs`); si una columna no
  tiene, se usa la descripción común de DESCRIPCIONES (columnas que se repiten en varias tablas).
- Reemplaza el bloque entre los marcadores <!-- diccionario:inicio --> y <!-- diccionario:fin -->.
"""
import glob
import pathlib
import re

import duckdb
import yaml

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DOC = RAIZ / "docs" / "modelo_datos.md"

# Orden y capa de las tablas que entran al diccionario (bronze se describe solo a nivel tabla).
TABLAS = [
    ("gold", "gold_analitico"), ("gold", "gold_aire_diario"), ("gold", "gold_sube_diario"),
    ("gold", "gold_meteo_diario"), ("silver", "dim_calendario"), ("silver", "silver_aire"),
    ("silver", "silver_sube"), ("silver", "silver_colectivos_caba_linea_dia"),
    ("silver", "silver_sube_actividad_diaria"), ("silver", "silver_smn_diario"),
    ("bronze", "eventos"), ("bronze", "feriados"),
]

DESCRIPCIONES = {
    # claves y calendario
    "estacion": "Estación de monitoreo de la APrA: CENTENARIO, CORDOBA o LA BOCA.",
    "fecha": "Día (fecha local de Buenos Aires).",
    "anio": "Año de la fecha.",
    "mes": "Mes de la fecha (1-12).",
    "dia_semana": "Día de la semana ISO: 1 = lunes ... 7 = domingo.",
    "nombre_dia": "Nombre del día de la semana.",
    "tipo_dia": "hábil, sábado, domingo o feriado (feriados del seed `feriados`).",
    "feriado": "Nombre del feriado, si lo es.",
    "grupo_dia": "Grupo de día: Hábil normal, Hábil baja actividad, Sábado, Domingo, Feriado, Paro de colectivos o Paro de trenes o subte (de dim_calendario).",
    "es_dia_normal": "Hábil, no feriado y con colectivo, tren y subte por encima del 90% de su uso habitual. Es la base del modelo de referencia.",
    "evento": "Nombre del paro, si ese día hubo uno del estudio.",
    "grupo_evento": "sin_colectivos (paro de colectivos) o trenes_subte (paro de trenes o subte con colectivos funcionando).",
    "pct_lineas_paradas_caba": "% de líneas de colectivo paradas según el seed de eventos (valor de referencia).",
    # aire, bloque 8-16 y 24 h
    "no_816_ppb": "NO, promedio del bloque de 8 a 16 h (ppb).",
    "no2_816_ppb": "NO2, promedio del bloque de 8 a 16 h (ppb).",
    "nox_816_ppb": "NOx, promedio del bloque de 8 a 16 h (ppb). Variable de las hipótesis.",
    "co_816_ppm": "CO, promedio del bloque de 8 a 16 h (ppm).",
    "pm10_816_ugm3": "PM10, promedio del bloque de 8 a 16 h (µg/m³).",
    "nox_co_816": "NOx (ppb) / CO (ppm) del bloque 8-16 h: NOx relativo al CO. Verificación de mecanismo.",
    "no2_24h_ppb": "NO2, promedio de 24 h (ppb).",
    "no2_24h_ugm3": "NO2, promedio de 24 h en µg/m³ (1,88 µg/m³ por ppb a 25 °C). Se compara con la guía OMS (25).",
    "nox_24h_ppb": "NOx, promedio de 24 h (ppb).",
    "co_24h_ppm": "CO, promedio de 24 h (ppm).",
    "pm10_24h_ugm3": "PM10, promedio de 24 h (µg/m³). Guía OMS de 24 h: 45.",
    # SUBE
    "usos_colectivo": "Viajes en colectivo de todo el AMBA ese día (SUBE).",
    "usos_tren": "Viajes en tren del AMBA ese día (SUBE).",
    "usos_subte": "Viajes en subte ese día (SUBE).",
    "usos_colectivo_caba": "Viajes en las 134 líneas de colectivo que circulan por CABA.",
    "ratio_colectivo": "Viajes en colectivo / mediana del mismo día de la semana en días normales (±4 semanas).",
    "ratio_tren": "Viajes en tren / mediana del mismo día de la semana en días normales (±4 semanas).",
    "ratio_subte": "Viajes en subte / mediana del mismo día de la semana en días normales (±4 semanas).",
    "ratio_colectivo_caba": "Viajes del universo CABA / su base habitual (solo días con base, de lunes a viernes).",
    "actividad_colectivo_vs_habil": "Viajes de colectivos de CABA / un día hábil normal típico (±4 semanas). 1 = hábil normal, ≈0,35 = domingo.",
    "lineas_evaluadas": "Líneas con base suficiente (> 2.000 viajes) para calcular si pararon.",
    "pct_lineas_paradas": "% de líneas paradas (menos del 15% de sus viajes habituales), sin ponderar. Vacío los fines de semana.",
    "pct_lineas_paradas_ponderado": "% de líneas paradas ponderado por sus viajes habituales: la dosis del paro. Vacío los fines de semana.",
    "pct_paradas_solo_caba": "Dosis entre las líneas que circulan solo dentro de CABA.",
    "pct_paradas_interjurisdiccionales": "Dosis entre las líneas nacionales (cruzan CABA y provincia).",
    "linea_num": "Número de línea (clave normalizada: se extrae del nombre, que cambia entre archivos).",
    "es_linea_solo_caba": "La línea circula solo dentro de CABA (pasó a jurisdicción de la Ciudad en 2025).",
    "usos": "Cantidad de viajes pagados con SUBE.",
    "etiquetas": "Nombres originales de la línea ese día (pueden ser varios).",
    "empresa": "Empresa operadora.",
    "linea_original": "Nombre de la línea tal como viene en el archivo.",
    "es_amba": "La línea pertenece al AMBA.",
    "tipo_transporte": "COLECTIVO, TREN, SUBTE, etc.",
    "jurisdiccion": "Jurisdicción de la línea (NACIONAL, C.A.B.A, PROVINCIAL, MUNICIPAL).",
    "provincia": "Provincia declarada en el archivo.",
    "municipio": "Municipio declarado en el archivo.",
    "es_dato_preliminar": "El dato está marcado como preliminar por la fuente (desde 2026).",
    "es_colectivo_caba": "La fila pertenece al universo de colectivos que circulan por CABA.",
    # meteorología
    "viento_kmh": "Velocidad media diaria del viento (km/h), promedio de Aeroparque y Observatorio (SMN).",
    "viento_max_kmh": "Ráfaga máxima del día (km/h), máximo de las dos estaciones.",
    "temp_c": "Temperatura media diaria (°C), promedio de las dos estaciones.",
    "humedad_pct": "Humedad relativa media diaria (%).",
    "precipitacion_mm": "Lluvia diaria (mm), máximo de las dos estaciones. Sin registro = 0 (supuesto declarado).",
    "precipitacion_sin_registro": "Ninguna de las dos estaciones informó lluvia ese día.",
    "hubo_lluvia": "Lluvia de 1 mm o más.",
    "estaciones_con_viento": "Cantidad de estaciones del SMN con dato de viento ese día.",
    "temp_media_c": "Temperatura media (°C).", "temp_max_c": "Temperatura máxima (°C).",
    "temp_min_c": "Temperatura mínima (°C).", "presion_hpa": "Presión a nivel de la estación (hPa).",
    "viento_medio_kmh": "Velocidad media del viento (km/h).",
    "viento_max_dir_grados": "Dirección de la ráfaga máxima (grados; viene en decenas de grado).",
    "nubosidad_octavos": "Nubosidad total (octavos).", "heliofania_h": "Horas de sol.",
    # silver_aire
    "contaminante": "NO, NO2, NOx, CO o PM10.",
    "estadistico": "24h, 0-8, 8-16, 16-24 (promedios) o max_1h, min_1h (extremos horarios del día).",
    "valor_crudo": "Valor tal como aparece en el PDF (texto, con coma decimal o 's/d', 'DND', '<4').",
    "unidad_original": "Unidad del PDF: ppb (NO, NO2, NOx), ppm (CO) o µg/m³ (PM10).",
    "unidad_masa": "Unidad de valor_masa: µg/m³ o mg/m³ (CO).",
    "archivo_pdf": "PDF de la APrA del que salió el valor (trazabilidad).",
    # seeds
    "grupo": "sin_colectivos o trenes_subte.",
    "fuente_prensa": "Nota periodística que confirma el paro.",
    "tipo": "inamovible, trasladable o puente.",
    "nombre": "Nombre del feriado.",
}


def descripciones_yml():
    out = {}
    archivos = glob.glob(str(RAIZ / "dbt" / "models" / "**" / "*.yml"), recursive=True)
    archivos += glob.glob(str(RAIZ / "dbt" / "seeds" / "*.yml"))
    for f in archivos:
        y = yaml.safe_load(open(f, encoding="utf-8")) or {}
        for bloque in ("models", "seeds"):
            lista = y.get(bloque) or []
            for m in (lista if isinstance(lista, list) else []):
                out[(m["name"], None)] = " ".join((m.get("description") or "").split())
                for c in m.get("columns", []) or []:
                    if c.get("description"):
                        out[(m["name"], c["name"])] = " ".join(c["description"].split())
    return out


def main():
    yml = descripciones_yml()
    con = duckdb.connect(str(RAIZ / "data" / "nox.duckdb"), read_only=True)
    partes = []
    faltan = []
    for capa, tabla in TABLAS:
        filas = con.execute(f'select count(*) from {capa}."{tabla}"').fetchone()[0]
        cols = con.execute("select column_name, data_type from information_schema.columns "
                           "where table_schema = ? and table_name = ? order by ordinal_position",
                           [capa, tabla]).fetchall()
        partes.append(f"### `{capa}.{tabla}` ({filas:,} filas)\n".replace(",", "."))
        if yml.get((tabla, None)):
            partes.append(yml[(tabla, None)] + "\n")
        partes.append("| Columna | Tipo | Descripción |\n|---|---|---|")
        for nombre, tipo in cols:
            desc = yml.get((tabla, nombre)) or DESCRIPCIONES.get(nombre, "")
            if not desc:
                faltan.append(f"{tabla}.{nombre}")
            partes.append(f"| `{nombre}` | {tipo.replace('HUGEINT', 'BIGINT')} | {desc.replace('|', '/')} |")
        partes.append("")
    con.close()
    bloque = "\n".join(partes)
    texto = DOC.read_text(encoding="utf-8")
    texto = re.sub(r"(<!-- diccionario:inicio -->).*?(<!-- diccionario:fin -->)",
                   lambda m: m.group(1) + "\n" + bloque + "\n" + m.group(2), texto, flags=re.S)
    DOC.write_text(texto, encoding="utf-8")
    print(f"Diccionario actualizado en {DOC.relative_to(RAIZ)}")
    if faltan:
        print("Columnas sin descripción:", ", ".join(faltan))


if __name__ == "__main__":
    main()
