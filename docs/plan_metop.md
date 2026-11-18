# Plan: METOP-B/C en la cadena de contenedores

**Escrito el 2026-09-26. Borrador para discutir con quien armó la rama METOP de la cadena
vieja (`referencia/metop/metop2.sh`); sin implementar.** Lo que ya está decidido va en la primera
sección; lo que depende de esa conversación, en "Preguntas para la rama vieja". Cuando algo
salga distinto al implementar, se marca aquí con **AL IMPLEMENTAR** en vez de reescribir el
diseño, como en `plan_operacion_datawork.md`, cuya fase 4 remite aquí.

---

## Por qué

El destino es que tahan, stratus y tsom03 tomen cualquier pasada desde contenedores
(`plan_operacion_datawork.md`, fase 3). Mientras METOP siga en su instalación de AAPP y el
metopizer, el sistema viejo no se apaga y stratus y tsom03 siguen atados a ella. METOP es lo
único que queda: de lo que llega a la antena, lo demás es JPSS (ya en contenedores) y Aqua
(que no procesa nadie).

## Decisiones tomadas

- **METOP va en este repositorio** (2026-09-26), no en uno aparte: comparte la recepción
  (`recibe.sh`, `config/cadenas.tsv`, el barrido), dos contenedores de Level 2 (HEAP y MiRS),
  el `.sif` de Polar2Grid con LANOT_tools y la publicación en kawak. Se instala en
  `/opt/lanot/polares` con lo demás.
- **Lo que entra: METOP-B y METOP-C** (`metop-1` y `metop-3` en `lspass`), por `chain6`
  (telemetría `ahrpt`), 3 a 5 pasadas al día de ~0.25 GB.
- **Lo que no entra, nunca:** Aqua (se apaga entre finales de 2026 y principios de 2027) y los
  NOAA heredados (NOAA-15/19, sin pasadas desde agosto de 2025, `referencia/noaa`).
- **Lo que no entra en este plan, pero sí en este repositorio: METOP-SG.** No es una exclusión
  sino un "todavía no": su `chain3` (`metopsgdb`) está configurada en TeraScan pero inactiva, y
  no ha llegado un solo crudo con qué probar. Tampoco se aprovecharía nada de esta rama —otros
  instrumentos (METimage, IASI-NG, MWS…), otro software de Level 1—, así que será otro
  contenedor y otra rama, con la misma recepción, cola, renderizado y publicación. Cuando
  empiece a llegar, se escribe su propio plan.
- **Mismas reglas que JPSS**: los `.def` instalan binarios y lo estático o dinámico vive en el
  host; marcador `.done` solo si la etapa produjo **todo** lo esperado; lo intermedio en
  `/data/tmp`; logs en `/var/log/lanot/polares/<etapa>/`.

## Lo que hace hoy la rama vieja

Resumen de `referencia/metop/metop2.sh` (versión del 2026-09-22), que corre en stratus y lo invoca el
`recibe.sh` de stratus para cada `chain6-*`:

1. `cadu_to_ccsds` (metopizer 3.51.1): CADU → paquetes CCSDS por instrumento (`isps.*`).
2. Distingue METOP-B de METOP-C buscando `METOP-*` en la salida del paso anterior.
3. `ccsds_to_l0` con el `mpr-config` del satélite → Level 0 por instrumento.
4. `get_tle` y luego `AAPP_RUN_METOP` por instrumento: AMSU-A, MHS, HIRS (solo METOP-B),
   AVHRR e IASI (este con OPS-LRS, `PATH_OPS`/`DIR_IASICONFIG`).
5. `convert_to_hdf5` y copia de todo a `/data3/output2/noaa_metop/{amsua,mhs,hirs,avhrr,iasi}/level1`.
6. AVHRR a GeoTIFF con Polar2Grid 3.0 del host (`avhrr_l1b_aapp`, `wgs84_geo_1000m`, float32
   sin realce), copiado a `avhrr/level1` **y** a `avhrr/vistas`.
7. IASI L1C, `amsual1b` y `mhsl1b` a un directorio de entrada de HEAP 2.x en tsom03, y
   `ssh tsom03 cspp_nucaps_metop.sh` para los sondeos.

Tiene los mismos defectos que ya se corrigieron en la rama JPSS vieja, y no se copian:
escribe el marcador (`$log/lastch5`) **antes** de procesar; borra el directorio de trabajo con
`rm -rf *` pase lo que pase; no revisa códigos de salida.

### Lo que hay en stratus y tsom03 (revisado el 2026-11-18)

Copias en `referencia/metop/`. Lo que hace falta saber para el contenedor:

- **El recorrido:** `recibe.sh` corre en stratus y lanza ahí mismo `metop2.sh` con cada
  `chain6-*`. Ese escribe en `/data3/output2/noaa_metop`, que es el `/data` de tsom03
  montado por NFS (`172.16.4.3:/data`), y al terminar dispara por `ssh`
  `cspp_nucaps_metop.sh` en tsom03.
- **Qué hace tsom03:** dos cosas, no una. Corre HEAP **2.0** (`run_heap.bash -s m01|m03`) y
  además **publica**: copia el Level 1 de los cinco instrumentos, los `.tif` de AVHRR y los
  NUCAPS a `/dataservice/noaa-metop/...` (y los NUCAPS al Peta, `/data2/output2`). Así que
  al apagar la rama vieja hay que reemplazar también esa publicación, no solo el
  procesamiento. **NUCAPS de METOP no tiene vista**: la llamada a Polar2Grid está comentada,
  `nucaps/vistas` está vacío desde junio de 2024, y `CSPP_SOUNDER_QL` se carga pero no se
  usa. Las "vistas" de AVHRR tampoco son JPG: son los mismos GeoTIFF float32 de `level1`.
- **Identifica la pasada por el AMSU-A más reciente** (`ls -t … | head -1`) con un marcador de
  un solo valor por satélite. Si llegan dos pasadas antes de que corra, la primera se pierde.
- **AAPP 8.12 compilado con su propio instalador** (`install_aapp8_v8.12.sh`, gfortran), con
  todas las dependencias en tarball: HDF5 1.10.1, eccodes 2.18.0, bufrdc, fftw 3.0.1,
  xerces-c 1.7.0, kai 1.12 y OPS-LRS V8.4. Los tarballs están en
  `stratus:/data/opt/AAPP/tarfiles` (lista en `tarfiles_stratus.txt`). AAPP y OPS-LRS se
  obtienen con registro en NWP SAF, así que esos tarballs **no se pueden volver a bajar
  libremente**: son la entrada del `.def` y hay que conservarlos en
  `/opt/contenedores` con su fila en `tarballs.tsv`. **Copiados el 2026-11-18** a
  `tahan:/opt/contenedores/aapp_8.12/` (87 MB, con `SHA256SUMS`), todos menos el atlas de
  MAIA4. Las filas de `tarballs.tsv` se agregan junto con el `.def`: hace falta un origen
  nuevo (`nwpsaf`) en el manifiesto y en `obtener_tarballs.sh`. El atlas de MAIA4 (987 MB) solo hace
  falta si se corre MAIA (máscara de nubes de AVHRR), y `metop2.sh` no lo corre.
- **El metopizer 3.51.1** está compilado en su árbol fuente (`~lanotadm/METOPIZER`), sin
  tarball aparte. Su `config/` va en `referencia/metop/metopizer_config` (sin los
  `IASI_BRD_*` de M02).
- **Estático que envejece y que nadie actualiza:**
  - `OPSAUX` (`DIR_IASICONFIG`): las BRD/GRD de IASI que publica NWP SAF. Su última
    actualización fue manual, el 2026-01-15, con `get_aux_files.sh`.
  - Los coeficientes de calibración de ATOVS, que se actualizan con
    `get_atovs_cal_files.sh`.

  Ninguno de los dos va en cron. En la cadena nueva es un `update_aapp_ancillary.sh`
  semanal, como el de HEAP.
- **Dinámico que se produce solo:**
  - `MMAM/`: los `MMAM_*.xml` y `TLE_*.tle` que `ccsds_to_l0` extrae de cada pasada
    (`-g`/`-u`). Lleva 5 712 archivos desde junio de 2024 y nadie lo poda.
  - `orbelems/tle_db`: lo escribe `get_tle` en cada pasada, **dentro del árbol de AAPP**.
    Como con HEAP, en el contenedor tiene que ir montado y escribible.
- **TLE:** `ATOVS_ENV8` las baja de EUMETSAT para M01, M02 y M03 sin credenciales. Space-Track
  (con cuenta: en la copia está censurada) solo es para NOAA-15/18/19, que ya no llegan, así
  que la cadena nueva no la necesita.
- **Los crudos de METOP ya llegan a tahan.** El reenvío de `recibe.sh` en stratus copia a
  `/datawork/input/polar/raw` todos los crudos, sin filtrar por cadena, y avisa al `recibe.sh`
  de tahan, que hoy los deja pasar como "no es de esta cadena". Hay `chain6-*` desde el
  2026-09-23 (268 al 2026-11-18). No hay que tocar la recepción para empezar: sirven de
  entrada de prueba, y sus productos viejos están en stratus para comparar.
- **IPOPP no entra.** En tsom03 IPOPP solo atiende MODIS (Aqua/Terra), que queda fuera de esta
  cadena. Los sondeos de METOP ya usan CSPP (HEAP 2.0), y aquí van con HEAP 3.0. AAPP sigue
  siendo necesario porque CSPP no cubre el paso de Level 0 a Level 1 de METOP.
- **Por revisar:** `STATION=exeter` y `SITE_ID=UKM`, los valores de ejemplo del instalador
  (`ATOVS_ENV8` sí pone `STATION_ID=LNT`). Hay que ver qué usa AAPP de la estación en
  `AAPP_RUN_METOP` antes de copiarlo.

## Qué ya está y qué falta

| Pieza | Estado |
|---|---|
| Recepción y enrutamiento (`recibe.sh`, `cadenas.tsv`, barrido) | Existe; METOP sale como "no es de esta cadena". Hay que enseñarle una segunda rama. |
| Level 0 → Level 1 (metopizer + AAPP + OPS-LRS) | **Falta todo**: contenedor, estático y `run_metop_l1.sh`. Es la pieza grande. |
| Sondeos (IASI + AMSU-A + MHS) | `cspp_heap_v3.0.sif` soporta `m01`/`m03` (manual §1.2 y §1.6.2); falta la rama METOP de `run_heap_edr.sh`. |
| Microondas (AMSU-A + MHS) | `cspp_mirs_v4.0.sif` las soporta; falta la rama en `run_mirs_edr.sh`. Opcional: la vieja no lo produce. |
| AVHRR a GeoTIFF y vistas | `polar2grid_v3.2-mapdrawer.sif` trae `avhrr_l1b_aapp`, y `wgs84_geo_1000m` ya está en `config/grid.yaml`. Falta el script, las CPT y las entradas de `product_map`. |
| Publicación en kawak | Falta la correspondencia en `publicar_kawak.sh`. |

## Trabajo, por pieza

### 1. Contenedor `metop_l1` (metopizer + AAPP + OPS-LRS)

- `.def` sobre `lanot_base_rocky8` o `_rocky9`, según lo que AAPP compile limpio. Compila
  AAPP 8.x, OPS-LRS y el metopizer. OPS-LRS es lo más delicado (Fortran, fftw, xerces y
  compañía): es la parte del sistema viejo con más pinta de ser "funciona porque nadie la toca".
- Los tarballs piden registro (NWP SAF, EUMETSAT): van a `contenedores/tarballs.tsv` con un
  origen nuevo, y `obtener_tarballs.sh --novedades` no los podrá consultar.
- **Estático en el host** (fase nueva de `preparar_servidor.sh`): OPSAUX, las configuraciones
  `mpr-config-M01`/`M03` y `ccsds.config`, y lo que AAPP necesite fuera de su árbol.
- **Dinámico en su propio caché** (`/data/ancillary/aapp`): TLE, el MMAM de `ccsds_to_l0`
  (`-g`/`-u`) y lo que refresque `get_tle`, con un `update_aapp_ancillary.sh` en cron. Hay que
  comprobar, como con HEAP y MiRS, si algo de AAPP escribe dentro de su árbol de instalación.
- `%test` que corra un crudo corto de prueba si hay uno pequeño disponible.

### 2. `run_metop_l1.sh`

- Patrón de los `run_*.sh`: marcador por crudo, `--force`, `--help`, autoselección, trabajo en
  `/data/tmp`, overrides `METOP_*`, conteo de productos contra una marca de inicio.
- **Éxito = todos los instrumentos esperados** para ese satélite (AMSU-A, MHS, AVHRR, IASI y,
  si se conserva, HIRS en METOP-B), no "salió algo".
- Identificar el satélite con algo más firme que el `grep` actual: la cabecera del Level 0 o
  el nombre que pone AAPP (`_M01_`/`_M03_`), y cotejarlo con lo que diga `cadenas.tsv`.
- Salida en un árbol hermano del de JPSS: `/data/output/metop/{level1,level2,geotiff,vistas,state}`.

### 3. Orquestación

- `config/cadenas.tsv`: una columna de rama (`jpss`/`metop`), para que la columna `xml` deje
  de hacer las veces de "¿lo procesa esta cadena?".
- `recibe.sh` y `barrer_pendientes.sh` despachan por rama. La cola de la fase 0.7 del plan de
  `/datawork` tiene que admitir los dos tipos de boleto.
- Un orquestador de pasada para METOP (L1 → AVHRR, HEAP y MiRS en paralelo), en vez de meter
  sus eslabones en los doce de `procesar_pasada.sh`.
- `scripts/pasadas.sh` agrupa por nombres de SDR (`j02_d…_t…`); METOP necesita claves a
  partir de los nombres de AAPP (`hrpt_M01_AAAAMMDD_HHMM_…`), con la misma regla de "por
  tiempo, no por órbita".

### 4. AVHRR

- Una sección de AVHRR en el renderizador de Level 1 (o un script propio), una llamada a
  Polar2Grid por conjunto de bandas, GeoTIFF float32 a `geotiff/avhrr` y vistas decoradas a
  `vistas/avhrr` — hoy la vieja publica los GeoTIFF de datos como vistas.
- CPT y entradas de `product_map` en LANOT_tools para lo que se decida mostrar: empujar, mover
  el pin, recompilar (y agregar a `%test` lo nuevo).
- Comparar contra las vistas que publica hoy la vieja antes de sustituirlas.

### 5. Sondeos con HEAP

- `run_heap_edr.sh`: entradas `IASI_xxx_1C_M0{1,3}_*`, `amsual1b_M0{1,3}_*.l1b` y
  `mhsl1b_M0{1,3}_*.l1b`, misión `m01`/`m03`, emparejadas por tiempo como CrIS ÷ ATMS. HEAP
  parte solo los IASI de pasada entera en trozos de 22–23 MDR (manual §1.6.2).
- Los nombres de los mapas y Skew-T hoy dicen `atms-cris`; para METOP, `iasi-amsu` o lo que
  se acuerde, y la entrada correspondiente en `product_map`.
- Confirmar que el lector `nucaps` de Polar2Grid lee igual la salida de METOP.

### 6. MiRS (opcional)

Rama `amsual1b_M0*`/`mhsl1b_M0*` en `run_mirs_edr.sh`. Es producto nuevo, no condición para
apagar la vieja.

### 7. Publicación

Categorías de METOP en `publicar_kawak.sh`, sin pisar lo que publica la vieja mientras
convivan (el mismo cuidado que con NPP y NOAA-20).

## Orden

1. Conversación con el autor de `metop2.sh` (preguntas de abajo).
2. Contenedor `metop_l1` + `run_metop_l1.sh`, probados a mano en tahan con un `chain6` real,
   comparando los Level 1 con los de `/data3/output2/noaa_metop/` de la misma pasada.
3. AVHRR a GeoTIFF y vistas.
4. HEAP con METOP; MiRS si sobra tiempo.
5. `cadenas.tsv` con rama `metop`, despacho en `recibe.sh` y el barrido, publicación.
6. Convivencia de unos días con la vieja; luego se apaga `metop2.sh` y su lado de tsom03.

## Preguntas para la rama vieja

**Software y compilación**
- Versiones exactas de AAPP, OPS-LRS y el metopizer, y de dónde salieron los tarballs (¿quién
  tiene la cuenta del NWP SAF y de EUMETSAT?).
- Qué hay en `~/ATOVS_ENV8` y qué se tocó de `ATOVS_CONF`. ¿Hubo parches o banderas de
  compilación especiales, sobre todo en OPS-LRS?
- ¿Qué más del host usa AAPP que no se vea en el script (bibliotecas, `eccodes`, HDF5 del
  sistema, variables de entorno)?

**Datos auxiliares**
- ¿Qué es y de dónde sale el contenido de `MMAM`? ¿Cambia con el tiempo?
- `get_tle`: ¿de dónde baja y con qué frecuencia hace falta? ¿Algo más que refrescar?
- `OPSAUX` y `DIR_IASICONFIG`: ¿se actualizan alguna vez o son fijos de la versión?

**Procesamiento**
- ¿Hay pasadas que fallen de forma conocida (cortas, con dropout, de un solo satélite)?
- El `grep METOP-*` para distinguir B de C: ¿ha fallado alguna vez?
- HIRS: ¿alguien usa el de METOP-B? ¿Y el A-DCS (`isps.a-dcs.ccsds`), que se genera y no se
  procesa?
- ¿Se conservan los Level 0 o los `isps.*` en algún lado?

**Productos y usuarios**
- ¿Quién consume `/data3/output2/noaa_metop/*/level1`? ¿Hace falta mantener el HDF5 de
  `convert_to_hdf5`, o basta el binario de AAPP que leen Polar2Grid, HEAP y MiRS?
- Qué se publica en kawak de METOP y desde dónde: ¿solo los GeoTIFF de AVHRR?
- `cspp_nucaps_metop.sh` en tsom03: qué produce con HEAP 2.x, dónde lo deja y si se publica.
- **¿Dónde corre `metop2.sh`?** `recibe.sh` de stratus lo lanza en local, pero
  `estado_y_pendientes.md` dice "METOP (`metop2.sh`, en tsom03)"; aclararlo y corregir el
  documento que esté mal.

**Futuro**
- ¿Hay fecha de fin para METOP-B?
- ¿Hay planes de recibir METOP-SG por `chain3`? Que `metopsgdb` ya esté configurada en
  TeraScan sugiere que alguien lo previó: ¿quién, y qué falta para activarla?

## Criterio para apagar la rama METOP vieja

- Varios días seguidos procesando sola cada `chain6`, sin intervención y sin crudos pendientes.
- Level 1 de AMSU-A, MHS, AVHRR e IASI equivalentes a los de la vieja en las mismas pasadas.
- Sondeos de METOP por HEAP 3.0 al menos iguales a los de HEAP 2.x en tsom03.
- Lo que publica la vieja en kawak lo publica la nueva, o se decidió dejarlo.
- Aviso si un crudo de METOP llega a `.fallido`, igual que para JPSS.
