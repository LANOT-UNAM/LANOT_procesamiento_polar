# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repositorio

Infraestructura como código para la cadena operativa de satélites polares JPSS (Suomi-NPP, NOAA-20, NOAA-21) del LANOT-UNAM. **No contiene software científico ni datos**: solo recetas Apptainer (`contenedores/*.def`), scripts de orquestación en Bash (`scripts/`), plantillas XML de RT-STPS (`config/`) y documentación (`docs/`).

No hay build, tests ni linter. El "producto" son imágenes `.sif` que se compilan a partir de tarballs oficiales de CIMSS/SSEC y NASA DRL que **no están versionados** (`.gitignore` excluye `*.tar.gz`, `*.sif`, `*.h5`, `*.nc`, `*.tif`, `*.log`). El sistema real corre en el servidor `tahan`; en esta máquina de desarrollo las rutas `/opt/containers`, `/data/...` y `/var/log/lanot/...` normalmente no existen, así que los scripts no se pueden ejecutar de verdad — se editan y se validan con `bash -n`.

Todo (comentarios, mensajes de log, documentación) está en español. Mantener ese idioma.

## Comandos

```bash
# Compilar un contenedor. Las recetas parten de una imagen base común, así que
# hay un orden; construir.sh lo resuelve y compila donde están los tarballs
# (TARBALLS, por omisión /opt/contenedores)
./contenedores/construir.sh                    # lista lo disponible
./contenedores/construir.sh cspp_sdr_v4.1.1    # compila esa receta y su base

# A mano, si hace falta: primero la base de la serie, luego la receta
cd /opt/contenedores/
sudo apptainer build lanot_base_rocky8.sif ~/…/contenedores/lanot_base_rocky8.def
sudo apptainer build cspp_sdr_v4.1.1.sif   ~/…/contenedores/cspp_sdr_v4.1.1.def

# Sanity check de una imagen ya compilada
apptainer exec rt_stps_7.0.sif ./bin/batch.sh --help
apptainer exec cspp_sdr_v4.1.1.sif viirs_sdr.sh --help
apptainer exec polar2grid_v3.2-mapdrawer.sif polar2grid.sh -h
apptainer test polar2grid_v3.2-mapdrawer.sif          # verifica P2G + LANOT_tools

# Verificar sintaxis de un script sin ejecutarlo (útil en desarrollo)
bash -n scripts/run_sdr.sh

# Regenerar config/jpss1.xml (escribe rutas relativas: ejecutar desde la raíz del repo)
python3 scripts/generar_xml.py

# Preparar el ambiente en un servidor nuevo (crea /data/..., /var/log/lanot/..., extrae XMLs)
sudo ./scripts/setup_ambiente_rt_stps.sh
```

**Estado y pendientes**: `docs/estado_y_pendientes.md` es el documento vivo — qué eslabón se ha probado con datos reales, qué falta y qué preguntas siguen abiertas. Los otros dos documentos de `docs/` describen la primera fase de la migración y ya no reflejan cómo corre la cadena.

## Arquitectura

### Cadena de procesamiento

```
RAW (CCSDS de antena)
  └─ rt_stps_7.0.sif ────────────────► Level 0 / RDR (.h5)
       └─ cspp_sdr_v4.1.1.sif ───────► Level 1 / SDR (SV*, GMTCO*, SATMS*, SCRIS*, SOMTC* .h5)
            ├─ polar2grid_v3.2-mapdrawer.sif ► geotiff/{m_bands,i_bands,dnb,rgb} + vistas/{dnb,rgb}
            ├─ cspp_omps_l2_v1.0.sif ────► Level 2 omps (V8TOZ-EDR*, V8PRO-EDR* .nc)
            ├─ cspp_atmos_edr_v1.0.sif ──► Level 2 atmosphere (JRR-*.nc)
            ├─ cspp_lsr_v2.0.sif ────────► Level 2 lsr (SurfRefl_*.nc)  [requiere ATMOS]
            ├─ cspp_cryo_edr_v1.0.sif ───► Level 2 cryosphere           [requiere ATMOS]
            ├─ cspp_acspo_v3.0.sif ──────► Level 2 acspo (SST)
            └─ cspp_active_fire_v2.1.sif ► Level 2 fires (AFIMG_*.nc)
                 └─ polar2grid_v3.2-mapdrawer.sif ► geotiff/{atmos,lsr,acspo} + vistas/…
```

`run_polar2grid_edr.sh` es el **renderizador único de Level 2**: ningún `run_*_edr.sh` debe llamar a Polar2Grid por su cuenta. Los scripts de EDR producen `.nc` y nada más; ahí están las rejillas, las paletas y la separación `geotiff/` ÷ `vistas/`.

`cryo` y `lsr` consumen tanto SDR como los productos ATMOS, así que **ATMOS debe correr antes** que ellos. NUCAPS/CLAVR-x/ASCI se descartaron: el nuevo CSPP ATMOS ya genera esos productos (ver `notas.txt`).

### Dos generaciones de scripts — importante

- **`scripts/run_*.sh`** (RT-STPS, SDR, cada EDR, Polar2Grid): la generación **actual y funcional**. Un script por etapa, cada uno se invoca a mano o vía Slurm. Escriben en `/data/output/jpss/{level0,level1,level2,geotiff,vistas}`, con lo intermedio en `/data/tmp`. `geotiff/` son datos (float32) y `vistas/` son JPG decorados: no mezclarlos.
- **`scripts/procesar_cadena_completa.sh` + `scripts/recibe.sh`**: orquestador monolítico de la primera fase de migración. **No está en uso, pero se conserva a propósito**: es la plantilla para reunificar los eslabones en una sola cadena cuando todos los `run_*.sh` corran de forma confiable. Mientras tanto está desactualizado — apunta a `cspp_sdr_v4.1.sif`, `polar2grid_v3.1.sif` y a un `cspp_nucaps_v1.0.sif` que nunca existió, y usa el árbol de rutas viejo `/data/products/{level0,level1,level2,geotiff}`. No borrarlo ni "arreglarlo" por cuenta propia. Los documentos en `docs/` describen esta generación, no la actual.
- **`referencia/`**: código que **no se ejecuta desde este repositorio**, solo se consulta (ver `referencia/README.md`). Los dos que importan corren **hoy en producción** en el servidor viejo: `cspp.sh` (orquestador RAW → Level 1 de los cuatro sensores, que dispara el resto por `ssh`) y `cspp_1_ptog.sh` (Level 1 → GeoTIFF, vistas DNB y RGB). De ahí salen las rejillas propias, ahora versionadas en `config/grid.yaml` (`wgs84_geo_750m` para bandas M, DNB y RGB; `wgs84_geo_375m` para bandas I), que hay que pasarle a Polar2Grid con `--grid-configs` porque el contenedor trae el de fábrica, sin ellas. `scripts/run_polar2grid_l1.sh` sustituye a `cspp_1_ptog.sh`; lo que sigue sin cubrirse de `cspp.sh` es **OMPS**. No copiar su manejo de estado: escribe el marcador *antes* de procesar (`cspp.sh:79`), así que un fallo a media pasada la da por hecha para siempre.

Al tocar rutas o versiones de contenedor, confirmar en qué generación se está trabajando; los dos árboles de directorios (`/data/products/*` vs `/data/output/jpss/*`) coexisten en el repo por esta razón.

### Contrato host ↔ contenedor

Los `.def` instalan **solo binarios**. Todo lo que cambia con el tiempo o pesa mucho vive en el host y se monta con `--bind`:

- **Estático por software**: `/data/opt/SDR_4_1/{anc,<sensor>/luts}`, `/data/opt/CSPP_ATMOS_1_0/anc/static`, `/data/opt/RT-STPS/rt-stps/config` → se montan sobre la ruta interna equivalente (`/opt/SDR_4_1/...`, etc.). Se despliegan una vez con `scripts/deploy_static_data_sdr.sh`.
- **Dinámico**: `/data/ancillary` (LUTs de calibración, TLE, GFS, `common/leapsec.dat`) → refrescado por `scripts/update_sdr_daily.sh` (cron diario, ejecuta `sdr_luts.sh` y `sdr_ancillary.sh` dentro del SIF).
- **Datos**: entradas y salidas se montan en puntos genéricos (`/input`, `/input_sdr`, `/output`, `/output_data`, `/work`) para que el script del contenedor no vea rutas del host.

Cada `run_*.sh` sigue el mismo patrón: `apptainer exec` con los binds, y dentro un `/bin/bash -c` que exporta `CSPP_*_HOME`, `HDF5_USE_FILE_LOCKING=FALSE` y `LC_ALL=C`, hace `source <cspp_env.sh>` y luego invoca el ejecutable. Varios ejecutables CSPP escriben en el `pwd`, por eso los scripts usan `cd /output` o `--pwd /output_data`.

**Imagen base común**: todas las recetas parten de `lanot_base_rocky8.sif` o `lanot_base_rocky9.sif` (`Bootstrap: localimage`), que concentran las decisiones que antes estaban repetidas: registro (Quay, porque las imágenes de Docker Hub están congeladas en 9.3 y 8.9), versión menor fijada, repositorios EPEL/CRB/PowerTools y las utilidades comunes. Cada receta instala solo lo suyo (perl, Java, GDAL, mesa-libGL). Consecuencia: **hay orden de compilación** — la base antes que el resto, y el `.sif` de la base debe estar en el directorio desde donde se ejecuta `apptainer build`. Eso es lo que resuelve `contenedores/construir.sh`.

Cada `.def` crea un symlink genérico (`/opt/cspp_sdr` → `SDR_4_1`, `/opt/polar2grid` → `polar2grid_v_3_2`, …) para que los scripts no dependan del nombre exacto de la carpeta que produce el tarball.

`polar2grid_v3.2-mapdrawer.def` es especial: además de Polar2Grid clona `github.com/asierra/LANOT_tools` (mapdrawer/geotiff2view, para logos y timestamps sobre las imágenes) y copia `/usr/local/share/lanot/{colortables,gpkg,logos,docs}` **desde el host de compilación**, así que solo se puede construir en una máquina que ya tenga esos recursos instalados.

### Convenciones específicas del dominio

- **Detección de satélite** por nombre de archivo RAW (`recibe.sh`, `run_rt_stps.sh`): `chain2`/`npp` → NPP/`npp.xml`; `chain6`/`j01`/`noaa20` → NOAA-20/`jpss1.xml`; `j02`/`noaa21` → NOAA-21/`jpss2.xml`. `chain4`/`chain5` son satélites legacy (NOAA-15/18/19, METOP) que se enrutan fuera de esta cadena.
- **Detección de sensor** por nombre del RDR (`run_sdr.sh`): `RVIIRS`/`RVIRS`→`viirs_sdr.sh`, `RATMS`→`atms_sdr.sh`, `RCRIS`→`cris_sdr.sh`, `ROTCS`/`RONPS`→`omps_sdr.sh`. `detectar_sensor` devuelve **clave y sensor por separado**: la clave es lo que se pide con `--sensor` y el sensor determina las rutas (LUTs y salida). Solo difieren en OMPS, que son dos instrumentos —Nadir Mapper (`ROTCS`) y Nadir Profiler (`RONPS`)— con LUTs y directorio compartidos pero que el manual exige procesar en llamadas separadas: de ahí `--sensor omps_nm` y `--sensor omps_np`. Con una sola clave, la autoselección tomaría el más reciente de los dos y se detendría en su marcador sin procesar nunca el otro. `RNSCA` **no** identifica sensor: es el spacecraft diary que RT-STPS adjunta a los tres (`RNSCA-RVIRS`, `RATMS-RNSCA`, `RCRIS-RNSCA`). Las banderas tampoco son comunes: `adl_atms_sdr.py` no acepta `-g`, solo VIIRS lo entiende, así que cada sensor trae las suyas (override: `SDR_OPTS`).
- **Contexto entre gránulos (manual CSPP SDR 4.1.1 §2.2.2)**: para calibrar un gránulo hacen falta sus vecinos — VIIRS ±1, ATMS ±1, **CrIS ±4** (9 RDR contiguos). Un gránulo truncado, que el filtro de tamaño descarta, deja sin calibrar a todos los que lo tienen en su ventana, así que las pasadas con dropout salen con huecos y **eso es normal** — se ven como costuras negras horizontales en la vista. `-a` no viene al caso: `cris_sdr.sh`/`atms_sdr.sh` declaran `AGGREGATE_OPT` pero nunca lo usan —reenvían `"$@"` al driver de Python, donde `aggregate` ya es `True`—, así que para esos dos sensores es un no-op (A/B verificado en tahan el 2026-08-13: mismos `SCRIF`/`GCRSO` con y sin la bandera).
- **El directorio de trabajo debe estar limpio** (manual CSPP SDR 4.1.1 §§4.1, 5.1, 6.1: *"All files should be removed from the work directory before each execution"*). Los drivers agregan **todo lo que encuentran** en el `pwd`, así que si ahí quedaron los productos de la pasada anterior, `nagg` intenta cubrir el hueco entre ambas series, falla con `no more fill granule available` y la limpieza final se lleva las dos: el directorio queda **vacío** pese a un log lleno de `Completed without problems`. Verificado en tahan el 2026-08-13. Por eso `run_sdr.sh` corre en un directorio de trabajo propio y mueve los productos a `level1/<sensor>` al terminar, en vez de usar la salida como `pwd`. Los agregados le sirven igual a CSPP HEAP v3.0 —el sucesor de NUCAPS, que necesita CrIS **y** ATMS (`SCRIF*`/`GCRSO*` y `TATMS*`/`GATMO*`)— porque desagrega la entrada antes de procesar.
- **Caché de ancillary dinámico, uno por software**: no compartir `/data/ancillary` entre productos. CSPP SDR usa subdirectorios por día (`2026_01_02_002/`); CSPP ATMOS guarda sus ~6 GB diarios sueltos en la raíz de su caché (`/data/ancillary/atmos`) y los poda con `delete_old_anc.sh`, que borra todo lo que pase de 14 días **en el directorio que se le indique** — apuntarlo al caché de SDR se lo llevaría entero. Cada driver descarga lo suyo al arrancar salvo que se le pase la bandera de "solo local" (`-l` en `viirs_atmos.sh`), en cuyo caso hay que precargar por cron.
- **Reprocesar duplica productos, y eso rompe LSR**: los `JRR-*` llevan un campo de creación en el nombre (`_c202608122142453`), así que volver a correr ATMOS sobre la misma pasada no sobrescribe: agrega. LSR deduce **cuántos gránulos hay contando los `JRR-AOD`** (`libexec/scripts/cspp_viirs_surface_reflectance.py:313`) y luego exige esa misma cantidad de cada producto; con duplicados la cuenta se infla y falla con un mensaje que culpa a los `NWP_GFS-INTP`, que son los únicos que no se duplican porque su nombre no lleva ese campo. Por eso el staging enlaza solo la versión más reciente de cada producto por gránulo.
- **Polar2Grid remuestrea una vez; lo visual sale de LANOT_tools.** El remuestreo swath → rejilla es la parte cara, así que se llama a `polar2grid.sh` **una vez por (lector, rejilla, conjunto de bandas)** y lo que entrega es GeoTIFF de datos (`--dtype float32 --no-enhance`). Las vistas se derivan de esos GeoTIFF, eligiendo herramienta según lo que P2G haya dejado: `geotiff2view` si es dato sin paleta (recolorea con un CPT y decora), `mapdrawer` si ya es imagen —los RGB, o los que traen `colormap` embebido— porque entonces solo hay que vestirlo. Excepción deliberada: los RGB `true_color`/`false_color` se siguen componiendo en Satpy, que aplica corrección de Rayleigh y afilado por razón con I01; `geotiff2view` sabe apilar tres GeoTIFF pero solo recorta y escala. Los algoritmos DNB (`adaptive`, `dynamic`, `hncc`, `histogram`) **son productos, no realces**: el float32 ya trae el algoritmo aplicado, así que no hay que remuestrearlos otra vez para tener la vista — que es lo que hace de más `referencia/cspp_1_ptog.sh` con sus cinco llamadas.
- **Vista solo para lo que se mira.** Los `run_polar2grid_*.sh` generan GeoTIFF de todo, pero JPG solo de lo que alguien va a ver: RGB (`true_color`, `false_color` y los de superficie), los cuatro algoritmos DNB, los productos geofísicos de ATMOS, la SST y —cuando tengan CPT— NDVI y EVI. **No** llevan vista las bandas M/I con sus ángulos y radiancias, los `surf_refl_*` ni los ángulos del DNB: son datos por banda, y decorarlos con logo y timestamp solo llena `vistas/` de imágenes que nadie abre. El recorte se hace con el filtro (ERE) que aceptan `vestir()` y `ordenes_de()`.
- **Todo lo intermedio vive en `/data/tmp`**, nunca bajo `/data/output/jpss/`, que es árbol de productos reales. Es la raíz por omisión de `*_WORK_BASE` en los ocho `run_*.sh`: staging de entrada, directorio de trabajo de CSPP y cualquier temporal. Se conserva cuando la etapa falla (para depurar) y se borra cuando termina bien.
- **Staging por enlaces simbólicos**: los EDR esperan un solo directorio de entrada, así que los scripts crean `/data/tmp/<algo>_staging_$JOB_ID` con symlinks a SDR (+ ATMOS cuando aplica) y lo borran al final.
- **Nombres para Satpy: `_cspp_dev` NO se quita.** El patrón del lector `viirs_sdr` termina en `_{source:8s}.h5`, un campo obligatorio de 8 caracteres que es justamente `cspp_dev`; quitarlo hace que el lector rechace todo con `No filenames found for reader: viirs_sdr` (verificado en tahan el 2026-08-13: los 28 SDR de la pasada, y los cuatro renderizados de Level 1 muertos con código 255). La creencia contraria venía de `referencia/test_render_fires.sh`, que es de Active Fire —otro lector, otro patrón— y que además pasa `j01` → `J01`. Cuando se implemente el renderizado de incendios, verificar ese caso por separado en vez de darlo por bueno.
- **XML de RT-STPS**: `run_rt_stps.sh` copia el XML del satélite a un temporal y reescribe con `sed` `<dest>`, `<outputPath>` y `<directory>` a `/output`, porque los XML traen rutas absolutas del host. `generar_xml.py` genera `jpss1.xml` desde tablas de APID/VCID por sensor.
- **Logs**: siempre `/var/log/lanot/polares/<etapa>/` (`rt-stps`, `cspp-sdr`, `cspp-edr`, `polar2grid`, `orquestador`), con nombre `YYYYMMDD_HHMMSS_*.log` que incluye el basename de la entrada.
- **Estado ("ya procesado")**: marcador `<archivo_de_entrada>.done` en `/data/output/jpss/state/<etapa>/`, escrito **solo** si la etapa terminó con éxito, para que un fallo se reintente solo. Cuidado: el código de salida no basta como criterio de éxito — RT-STPS termina en 0 con un RAW corrupto sin decodificar nada (verificado en tahan), así que hay que exigir además que la etapa haya producido archivos, contados contra una marca de tiempo del inicio de la corrida y no contra el mtime de la entrada. Implementado en **todos** los `run_*.sh`, con la misma forma: autoselección de la entrada más reciente, `--force`, `--help`, validación del ambiente después de decidir si hay trabajo, conteo de productos contra una marca de tiempo del inicio, duración en el resumen y overrides por variables de entorno (`RTSTPS_*`, `SDR_*`, `ATMOS_*`, `LSR_*`, `CRYO_*`, `ACSPO_*`, `FIRE_*`, `P2G_*`) para poder probar el flujo completo con un `apptainer` simulado, sin tocar `/data`.
- **Unidad de trabajo, según la etapa**: `run_rt_stps.sh` marca por archivo RAW y `run_sdr.sh` por RDR, pero de Level 2 en adelante la entrada es un directorio, así que la unidad es la **pasada**, identificada por satélite, fecha y órbita (`j01_d20260811_b45236`) tomados del nombre de los SDR. Cada script enlaza en un staging solo los archivos de esa pasada, porque los drivers de CSPP procesan todo lo que encuentren en el directorio que se les da. Los productos de Level 2 (`JRR-*`, `SurfRefl_*`) no llevan órbita en el nombre: se emparejan por el sello temporal del gránulo, que concatena fecha y hora de inicio (`GMTCO ... d20260811_t1947330` → `JRR ... s202608111947330`). No usar la existencia del log como estado: el log también queda cuando el proceso falla y logrotate lo borra a los 30 días.
- **Slurm**: los scripts de Level 2 más nuevos (`run_acspo_edr.sh`, `run_active_fire_edr.sh`, `run_cryo_edr.sh`, `run_lsr_edr.sh`) traen cabecera `#SBATCH` y usan `${SLURM_CPUS_PER_TASK:-N}` / `${SLURM_JOB_ID:-$$}` para funcionar igual con o sin Slurm. Los más antiguos no. El clúster con Slurm todavía no está en producción.
- **Manejo de errores**: bajo `set -euo pipefail` (`run_rt_stps.sh`, `procesar_cadena_completa.sh`) un `EXIT_CODE=$?` después de un `apptainer exec` es código muerto: el script ya abortó y nunca se imprime el mensaje que apunta al log. Hay que usar `... || EXIT_CODE=$?`, como en `run_rt_stps.sh`. `procesar_cadena_completa.sh` todavía tiene ese patrón roto en sus cuatro pasos. Los `run_*.sh` de EDR no usan `set -e` y sí revisan `$?` de verdad.

## Flujo de trabajo

`main` es la rama operativa conectada a la antena. Según el README: no hacer commits directos a `main`, trabajar en rama y abrir PR.
