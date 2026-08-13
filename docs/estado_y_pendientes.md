# Estado de la migración y pendientes

**Última actualización: 2026-08-12**

Documento vivo. Sustituye en la práctica a `migracion_polares.md` y `README_SCRIPTS.md`,
que describen la primera fase de la migración y ya no reflejan cómo corre la cadena.

---

## Lo que corre hoy de punta a punta

Probado en tahan con datos reales, todo sobre la misma pasada: **`j01_d20260811_b45236`**
(NOAA-20, 11 gránulos, 19:47–20:03 UTC).

| Eslabón | Script | Resultado |
|---|---|---|
| RAW → Level 0 | `run_rt_stps.sh` | 10 RDR |
| Level 0 → Level 1 | `run_sdr.sh` | 28 SDR de VIIRS |
| Level 2 atmósfera | `run_atmos_edr.sh` | 132 productos, 7m 30s |
| Level 2 superficie | `run_lsr_edr.sh` | 11 productos, 1m 37s |
| Level 2 criósfera | `run_cryo_edr.sh` | 22 productos, 5s |
| Level 2 incendios | `run_active_fire_edr.sh` | 11 productos, 2m 47s |
| Level 2 SST | `run_acspo_edr.sh` | 1 producto + 1 imagen, 1m 48s |
| Level 2 inundaciones | `run_flood_edr.sh` | 11 gránulos procesados; **falta reconfirmar tras el arreglo** |
| Vistas | `run_polar2grid_edr.sh` | **nunca se ha ejecutado** |

Cada eslabón sabe qué le toca procesar, no repite trabajo y distingue "terminó sin error"
de "produjo algo". Las convenciones comunes están en `CLAUDE.md`.

---

## Pendientes, en orden sugerido

### 1. Reconfirmar Flood
El arreglo del traslado desde el directorio de trabajo no se ha probado con datos reales.

```bash
rm /data/output/jpss/state/cspp-flood/j01_d20260811_b45236.done
scripts/run_flood_edr.sh          # esperado: 11 .nc en level2/flood
```

### 2. Probar `run_polar2grid_edr.sh`
Es el único eslabón que nunca ha corrido. Ya tiene todos sus insumos.

### 3. Precarga de ancillary de ATMOS
`update_atmos_ancillary.sh` no se ha ejecutado nunca. Correrlo a mano una vez y luego
montarlo en cron **cuatro veces al día** (el manual §2.4 lo pide por las cuatro corridas
del GFS):

```
17 2,8,14,20 * * * /home/lanotadm/bin/update_atmos_ancillary.sh
```

Mientras no exista ese cron, `run_atmos_edr.sh` fallará con una fecha nueva, porque usa
`-l` (solo caché local). `--download` es la salida de emergencia.

### 4. Vistas decoradas — el tema abierto
Discutido a fondo y sin cerrar. Lo que quedó establecido:

- Las vistas se hacen con `geotiff2view` (recolorea con un CPT) y `mapdrawer` (no
  recolorea: usa la paleta embebida). Ambas viven en el contenedor
  `polar2grid_v3.2-mapdrawer.sif`, que es el que debe usar el script.
- **Polar2Grid es indispensable**: los sensores polares miden en swath y hay que
  remuestrear a una rejilla antes de poder dibujar.
- Las rejillas de producción son propias y ahora están versionadas en
  **`config/grid.yaml`**: `wgs84_geo_750m` (bandas M, DNB, RGB) y `wgs84_geo_375m`
  (bandas I). Son dinámicas —solo proyección y resolución—, así que cada pasada da una
  extensión distinta.
- Los argumentos de decoración validados en producción están en
  `LANOT_tools/crea_vistas_viirs.sh:96-118`.
- Prioridad acordada: primero los productos de `geotiff2view` + CPT; los de `mapdrawer`
  (ya grillados y con paleta) se discuten después.

Preguntas sin responder:

- **Alcance**: ¿`run_polar2grid_edr.sh` cubre también el Level 1 (RGB `true_color` /
  `false_color` y DNB), reemplazando a `cspp_1_ptog.sh`, o se queda en Level 2?
  Hoy la cadena nueva **no produce RGB**, que es el producto más visible de todos.
- ¿De dónde salen hoy los `.tif` de `acspo` y `fire` que consume `crea_vistas_viirs.sh`?
  Los scripts que los generarían no están en cron.
- Paletas para nubes, LSR y criósfera: los CPT de `colortables/` se hicieron para las
  variables de CLAVR-x y los `JRR-*` traen otros nombres, códigos y rangos.

### 5. HEAP (rama ATMS/CrIS)
El tarball está en `/opt/contenedores/CSPP_HEAP_V3.0.tar.gz` y el manual en
`docs/manuals/`. Antes hay que validar la rama que nunca se ha ejercitado:

```bash
scripts/run_sdr.sh --sensor atms
scripts/run_sdr.sh --sensor cris
```

HEAP descarga su propio ancillary dinámico (con `lftp`), así que repite el patrón de
ATMOS: caché propio, modo local y descargador en cron.

### 6. Productos duplicados
`/data/output/jpss/level2/atmosphere` crece con cada reproceso: los `JRR-*` llevan campo
de creación en el nombre, así que una segunda corrida agrega en vez de sobrescribir. El
staging ya se protege enlazando solo la versión más reciente, pero falta decidir la
política de limpieza. La propuesta sobre la mesa es un `limpiar_productos.sh` en cron que
conserve la versión más reciente de cada producto y borre lo que pase de N días.

### 7. Recompilar con la base común
Las recetas ahora parten de `lanot_base_rocky8.sif` / `lanot_base_rocky9.sif`. Ninguna
imagen se ha recompilado con eso. Orden sugerido: primero las de Rocky 9 (menor riesgo,
ya validadas hoy), y al final RT-STPS y CSPP SDR, que sostienen los dos primeros eslabones
y pasan de 8.9 a 8.10. Conservar el `.sif` viejo hasta comprobar los conteos.

### 8. Decidir sobre Polar2Grid v3.1
Nadie lo usa en la cadena actual y su tarball ya no está en `/opt/contenedores`. O se
retira `contenedores/polar2grid_v3.1.def` del repositorio, o se recupera el tarball.

---

## Hallazgos que conviene no volver a descubrir

Cosas que costaron trabajo y no son evidentes leyendo el código:

- **`config/grid.yaml` define `itrf2008_lcc_375m` dos veces**, la segunda con resolución
  de 1000 m. En YAML gana la última, así que esa rejilla hoy vale 1000 m y no existe
  ninguna llamada `itrf2008_lcc_1000m`. Probablemente sea un error de dedo al agregarla.
- **LSR deduce cuántos gránulos hay contando los `JRR-AOD`**
  (`cspp_viirs_surface_reflectance.py:313`) y luego exige esa misma cantidad de cada
  producto. Con productos duplicados falla culpando a los `NWP_GFS-INTP`, que son los
  únicos que no se duplican.
- **ATMOS con `-l` no descarga ancillary**, y sin CMCSST cada gránulo aborta y la corrida
  entrega "0 products of 132" con código de salida 0.
- **Cada software tiene su propio caché de ancillary y no deben compartirse.** El de CSPP
  SDR usa subdirectorios por día; el de ATMOS guarda ~6 GB diarios sueltos en la raíz y
  los poda `delete_old_anc.sh`, que borraría el de SDR si se le apuntara ahí.
- **`gdal` arrastra 709 MB de rejillas de datum de PROJ de otros países** como dependencia
  débil. De ahí el `--setopt=install_weak_deps=False` en las recetas.
- **Las imágenes de Rocky en Docker Hub están congeladas** (9 en 9.3 de mayo de 2024, 8 en
  8.9). Rocky mantiene las suyas en Quay. Partir de Docker Hub y actualizar con `dnf` hacía
  que el contenido dependiera del día de compilación.
- **Los productos de Level 2 usan dos convenciones de sello temporal**: `s202608111947330`
  (fecha y hora) en los `JRR-*`, y `2026223_1947_33` (año y día juliano) en los
  `*_VIIRS_750M*`.
- **El mismo satélite aparece con tres nombres** según el producto: `j01` en los SDR,
  `NOAA20` en los `VIIRS_750M` de ATMOS, `n20` en los de Flood.
- **Los SDR de `run_sdr.sh` vienen agregados**: un archivo por banda para toda la pasada,
  con un solo GMTCO. Por eso el emparejamiento con los productos de Level 2 se hace por
  ventana temporal y no gránulo por gránulo.

---

## Material de referencia

- `scripts/cspp_1_ptog.sh` — el script **en producción hoy** en el servidor viejo, que
  genera los GeoTIFF de Level 1, las vistas DNB y las RGB. Es la referencia de lo que la
  cadena nueva tiene que llegar a cubrir. No se ejecuta desde este repositorio.
- `scripts/old_cspp_no_usar.sh` — la cadena monolítica anterior, solo como referencia.
- `scripts/procesar_cadena_completa.sh` — plantilla para reunificar los eslabones cuando
  todos corran solos. En espera, no en uso.
- `docs/manuals/` — manuales oficiales de CSPP y RT-STPS, sin rastrear en git. Consultar
  con `pdftotext -layout` antes de suponer cómo se comporta un driver: ahí estaba la
  respuesta a lo del `-l` de ATMOS y a las entradas que exige LSR.
