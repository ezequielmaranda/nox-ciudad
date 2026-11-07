"""EXTRACCIÓN: baja el dataset horario de calidad del aire de BA Data.

Fuente: dataset "Calidad del aire" de Buenos Aires Data (portal de datos abiertos del GCBA),
publicado por la Agencia de Protección Ambiental (APrA): https://data.buenosaires.gob.ar/dataset/calidad-aire

El archivo `calidad-aire.csv` trae una fila por fecha y hora, desde octubre de 2009, con una
columna por estación y contaminante (CO, NO2 y PM10 de Centenario, Córdoba, La Boca y Palermo).
Cada contaminante viene con el promedio que publica la red:
    CO    ppm     promedio móvil de las 8 horas anteriores
    NO2   ppb     promedio de la hora (los 60 minutos anteriores)
    PM10  µg/m³   promedio móvil de las 24 horas anteriores
El portal también publica archivos por año (calidad_aire_2025.csv, ...): se verificó que son un
subconjunto idéntico de calidad-aire.csv, así que alcanza con este.

Qué hace: descarga el CSV (con reintentos, porque el portal a veces responde 502), verifica que
tenga las columnas esperadas y lo guarda tal como viene en data/raw/calidad-aire.csv. No
transforma nada: la conversión de tipos y las reglas de calidad viven en SQL (dbt, staging).

Este paso es opcional para correr el TP: el CSV crudo ya está en el repo. Sirve para
actualizarlo con los meses nuevos.

Uso (desde la raíz del repo):  python -m src.extract
"""

import sys
import time
import urllib.request

from src.config import DIR_RAW, RAW_AIRE, URL_CALIDAD_AIRE

# Columnas que el staging de dbt necesita (las de Palermo también vienen, pero vacías desde 2010)
COLUMNAS_ESPERADAS = [
    "FECHA", "HORA",
    "CO_CENTENARIO", "NO2_CENTENARIO", "PM10_CENTENARIO",
    "CO_CORDOBA", "NO2_CORDOBA", "PM10_CORDOBA",
    "CO_LA_BOCA", "NO2_LA_BOCA", "PM10_LA_BOCA",
]


def descargar(url: str, intentos: int = 4, espera: float = 2.0) -> bytes:
    """Descarga con reintentos y espera creciente (2, 4, 8 s) ante errores de red o 5xx."""
    for intento in range(1, intentos + 1):
        try:
            pedido = urllib.request.Request(url, headers={"User-Agent": "nox-ciudad-tp/1.0"})
            with urllib.request.urlopen(pedido, timeout=120) as respuesta:
                return respuesta.read()
        except OSError as error:  # URLError, HTTPError y timeouts heredan de OSError
            if intento == intentos:
                raise
            print(f"  intento {intento} falló ({error}); reintento en {espera:.0f} s")
            time.sleep(espera)
            espera *= 2
    raise RuntimeError("no debería llegar acá")


def columnas_faltantes(contenido: bytes) -> list[str]:
    """Columnas esperadas que no están en el encabezado del CSV (lista vacía = formato OK)."""
    encabezado = contenido.decode("utf-8-sig").splitlines()[0]
    columnas = [c.strip().upper() for c in encabezado.split(",")]
    return [c for c in COLUMNAS_ESPERADAS if c not in columnas]


def main() -> None:
    print(f"Descargando {URL_CALIDAD_AIRE}")
    contenido = descargar(URL_CALIDAD_AIRE)
    faltan = columnas_faltantes(contenido)
    if faltan:
        sys.exit(f"El CSV cambió de formato: faltan las columnas {faltan}. No se guardó nada.")
    DIR_RAW.mkdir(parents=True, exist_ok=True)
    RAW_AIRE.write_bytes(contenido)
    filas = contenido.count(b"\n") - 1
    filas_txt = f"{filas:,}".replace(",", ".")
    print(f"Guardado {RAW_AIRE.relative_to(DIR_RAW.parent.parent)}: {filas_txt} filas, {len(contenido) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
