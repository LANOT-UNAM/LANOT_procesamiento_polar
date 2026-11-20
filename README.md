# LANOT_procesamiento_polar

**Orquestación de contenedores Apptainer para el procesamiento operativo de los satélites polares que recibe el LANOT: la serie JPSS (NOAA-20, NOAA-21 y, hasta noviembre de 2026, Suomi-NPP) y METOP-B/C.**

![Estado](https://img.shields.io/badge/Estado-Operativo-green) ![Licencia](https://img.shields.io/badge/Licencia-GPLv3-blue) ![Institución](https://img.shields.io/badge/LANOT-UNAM-gold)

---

## 📋 Descripción del Proyecto

Este repositorio contiene la "Infraestructura como Código" (IaC) de la cadena de procesamiento de imágenes satelitales polares del **Laboratorio Nacional de Observación de la Tierra (LANOT)**.

El objetivo es migrar de scripts monolíticos en servidor ("bare metal") a una arquitectura modular basada en contenedores **Apptainer** (anteriormente Singularity). Esto garantiza:
* **Reproducibilidad:** Entornos idénticos a los validados por SSEC/Wisconsin.
* **Soporte Moderno:** Capacidad para procesar NOAA-21 (JPSS-2).
* **Aislamiento:** Eliminación de conflictos de bibliotecas entre cadenas de procesamiento antiguas y nuevas.

**No contiene software científico ni datos**: solo recetas, scripts, plantillas XML y documentación. Los tarballs oficiales de CIMSS/SSEC están listados en el manifiesto `contenedores/tarballs.tsv`.

### 🛰️ Satélites Soportados
* **Suomi-NPP** (hasta su último crudo, el 2026-11-02)
* **NOAA-20 (JPSS-1)**
* **NOAA-21 (JPSS-2)**
* **METOP-B y METOP-C** (desde el 2026-11-19)

---

## 🏗️ Arquitectura del Flujo: JPSS

`recibe.sh` recibe el RAW de la antena y enruta; `procesar_pasada.sh` encadena los doce eslabones de una pasada, con barreras entre niveles y hasta tres etapas simultáneas; `barrer_pendientes.sh` va en cron y recoge lo que se quedó atrás.

```mermaid
%%{init: {"theme": "base", "flowchart": {"curve": "basis", "nodeSpacing": 18, "rankSpacing": 30, "padding": 12}, "themeVariables": {"primaryColor": "#f6f8fa", "primaryBorderColor": "#bbbbbb", "primaryTextColor": "#222222", "lineColor": "#888888", "clusterBkg": "#fbfbf6", "clusterBorder": "#d8d4b0", "edgeLabelBackground": "#ffffff"}}}%%
flowchart TD
    A["Antena<br/>RAW"] --> R["recibe.sh<br/>cadenas.tsv"]
    R --> D["procesar_pasada.sh"]
    Z["barrer_pendientes.sh<br/>cron cada 15 min"] -.->|reintenta| D

    subgraph AP["Apptainer"]
        B["RT-STPS 7.0<br/>Level 0 / RDR"] --> C["CSPP SDR 4.1.1<br/>Level 1"]
        C -->|VIIRS| V["ATMOS · ACSPO<br/>Active Fire · Flood"]
        V -->|ATMOS primero| L["LSR · CRYO"]
        C -->|ATMS| MI["MiRS 4.0<br/>lluvia · agua precipitable"]
        C -->|CrIS + ATMS| N["HEAP 3.0<br/>sondeos NUCAPS"]
        C -->|OMPS NM + NP| O["OMPS L2<br/>ozono total"]
        C -->|Level 1| P["Polar2Grid 3.2<br/>GeoTIFF"]
        V --> P
        L -->|LSR| P
        MI --> P
        N -->|mapas| P
        N -->|perfiles| K["skewt + MetaGráfica<br/>Skew-T"]
        P --> M["LANOT_tools<br/>vistas JPG"]
        O -->|omps_a_geotiff.py| M
    end

    D --> B

    classDef l2 fill:#e8f0fe,stroke:#4a7fd4
    classDef aux fill:#ffffff,stroke:#bbbbbb,stroke-dasharray:4 3,color:#666666
    class V,L,MI,N,O l2
    class Z aux
```

**Las ramas de Level 2 no comen todas de lo mismo.** CSPP SDR produce cuatro flujos de sensor y
cada rama se alimenta de unos y no de otros:

* **VIIRS** → ATMOS, ACSPO, Active Fire, Flood, LSR, CRYO y los renderizados de Level 1.
* **ATMS** → CSPP MiRS v4.0: lluvia, agua precipitable y temperaturas de brillo con corrección
  de limbo, en los tres satélites.
* **CrIS + ATMS** → los sondeos hiperespectrales de **NUCAPS**, hoy en CSPP HEAP v3.0. Es la
  única rama que consume **dos** sensores a la vez, y por eso el emparejamiento va por traslape
  de intervalos con margen (`HEAP_MARGEN_ATMS`) y no por clave de pasada. NUCAPS **no** sale de
  VIIRS ni lo cubre ATMOS.
* **OMPS** → ozono, con sus dos instrumentos —Nadir Mapper y Nadir Profiler— procesados en
  llamadas separadas de `run_sdr.sh`.

Casi todo Level 2 se renderiza con Polar2Grid —una sola vez por lector y rejilla, a GeoTIFF
float32— y las vistas las viste LANOT_tools. Las excepciones: el ozono total, que Polar2Grid no lee
hasta la 3.3 y convierte `scripts/omps_a_geotiff.py`; las inundaciones, cuyo GeoTIFF sale del
convertidor del propio bundle de CSPP; los Skew-T de los sitios de radiosondeo, que dibuja `skewt`
con MetaGráfica a partir de los perfiles de NUCAPS, y CRYO, que se queda sin renderizar porque no
tiene lector.

**La órbita no es común entre instrumentos**: el mismo sobrevuelo es `b45236` en VIIRS y `b45237`
en OMPS. Sirve como clave dentro de un instrumento, nunca para cruzar de uno a otro — para eso,
tiempo.

`geotiff/` son datos (float32) y `vistas/` son JPG decorados con logo y sello de tiempo: no se mezclan.

---

## 🛰️ Arquitectura del Flujo: METOP-B/C

Comparte con JPSS la recepción, `cadenas.tsv`, el barrido, HEAP, MiRS y la imagen de Polar2Grid,
pero no la cadena: `recibe.sh` manda los crudos de la rama `metop` a `procesar_metop.sh`, que
encadena cuatro eslabones en serie sobre una pasada.

```mermaid
%%{init: {"theme": "base", "flowchart": {"curve": "basis", "nodeSpacing": 18, "rankSpacing": 30, "padding": 12, "subGraphTitleMargin": {"top": 4, "bottom": 14}}, "themeVariables": {"primaryColor": "#f6f8fa", "primaryBorderColor": "#bbbbbb", "primaryTextColor": "#222222", "lineColor": "#888888", "clusterBkg": "#fbfbf6", "clusterBorder": "#d8d4b0", "edgeLabelBackground": "#ffffff"}}}%%
flowchart TD
    A["Antena<br/>RAW"] --> R["recibe.sh<br/>cadenas.tsv"]
    R --> D["procesar_metop.sh"]
    Z["barrer_pendientes.sh<br/>cron cada 15 min"] -.->|reintenta| D

    subgraph AP["Apptainer"]
        B["metopizer 3.57<br/>Level 0"] --> C["AAPP 8.15 + OPS-LRS<br/>Level 1"]
        C -->|AVHRR| P["Polar2Grid 3.2<br/>GeoTIFF"]
        C -->|AMSU-A + MHS| MI["MiRS 4.0<br/>lluvia · agua precipitable"]
        C -->|IASI + AMSU-A + MHS| N["HEAP 3.0<br/>sondeos NUCAPS"]
        MI --> P
        P --> M["LANOT_tools<br/>vistas JPG"]
    end

    D --> B

    classDef l2 fill:#e8f0fe,stroke:#4a7fd4
    classDef aux fill:#ffffff,stroke:#bbbbbb,stroke-dasharray:4 3,color:#666666
    class MI,N l2
    class Z aux
```

**Lo que cambia respecto a JPSS:**

* **La unidad de trabajo es el crudo**, no la pasada de SDR: cada recepción de la antena da un
  Level 1 por instrumento, y `run_metop_l1.sh` deja un manifiesto (`<crudo>.l1`) del que los
  demás eslabones toman sus entradas. No hay nada que emparejar por tiempo.
* **El Level 1 lo hace AAPP**, de NWP SAF, en un solo contenedor (`aapp_v8.15.sif`) con el
  metopizer de EUMETSAT y OPS-LRS para IASI. Sus coeficientes de calibración viven en el host
  y `update_aapp_ancillary.sh` los trae al día cada semana.
* **Los mismos paquetes, otros sensores**: HEAP saca los sondeos de IASI + AMSU-A + MHS en vez de
  CrIS + ATMS, y MiRS la lluvia y el agua precipitable de AMSU-A + MHS en vez de ATMS. MiRS no lee
  los 1b de AAPP tal cual: `metop_l1b_para_mirs.py` le prepara una copia con la cabecera que espera.
* **Los sondeos todavía no tienen mapas ni Skew-T**, a diferencia de los de JPSS.

Todo va a su propio árbol, `/data/output/metop/{level1,level2,geotiff,vistas}`, y se publica
en `polar/metop` (kawak) y `/dataservice/metop`, al lado de los `noaa-metop` de la cadena
anterior, que sigue corriendo mientras se comparan. El plan y su estado están en
[`docs/plan_metop.md`](docs/plan_metop.md).

---

## 🚀 Requisitos Previos

Para desplegar este sistema en un servidor nuevo, se requiere:

*   **Sistema Operativo:** Rocky Linux 8/9 o RHEL compatible.
*   **Motor de Contenedores:** `Apptainer` instalado (`dnf install apptainer`).
*   **Credenciales:** registro en el sitio de descargas de CIMSS/SSEC y, para la rama METOP, en el área de usuario de NWP SAF (AAPP, OPS-LRS) y en el User Portal de EUMETSAT (metopizer).

---

## 🛠️ Puesta en marcha

### 1. Clonar y ver qué falta

```bash
git clone https://github.com/LANOT-UNAM/LANOT_procesamiento_polar.git
cd LANOT_procesamiento_polar

./contenedores/obtener_tarballs.sh              # qué falta, qué sobra, qué no cuadra
./contenedores/obtener_tarballs.sh --descargar  # qué bajar y de dónde
```

La descarga es manual: el script dice exactamente qué archivos faltan, de qué sitio salen y dónde dejarlos. `--verificar` confirma después que llegaron completos.

### 2. Compilar las imágenes

Hay **orden de compilación**: todas las recetas parten de una imagen base común. `construir.sh` lo resuelve.

```bash
./contenedores/construir.sh                    # lista lo disponible
./contenedores/construir.sh cspp_sdr_v4.1.1    # compila esa receta y su base

# El destino de los .sif se elige con DESTINO; los scripts los buscan en /opt/containers
DESTINO=/opt/containers ./contenedores/construir.sh polar2grid_v3.2-mapdrawer
```

### 3. Preparar el servidor (una vez)

```bash
./scripts/preparar_servidor.sh --verificar   # audita sin tocar nada
sudo ./scripts/preparar_servidor.sh          # directorios, estáticos, XML, leapsec, cachés
```

Los tarballs de datos estáticos se borran después de extraerlos y comprobar que el destino quedó poblado: son decenas de GB que duplicarían lo que ya vive en `/data/opt`. Los bundles de software sí se conservan, porque son la entrada de `apptainer build`.

### 4. Instalar el código de operación (en cada despliegue)

```bash
sudo ./scripts/instalar.sh    # copia a /opt/lanot/polares
```

En operación la cadena se ejecuta como `lanotadm` desde `/opt/lanot/polares/scripts/`, **no** desde el clon: así un `git pull` o una edición en el servidor no cambian lo que corre el cron. `VERSION` anota de qué commit salió. Si hay una pasada en curso, `instalar.sh` espera a que termine (hasta 45 min, `INSTALAR_ESPERA`), para que ninguna quede hecha con dos versiones.

La recepción invoca `/opt/lanot/polares/scripts/recibe.sh <crudo>` directamente por `ssh`. **Sin enlace en `~lanotadm/bin`**: ahí vive el `recibe.sh` de la cadena vieja.

### 5. Comprobar que hay versión nueva de algún paquete

CSPP no tiene lista de correo ni RSS, así que nadie avisa. La portada sí es pública:

```bash
./contenedores/obtener_tarballs.sh --novedades   # va bien en un cron mensual
```

---

## ⚙️ Mantenimiento Operativo

### Datos ancilares dinámicos
Cada software tiene **su propio caché** bajo `/data/ancillary`, y no se comparten: el podador de ATMOS borra por directorio y se llevaría el de SDR entero. Los refrescan dos tareas de cron, `update_sdr_daily.sh` y `update_atmos_ancillary.sh`.

### Leap seconds
`/data/ancillary/common/leapsec.dat` sale del contenedor de RT-STPS, que es la única fuente con el formato correcto garantizado, y lo refresca `update_sdr_daily.sh`. **Nunca se sustituye por uno improvisado**: un leapsec inventado no falla, fecha mal los datos en silencio.

---

## 🤝 Contribución

Este es un proyecto interno del LANOT. Se trabaja **directo sobre `main`**, sin ramas ni Pull Requests: `tahan` es servidor de desarrollo y no el que está conectado a la antena. El ciclo es editar, `git push`, `git pull` en tahan, `instalar.sh` y correr.

---

## 📜 Licencia y Créditos
*   **Código de Orquestación:** Distribuido bajo licencia GNU GPLv3.
*   **Software Base:**
    *   CSPP (SDR, ATMOS, LSR, CRYO, ACSPO, Active Fire, Flood, OMPS) y Polar2Grid: University of Wisconsin-Madison (SSEC/CIMSS).
    *   RT-STPS: NASA Direct Readout Laboratory (DRL); lo distribuye y parchea CSPP (SSEC/CIMSS), porque el DRL está congelado.

---
*Laboratorio Nacional de Observación de la Tierra (LANOT) - UNAM, 2026.*
