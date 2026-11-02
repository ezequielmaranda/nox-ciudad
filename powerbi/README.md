# Dashboard en Power BI — guía de armado

El dashboard **no calcula el análisis**: lo muestra. Todo lo pesado (limpieza, modelo, prueba placebo) ya
está en el pipeline y en los notebooks, que dejan tablas listas en `export/`. Power BI solo las lee.
Así cualquiera del equipo puede explicar de dónde sale cada número.

## 1. Generar los datos

```
uv run python run.py --analisis
```

Deja en `export/` (fuera de git; compartirlo por Drive con quien arme el dashboard):

| Archivo | Grano | Para qué página |
|---|---|---|
| `gold_analitico.parquet` | estación × día | Contexto (series, OMS) |
| `gold_sube_diario.parquet` | día | Transporte (actividad, dosis de paro) |
| `dim_calendario.parquet` | día | Filtros por fecha y tipo de día |
| `eventos.parquet` | evento | Etiquetas de los paros |
| `indice_tipo_dia.parquet` | tipo de día × variable | El gradiente (notebook 04) |
| `resultados_evento.parquet` | evento × estación × variable | Resultados por paro (notebook 05) |
| `resultados_grupo.parquet` | grupo × variable | Resultado principal y valor p (notebook 05) |

En Power BI Desktop: **Obtener datos → Parquet** y elegir cada archivo (o **Carpeta** apuntando a
`export/` y filtrar por extensión).

## 2. Modelo de datos

Un modelo estrella chico, con una sola dimensión compartida:

```
dim_calendario[fecha] 1 ──── * gold_analitico[fecha]
dim_calendario[fecha] 1 ──── * gold_sube_diario[fecha]   (dirección única)
dim_calendario[fecha] 1 ──── * resultados_evento[fecha]
```

- `indice_tipo_dia` y `resultados_grupo` quedan sueltas (son tablas de resultados ya agregadas).
- Crear `dim_estacion` con **Inicio → Especificar datos**: una columna `estacion` con CENTENARIO, CORDOBA y
  LA BOCA, y relacionarla 1 → * con `gold_analitico[estacion]` y `resultados_evento[estacion]`.
- Marcar `dim_calendario` como tabla de fechas (columna `fecha`).

## 3. Indicadores (medidas DAX)

Pocas medidas, todas explicables en una frase:

```DAX
Días con NO2 = COUNTROWS ( FILTER ( gold_analitico, NOT ISBLANK ( gold_analitico[no2_24h_ugm3] ) ) )

% días NO2 sobre guía OMS =
DIVIDE (
    COUNTROWS ( FILTER ( gold_analitico, gold_analitico[no2_24h_ugm3] > 25 ) ),
    [Días con NO2]
)

NO2 P99 24 h = PERCENTILEX.INC (
    FILTER ( gold_analitico, NOT ISBLANK ( gold_analitico[no2_24h_ugm3] ) ),
    gold_analitico[no2_24h_ugm3], 0.99 )

NO2 media (µg/m³) = AVERAGE ( gold_analitico[no2_24h_ugm3] )

-- Media geométrica: el promedio "justo" para concentraciones con cola larga (ver notebook 01).
NOx/CO típico = EXP ( AVERAGEX ( FILTER ( gold_analitico, gold_analitico[nox_co_816] > 0 ),
                                 LN ( gold_analitico[nox_co_816] ) ) )

Actividad colectivos = AVERAGE ( gold_sube_diario[actividad_colectivo_vs_habil] )

-- La dosis de paro solo existe de lunes a viernes (fines de semana = vacío, no 0).
Dosis de paro (%) = AVERAGE ( gold_sube_diario[pct_lineas_paradas_ponderado] )

Desvío NOx/CO paros sin colectivos =
CALCULATE ( MAX ( resultados_grupo[desvio_medio_pct] ),
            resultados_grupo[variable] = "NOx/CO", resultados_grupo[grupo] = "sin_colectivos" )

Desvío NOx/CO controles =
CALCULATE ( MAX ( resultados_grupo[desvio_medio_pct] ),
            resultados_grupo[variable] = "NOx/CO", resultados_grupo[grupo] = "control" )
```

Guías OMS 2021 de referencia (µg/m³): NO2 24 h = 25 (metas intermedias 120 y 50), NO2 anual = 10;
PM10 24 h = 45, PM10 anual = 15. La guía de 24 h de la OMS es el percentil 99 (3-4 días por año).

## 4. Páginas (siguen el storytelling)

1. **El problema: el aire de la Ciudad.**
   Tarjetas: `% días NO2 sobre guía OMS`, `NO2 P99 24 h`, `NO2 media`. Línea: NOx 8-16 h por estación
   (eje: `dim_calendario[fecha]`). Filtros: estación y año.
   Mensaje: el NO2 supera la guía casi todos los días en La Boca y Córdoba; el tránsito y el invierno mandan.
2. **El experimento natural: los paros.**
   Línea: `Actividad colectivos` en el tiempo, con los eventos marcados. Tabla de eventos con la dosis
   (`pct_lineas_paradas_ponderado`). Mensaje: hay días en que desaparecen 2 de cada 3 colectivos.
3. **El gradiente.**
   Gráfico de puntos o barras con `indice_tipo_dia` (eje: `grupo` ordenado por `actividad`; leyenda:
   `variable`). Mensaje: cuanto menos colectivos, menor la firma diésel; en los paros el CO no baja.
4. **El resultado.**
   Tarjetas: `Desvío NOx/CO paros sin colectivos` (−43%) y `Desvío NOx/CO controles` (−10%), con el valor p.
   Gráfico de barras horizontales: `resultados_evento[desvio_pct]` por fecha y estación, filtro
   `variable = NOx/CO`, color por `grupo`. Mensaje: la caída es mucho más grande de lo esperable.
5. **Cómo lo hicimos y límites.**
   Esquema del pipeline (fuentes → dbt → notebooks → Power BI) y las 6 limitaciones del notebook 05.

## 5. Formato

- Importar el tema `powerbi/tema_nox.json` (**Vista → Temas → Buscar temas**). Los tres primeros colores
  son las estaciones (Centenario azul, Córdoba naranja, La Boca verde agua): mantenerlos siempre en ese orden
  para que cada estación tenga el mismo color en todas las páginas.
- Paros sin colectivos en violeta (`#6250d6`), controles en amarillo (`#eda100`), resto de días en gris.
- Un mensaje por página, en el título. Etiquetas de datos solo donde hagan falta.
- Siempre la fuente al pie: "Fuente: APrA (GCBA), SUBE (Secretaría de Transporte), SMN".
