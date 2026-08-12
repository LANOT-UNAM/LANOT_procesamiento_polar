# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repositorio

Infraestructura como código para la cadena operativa de satélites polares JPSS (Suomi-NPP, NOAA-20, NOAA-21) del LANOT-UNAM. **No contiene software científico ni datos**: solo recetas Apptainer (`contenedores/*.def`), scripts de orquestación en Bash (`scripts/`), plantillas XML de RT-STPS (`config/`) y documentación (`docs/`).

No hay build, tests ni linter. El "producto" son imágenes `.sif` que se compilan a partir de tarballs oficiales de CIMSS/SSEC y NASA DRL que **no están versionados** (`.gitignore` excluye `*.tar.gz`, `*.sif`, `*.h5`, `*.nc`, `*.tif`, `*.log`). El sistema real corre en el servidor `tahan`; en esta máquina de desarrollo las rutas `/opt/containers`, `/data/...` y `/var/log/lanot/...` normalmente no existen, así que los scripts no se pueden ejecutar de verdad — se editan y se validan con `bash -n`.

Todo (comentarios, mensajes de log, documentación) está en español. Mantener ese idioma.

## Comandos

```bash
# Compilar un contenedor (el tarball correspondiente debe estar en contenedores/)
cd contenedores/
sudo apptainer build cspp_sdr_v4.1.1.sif cspp_sdr_v4.1.1.def

# Sanity check de una imagen ya compilada
apptainer exec rt_stps_7.0.sif ./bin/batch.sh --help
apptainer exec cspp_sdr_v4.1.1.sif viirs_sdr.sh --help
apptainer exec polar2grid_v3.2.sif polar2grid.sh --list-readers

# Verificar sintaxis de un script sin ejecutarlo (útil en desarrollo)
bash -n scripts/run_sdr.sh

# Regenerar config/jpss1.xml (escribe rutas relativas: ejecutar desde la raíz del repo)
python3 scripts/generar_xml.py

# Preparar el ambiente en un servidor nuevo (crea /data/..., /var/log/lanot/..., extrae XMLs)
sudo ./scripts/setup_ambiente_rt_stps.sh
```

## Arquitectura

### Cadena de procesamiento

```
RAW (CCSDS de antena)
  └─ rt_stps_7.0.sif ────────────────► Level 0 / RDR (.h5)
       └─ cspp_sdr_v4.1.1.sif ───────► Level 1 / SDR (SV*, GMTCO*, SATMS*, SCRIS* .h5)
            ├─ cspp_atmos_edr_v1.0.sif ──► Level 2 atmosphere (JRR-*.nc)
            ├─ cspp_lsr_v2.0.sif ────────► Level 2 lsr (SurfRefl_*.nc)  [requiere ATMOS]
            ├─ cspp_cryo_edr_v1.0.sif ───► Level 2 cryosphere           [requiere ATMOS]
            ├─ cspp_acspo_v3.0.sif ──────► Level 2 acspo (SST)
            └─ cspp_active_fire_v2.1.sif ► Level 2 fires (AFIMG_*.nc)
                 └─ polar2grid_v3.2[-mapdrawer].sif ► GeoTIFF y "vistas"
```

`cryo` y `lsr` consumen tanto SDR como los productos ATMOS, así que **ATMOS debe correr antes** que ellos. NUCAPS/CLAVR-x/ASCI se descartaron: el nuevo CSPP ATMOS ya genera esos productos (ver `notas.txt`).

### Dos generaciones de scripts — importante

- **`scripts/run_*.sh`** (RT-STPS, SDR, cada EDR, Polar2Grid): la generación **actual y funcional**. Un script por etapa, cada uno se invoca a mano o vía Slurm. Escriben en `/data/output/jpss/{level0,level1,level2,vistas}`.
- **`scripts/procesar_cadena_completa.sh` + `scripts/recibe.sh`**: orquestador monolítico de la primera fase de migración. **No está en uso, pero se conserva a propósito**: es la plantilla para reunificar los eslabones en una sola cadena cuando todos los `run_*.sh` corran de forma confiable. Mientras tanto está desactualizado — apunta a `cspp_sdr_v4.1.sif`, `polar2grid_v3.1.sif` y a un `cspp_nucaps_v1.0.sif` que nunca existió, y usa el árbol de rutas viejo `/data/products/{level0,level1,level2,geotiff}`. No borrarlo ni "arreglarlo" por cuenta propia. Los documentos en `docs/` describen esta generación, no la actual.
- **`scripts/old_cspp_no_usar.sh`**: referencia histórica del sistema bare-metal. No usar.

Al tocar rutas o versiones de contenedor, confirmar en qué generación se está trabajando; los dos árboles de directorios (`/data/products/*` vs `/data/output/jpss/*`) coexisten en el repo por esta razón.

### Contrato host ↔ contenedor

Los `.def` instalan **solo binarios**. Todo lo que cambia con el tiempo o pesa mucho vive en el host y se monta con `--bind`:

- **Estático por software**: `/data/opt/SDR_4_1/{anc,<sensor>/luts}`, `/data/opt/CSPP_ATMOS_1_0/anc/static`, `/data/opt/RT-STPS/rt-stps/config` → se montan sobre la ruta interna equivalente (`/opt/SDR_4_1/...`, etc.). Se despliegan una vez con `scripts/deploy_static_data_sdr.sh`.
- **Dinámico**: `/data/ancillary` (LUTs de calibración, TLE, GFS, `common/leapsec.dat`) → refrescado por `scripts/update_sdr_daily.sh` (cron diario, ejecuta `sdr_luts.sh` y `sdr_ancillary.sh` dentro del SIF).
- **Datos**: entradas y salidas se montan en puntos genéricos (`/input`, `/input_sdr`, `/output`, `/output_data`, `/work`) para que el script del contenedor no vea rutas del host.

Cada `run_*.sh` sigue el mismo patrón: `apptainer exec` con los binds, y dentro un `/bin/bash -c` que exporta `CSPP_*_HOME`, `HDF5_USE_FILE_LOCKING=FALSE` y `LC_ALL=C`, hace `source <cspp_env.sh>` y luego invoca el ejecutable. Varios ejecutables CSPP escriben en el `pwd`, por eso los scripts usan `cd /output` o `--pwd /output_data`.

Cada `.def` crea un symlink genérico (`/opt/cspp_sdr` → `SDR_4_1`, `/opt/polar2grid` → `polar2grid_v_3_2`, …) para que los scripts no dependan del nombre exacto de la carpeta que produce el tarball.

`polar2grid_v3.2-mapdrawer.def` es especial: además de Polar2Grid clona `github.com/asierra/LANOT_tools` (mapdrawer/geotiff2view, para logos y timestamps sobre las imágenes) y copia `/usr/local/share/lanot/{colortables,gpkg,logos,docs}` **desde el host de compilación**, así que solo se puede construir en una máquina que ya tenga esos recursos instalados.

### Convenciones específicas del dominio

- **Detección de satélite** por nombre de archivo RAW (`recibe.sh`, `run_rt_stps.sh`): `chain2`/`npp` → NPP/`npp.xml`; `chain6`/`j01`/`noaa20` → NOAA-20/`jpss1.xml`; `j02`/`noaa21` → NOAA-21/`jpss2.xml`. `chain4`/`chain5` son satélites legacy (NOAA-15/18/19, METOP) que se enrutan fuera de esta cadena.
- **Detección de sensor** por nombre del RDR (`run_sdr.sh`): `RVIIRS`→`viirs_sdr.sh`, `RATMS`/`RNSCA`→`atms_sdr.sh`, `RCRIS`→`cris_sdr.sh`.
- **Caché de ancillary dinámico, uno por software**: no compartir `/data/ancillary` entre productos. CSPP SDR usa subdirectorios por día (`2026_01_02_002/`); CSPP ATMOS guarda sus ~6 GB diarios sueltos en la raíz de su caché (`/data/ancillary/atmos`) y los poda con `delete_old_anc.sh`, que borra todo lo que pase de 14 días **en el directorio que se le indique** — apuntarlo al caché de SDR se lo llevaría entero. Cada driver descarga lo suyo al arrancar salvo que se le pase la bandera de "solo local" (`-l` en `viirs_atmos.sh`), en cuyo caso hay que precargar por cron.
- **Staging por enlaces simbólicos**: los EDR esperan un solo directorio de entrada, así que los scripts crean `/data/output/jpss/tmp/<algo>_staging_$JOB_ID` con symlinks a SDR (+ ATMOS cuando aplica) y lo borran al final.
- **Normalización de nombres para Satpy**: Polar2Grid es sensible al patrón de los nombres. Hay que quitar el sufijo `_cspp_dev` de los `GMTCO*` y, para Active Fire, además pasar `j01` → `J01` (ver `run_polar2grid_edr.sh` y `test_render_fires.sh`).
- **XML de RT-STPS**: `run_rt_stps.sh` copia el XML del satélite a un temporal y reescribe con `sed` `<dest>`, `<outputPath>` y `<directory>` a `/output`, porque los XML traen rutas absolutas del host. `generar_xml.py` genera `jpss1.xml` desde tablas de APID/VCID por sensor.
- **Logs**: siempre `/var/log/lanot/polares/<etapa>/` (`rt-stps`, `cspp-sdr`, `cspp-edr`, `polar2grid`, `orquestador`), con nombre `YYYYMMDD_HHMMSS_*.log` que incluye el basename de la entrada.
- **Estado ("ya procesado")**: marcador `<archivo_de_entrada>.done` en `/data/output/jpss/state/<etapa>/`, escrito **solo** si la etapa terminó con éxito, para que un fallo se reintente solo. Cuidado: el código de salida no basta como criterio de éxito — RT-STPS termina en 0 con un RAW corrupto sin decodificar nada (verificado en tahan), así que hay que exigir además que la etapa haya producido archivos, contados contra una marca de tiempo del inicio de la corrida y no contra el mtime de la entrada. Implementado en **todos** los `run_*.sh`, con la misma forma: autoselección de la entrada más reciente, `--force`, `--help`, validación del ambiente después de decidir si hay trabajo, conteo de productos contra una marca de tiempo del inicio, duración en el resumen y overrides por variables de entorno (`RTSTPS_*`, `SDR_*`, `ATMOS_*`, `LSR_*`, `CRYO_*`, `ACSPO_*`, `FIRE_*`, `P2G_*`) para poder probar el flujo completo con un `apptainer` simulado, sin tocar `/data`.
- **Unidad de trabajo, según la etapa**: `run_rt_stps.sh` marca por archivo RAW y `run_sdr.sh` por RDR, pero de Level 2 en adelante la entrada es un directorio, así que la unidad es la **pasada**, identificada por satélite, fecha y órbita (`j01_d20260811_b45236`) tomados del nombre de los SDR. Cada script enlaza en un staging solo los archivos de esa pasada, porque los drivers de CSPP procesan todo lo que encuentren en el directorio que se les da. Los productos de Level 2 (`JRR-*`, `SurfRefl_*`) no llevan órbita en el nombre: se emparejan por el sello temporal del gránulo, que concatena fecha y hora de inicio (`GMTCO ... d20260811_t1947330` → `JRR ... s202608111947330`). No usar la existencia del log como estado: el log también queda cuando el proceso falla y logrotate lo borra a los 30 días.
- **Slurm**: los scripts de Level 2 más nuevos (`run_acspo_edr.sh`, `run_active_fire_edr.sh`, `run_cryo_edr.sh`, `run_lsr_edr.sh`) traen cabecera `#SBATCH` y usan `${SLURM_CPUS_PER_TASK:-N}` / `${SLURM_JOB_ID:-$$}` para funcionar igual con o sin Slurm. Los más antiguos no. El clúster con Slurm todavía no está en producción.
- **Manejo de errores**: bajo `set -euo pipefail` (`run_rt_stps.sh`, `procesar_cadena_completa.sh`) un `EXIT_CODE=$?` después de un `apptainer exec` es código muerto: el script ya abortó y nunca se imprime el mensaje que apunta al log. Hay que usar `... || EXIT_CODE=$?`, como en `run_rt_stps.sh`. `procesar_cadena_completa.sh` todavía tiene ese patrón roto en sus cuatro pasos. Los `run_*.sh` de EDR no usan `set -e` y sí revisan `$?` de verdad.

## Flujo de trabajo

`main` es la rama operativa conectada a la antena. Según el README: no hacer commits directos a `main`, trabajar en rama y abrir PR.
