"""EXTRACCIÓN: baja los informes mensuales públicos de calidad del aire y los pasa a CSV.

Fuente: páginas de las estaciones de monitoreo de la Agencia de Protección Ambiental (APrA) del
Gobierno de la Ciudad (https://buenosaires.gob.ar/calidad-del-aire). Hay un PDF por mes,
contaminante y estación (CO, óxidos de nitrógeno y PM10). Cada PDF trae, por día: promedio de
24 h, promedios de 0-8, 8-16 y 16-24 h, máximo y mínimo horario.

Pasos:
  1. Lee las páginas de las tres estaciones y junta los links a PDF.
  2. Reescribe el dominio a static.buenosaires.gob.ar (el link original redirige y da 404).
  3. Descarga los PDF de los años pedidos a data/raw/pdf/ (si ya existen, no los vuelve a bajar).
  4. Extrae la tabla diaria de la página 1 y escribe data/raw/aire_publico.csv en formato largo.
     Los valores quedan como TEXTO (valor_crudo): la conversión a número se hace en SQL (staging).
  5. Deja un manifiesto con cada archivo y su estado en data/raw/aire_publico_manifiesto.csv.

Este paso es opcional para correr el TP: el CSV crudo ya está en el repo. Sirve para
reproducir la extracción o actualizarla con meses nuevos. El sitio a veces bloquea descargas
automáticas o desde fuera de Argentina; en ese caso se pueden guardar las páginas desde el
navegador y usar --paginas.

Uso (desde la raíz del repo):
    python -m src.extract                    # baja y procesa de 2024 en adelante
    python -m src.extract --desde 2023
    python -m src.extract --solo-parsear     # no descarga: procesa los PDF ya bajados
"""

import argparse
import calendar
import csv
import re
import sys
import time
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

from src.config import DIR_PDF, DIR_RAW, RAW_AIRE, RAW_MANIFIESTO

PAGINAS = {
    "CENTENARIO": "https://buenosaires.gob.ar/calidad-del-aire/estacion-parque-centenario",
    "CORDOBA": "https://buenosaires.gob.ar/calidad-del-aire/estacion-cordoba",
    "LA BOCA": "https://buenosaires.gob.ar/calidad-del-aire/estacion-la-boca",
}
HOST_DESCARGA = "https://static.buenosaires.gob.ar"
# El sitio le responde distinto a clientes que no parecen un navegador: se piden como uno.
UA = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-AR,es;q=0.9",
}

MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]  # fmt: skip

# Columnas de la tabla diaria, en el orden en que aparecen en el PDF.
ESTADISTICOS = ["24h", "0-8", "8-16", "16-24", "max_1h", "min_1h"]
# Por tipo de informe: contaminantes de cada grupo y unidad. En CO y PM10 la tabla suele traer
# una columna constante al final ("2,6"), que se descarta; algunos meses no la traen.
TIPOS = {
    "nox": {"contaminantes": ["NO", "NO2", "NOx"], "unidad": "ppb"},
    "co": {"contaminantes": ["CO"], "unidad": "ppm"},
    "pm10": {"contaminantes": ["PM10"], "unidad": "ug/m3"},
}
# Valor válido de una celda: número con coma decimal, "<4" (bajo el límite de detección),
# "s/d" (sin dato) o "DND" (dato no disponible).
VALOR_RE = re.compile(r"^(?:-?\d+(?:,\d+)?|<\d+(?:,\d+)?|s/d|S/D|DND|dnd)$")


def sin_tildes(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def tipo_de_archivo(nombre: str):
    n = sin_tildes(unquote(nombre)).lower()
    for t in ("pm10", "nox", "co"):
        if n.startswith(t + "_") or n.startswith(t + " "):
            return t
    return None


def mes_anio_de_texto(s: str):
    """Busca '<mes> ... <año>' en un nombre de archivo o en el texto del PDF."""
    s = sin_tildes(unquote(s)).lower()
    m = re.search(r"(" + "|".join(MESES) + r")\D{0,3}(20\d{2})", s)
    return (MESES.index(m.group(1)) + 1, int(m.group(2))) if m else (None, None)


def estacion_de_texto(s: str):
    s = sin_tildes(unquote(s)).upper()
    if any(x in s for x in ("CENTENARIO", "CENTENAEIO", "CENTENAIO")):  # hay nombres mal escritos
        return "CENTENARIO"
    if "CORDOBA" in s:
        return "CORDOBA"
    if "BOCA" in s.replace(" ", ""):
        return "LA BOCA"
    return None


def celdas_pagina1(ruta: Path):
    """Devuelve el texto de la página 1 y sus celdas como (texto, x_centro, y_centro).

    pdfminer lee estas planillas por columnas, así que la tabla se reconstruye por posición.
    """
    from pdfminer.high_level import extract_pages
    from pdfminer.layout import LTTextContainer, LTTextLine

    pagina = next(extract_pages(str(ruta), page_numbers=[0]))
    celdas, textos = [], []

    def recorrer(obj):
        if isinstance(obj, LTTextLine):
            t = obj.get_text().strip()
            if not t:
                return
            textos.append(t)
            partes = t.split()
            ancho = (obj.x1 - obj.x0) / len(partes)  # si una línea trae varias celdas, se reparten
            for k, p in enumerate(partes):
                celdas.append((p, obj.x0 + ancho * (k + 0.5), (obj.y0 + obj.y1) / 2))
        elif isinstance(obj, LTTextContainer) or hasattr(obj, "__iter__"):
            for hijo in obj:
                recorrer(hijo)

    recorrer(pagina)
    return "\n".join(textos), celdas


def parsear_tabla(celdas, n_dias: int, ancho: int):
    """Reconstruye la tabla diaria a partir de las posiciones de las celdas.

    Busca una columna con los números 1..n alineados verticalmente (la columna de días), y para
    cada día toma las celdas a su misma altura y a su derecha, ordenadas por x. Tolerancias,
    todas vistas en los PDF publicados:
    - cada fila puede traer de 0 a 2 columnas constantes al final ("2,6", "100"): se descartan;
    - una celda por fila puede tener texto inválido (p. ej. "Lunes"): se conserva como texto crudo;
    - la tabla puede terminar antes del último día del mes (febrero 2024 trae 28 filas, no 29).
    Devuelve [(dia, [valores])] o None si no encuentra una tabla consistente de al menos 28 días.
    """
    unos = [c for c in celdas if c[0] == "1"]
    for _, x_dia, y_uno in unos:
        filas_y = {1: y_uno}
        for dia in range(2, n_dias + 1):
            cand = [c for c in celdas if c[0] == str(dia) and abs(c[1] - x_dia) < 6 and c[2] < filas_y[dia - 1]]
            if not cand:
                break
            filas_y[dia] = max(cand, key=lambda c: c[2])[2]  # el más cercano por debajo
        if len(filas_y) < 28:
            continue
        ultimo = max(filas_y)
        paso = (filas_y[1] - filas_y[ultimo]) / (ultimo - 1)
        tol = paso * 0.45
        filas = []
        for dia, y in filas_y.items():
            fila = sorted((c for c in celdas if abs(c[2] - y) < tol and c[1] > x_dia + 3), key=lambda c: c[1])
            vals = [c[0] for c in fila]
            invalidas = sum(not VALOR_RE.match(v) for v in vals[:ancho])
            if not ancho <= len(vals) <= ancho + 2 or invalidas > 1:
                break
            filas.append((dia, vals[:ancho]))
        if len(filas) == len(filas_y):
            return filas
    return None


def procesar_pdf(ruta: Path, tipo: str, estacion_pagina: str):
    """Devuelve (filas_largas, info) para un PDF.

    Estación: se cruzan la página que enlaza el archivo, el nombre del archivo y el encabezado.
    - Si el nombre del archivo es de otra estación, es un link cruzado y se descarta
      (p. ej. el PM10 de Córdoba de febrero 2026 enlaza al archivo de La Boca).
    - Si solo el encabezado difiere, se toma como error de plantilla y se conservan los datos
      con un aviso (p. ej. el PM10 de La Boca de mayo 2025 dice "Córdoba" en el encabezado,
      pero sus valores son distintos de los del archivo de Córdoba de ese mes).
    """
    texto, celdas = celdas_pagina1(ruta)
    # El nombre aparece como "ESTACIÓN LA BOCA"; antes hay un "Red de Estaciones EPA" que no sirve.
    estacion_pdf = None
    for m in re.finditer(r"ESTACION\s[^\n]{0,40}", sin_tildes(texto).upper()):
        estacion_pdf = estacion_de_texto(m.group(0))
        if estacion_pdf:
            break
    mes, anio = mes_anio_de_texto(texto)
    if mes is None:
        mes, anio = mes_anio_de_texto(ruta.name)
    estacion_nombre = estacion_de_texto(ruta.name)
    info = {"estacion_pdf": estacion_pdf, "mes": mes, "anio": anio}
    if mes is None:
        return [], {**info, "estado": "error: no se encontró mes/año"}
    if estacion_nombre and estacion_nombre != estacion_pagina:
        return [], {**info, "estado": f"descartado: archivo de {estacion_nombre} enlazado desde {estacion_pagina}"}
    aviso = ""
    if estacion_pdf and estacion_pdf != estacion_pagina:
        aviso = f" (aviso: el encabezado dice {estacion_pdf})"

    cfg = TIPOS[tipo]
    n_cont = len(cfg["contaminantes"])
    ancho = len(ESTADISTICOS) * n_cont
    n_dias = calendar.monthrange(anio, mes)[1]
    tabla = parsear_tabla(celdas, n_dias, ancho)
    if tabla is None:
        return [], {**info, "estado": "error: no se pudo leer la tabla diaria"}
    if len(tabla) < n_dias:
        aviso += f" (aviso: la tabla termina el día {len(tabla)} de {n_dias})"
    invalidas = [v for _, vals in tabla for v in vals if not VALOR_RE.match(v)]
    if invalidas:
        aviso += f" (aviso: celdas con texto inválido: {', '.join(sorted(set(invalidas)))})"

    filas = []
    for dia, vals in tabla:
        fecha = f"{anio:04d}-{mes:02d}-{dia:02d}"
        for e, est in enumerate(ESTADISTICOS):
            for c, cont in enumerate(cfg["contaminantes"]):
                filas.append({
                    "estacion": estacion_pagina, "fecha": fecha, "contaminante": cont,
                    "estadistico": est, "valor_crudo": vals[e * n_cont + c],
                    "unidad": cfg["unidad"], "archivo": ruta.name,
                })  # fmt: skip
    return filas, {**info, "estado": "ok" + aviso}


def obtener_html(estacion: str, url: str, sesion, carpeta_paginas: Path | None) -> str:
    """Devuelve el HTML de la página de una estación.

    Con --paginas se usa el HTML guardado desde el navegador (<carpeta>/<ESTACION>.html).
    Si la descarga no trae links a PDF, se guarda lo recibido para diagnóstico.
    """
    if carpeta_paginas is not None:
        return (carpeta_paginas / f"{estacion}.html").read_text(encoding="utf-8", errors="replace")
    r = sesion.get(url, headers=UA, timeout=60)
    if ".pdf" not in r.text.lower():
        debug = DIR_RAW / f"debug_pagina_{estacion.replace(' ', '_')}.html"
        debug.write_text(r.text, encoding="utf-8", errors="replace")
        titulo = re.search(r"<title>(.*?)</title>", r.text, flags=re.IGNORECASE | re.DOTALL)
        print(f"AVISO {estacion}: la página no trae links a PDF. HTTP {r.status_code}, URL final {r.url}, "
              f"{len(r.text)} caracteres, título: {titulo.group(1).strip()[:80] if titulo else '-'}. "
              f"Guardado en {debug}", file=sys.stderr)
    return r.text


def listar_links(estacion: str, html: str):
    """Links a PDF de la página, sin repetir el mismo archivo (a veces aparece con dos dominios)."""
    hrefs = re.findall(r'href="([^"]+\.pdf)"', html, flags=re.IGNORECASE)
    salida, vistos = [], set()
    for href in hrefs:
        partes = urlsplit(href)
        if partes.path in vistos:
            continue
        vistos.add(partes.path)
        nombre = unquote(partes.path.rsplit("/", 1)[-1])
        tipo = tipo_de_archivo(nombre)
        if tipo is None:
            continue
        mes, anio = mes_anio_de_texto(nombre)
        original = href if partes.netloc else "https://buenosaires.gob.ar" + partes.path
        salida.append({
            "estacion_pagina": estacion, "tipo": tipo, "mes_nombre": mes, "anio_nombre": anio,
            "archivo": nombre, "url_original": original, "url_descarga": HOST_DESCARGA + partes.path,
        })  # fmt: skip
    return salida


def descargar_pdf(sesion, link: dict):
    """Prueba el dominio static y, si falla, la URL original. Devuelve (bytes, estado)."""
    estado = ""
    for url in (link["url_descarga"], link["url_original"]):
        try:
            r = sesion.get(url, headers=UA, timeout=120)
        except Exception as e:
            estado = f"error descarga: {e.__class__.__name__}"
            continue
        if r.status_code == 200 and r.content.startswith(b"%PDF"):
            return r.content, "descargado"
        estado = f"error descarga: HTTP {r.status_code}"
    return None, estado


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--desde", type=int, default=2024, help="primer año a procesar")
    ap.add_argument("--solo-parsear", action="store_true", help="no descarga; procesa lo ya bajado")
    ap.add_argument("--paginas", type=Path, default=None,
                    help="carpeta con las páginas de las estaciones guardadas desde el navegador "
                         "(CENTENARIO.html, CORDOBA.html, LA BOCA.html), si el sitio bloquea la descarga")
    args = ap.parse_args()
    DIR_RAW.mkdir(parents=True, exist_ok=True)

    import requests

    sesion = requests.Session()
    manifiesto, filas = [], []
    if args.solo_parsear:
        for ruta in sorted(DIR_PDF.glob("*/*.pdf")):
            tipo = tipo_de_archivo(ruta.name)
            if tipo:
                manifiesto.append({"estacion_pagina": ruta.parent.name, "tipo": tipo, "archivo": ruta.name,
                                   "url_original": "", "url_descarga": "", "ruta": ruta})
    else:
        for estacion, url in PAGINAS.items():
            html = obtener_html(estacion, url, sesion, args.paginas)
            links = listar_links(estacion, html)
            print(f"{estacion}: {len(links)} PDF enlazados")
            for link in links:
                if link["anio_nombre"] is not None and link["anio_nombre"] < args.desde:
                    continue
                destino = DIR_PDF / estacion / link["archivo"]
                destino.parent.mkdir(parents=True, exist_ok=True)
                if not destino.exists():
                    contenido, estado = descargar_pdf(sesion, link)
                    if contenido is None:
                        manifiesto.append({**link, "ruta": None, "estado": estado})
                        continue
                    destino.write_bytes(contenido)
                    time.sleep(0.5)  # no saturar el servidor
                manifiesto.append({**link, "ruta": destino})

    for item in manifiesto:
        if item.get("ruta") is None:
            continue
        try:
            nuevas, info = procesar_pdf(item["ruta"], item["tipo"], item["estacion_pagina"])
        except Exception as e:  # PDF dañado u otra estructura
            nuevas, info = [], {"estado": f"error: {e}"}
        if info.get("anio") is not None and info["anio"] < args.desde:
            continue
        item.update(info)
        filas.extend(nuevas)

    # Si un mismo mes/contaminante/estación tiene dos archivos (p. ej. uno "corregido"),
    # queda el último en orden alfabético y se avisa.
    vistos = {}
    for f in filas:
        vistos.setdefault((f["estacion"], f["fecha"], f["contaminante"], f["estadistico"]), []).append(f)
    duplicados = {k: v for k, v in vistos.items() if len(v) > 1}
    if duplicados:
        archivos = sorted({tuple(sorted(x["archivo"] for x in v)) for v in duplicados.values()})
        print(f"AVISO: {len(duplicados)} valores con más de un archivo de origen; se usa el último:", file=sys.stderr)
        for a in archivos:
            print("   ", " | ".join(a), file=sys.stderr)
    finales = [sorted(v, key=lambda x: x["archivo"])[-1] for v in vistos.values()]
    finales.sort(key=lambda f: (f["estacion"], f["fecha"], f["contaminante"], f["estadistico"]))

    with RAW_AIRE.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["estacion", "fecha", "contaminante", "estadistico",
                                           "valor_crudo", "unidad", "archivo"])
        w.writeheader()
        w.writerows(finales)

    campos = ["estacion_pagina", "tipo", "archivo", "estacion_pdf", "mes", "anio", "estado",
              "url_original", "url_descarga"]
    with RAW_MANIFIESTO.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=campos, extrasaction="ignore")
        w.writeheader()
        w.writerows(manifiesto)

    estados = {}
    for m in manifiesto:
        clave = m.get("estado", "fuera del período").split(":")[0].split(" (")[0]
        estados[clave] = estados.get(clave, 0) + 1
    print(f"\n{len(finales)} filas -> {RAW_AIRE}")
    print("Archivos por estado:", estados)
    for m in manifiesto:
        estado = m.get("estado", "")
        if estado and not estado.startswith("ok") or "aviso" in estado:
            print(f"  {m['estacion_pagina']} | {m['archivo']} | {estado}", file=sys.stderr)


if __name__ == "__main__":
    main()
