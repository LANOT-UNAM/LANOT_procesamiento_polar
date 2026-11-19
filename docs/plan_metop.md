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

  **Qué haría falta para recibirlo (revisado el 2026-11-18):**

  - **En polaracq (TeraScan):**
    - Activar `chain3` (`telemetry.active: no` en `referencia/terascan/system.config`).
    - Corregir la línea `metop-sg-a1 frequency: 7825.00`, a la que le falta el punto: el
      formato es `<satélite>.frequency`, y así TeraScan probablemente la ignora. Hay que ver
      si sigue así en polaracq, porque nuestra copia es del 2026-09-22.
    - Darle al programador de pasadas los TLE de Metop-SG-A1, que están en la página de TLE
      de EUMETSAT, y un criterio de prioridad: va en la misma órbita de media mañana que
      METOP-B/C y puede chocar con `chain6` y con JPSS.
  - **El riesgo es la antena.** EUMETSAT habla de unos 3 m según las condiciones del sitio,
    y la nuestra es de 2.4 m (`ANT-24-11P`). Hasta no recibir una pasada no se sabe si
    alcanza.
  - **De nuestro lado, nada hasta que llegue un crudo.** `recibe.sh` de stratus ya reenvía
    todo; al primer crudo se agrega la fila de `chain3` en `cadenas.tsv`.
  - **Software, de NWP SAF (que distribuye los procesadores de EUMETSAT):**
    - Level 0 y Level 1 de MWS y de METimage, con scripts envolventes (versión del
      2026-04-30).
    - Una configuración de RT-STPS para pasar del crudo a VCDU. Ese paso lo puede hacer
      nuestro `rt_stps_7.0.sif`.
    - El procesador de IASI-NG esperaba aprobación de EUMETSAT; está por confirmar si ya
      salió.
    - Otra versión hacia principios de 2027, al terminar la puesta en servicio.
    - Las órbitas para procesar se bajan con `eumdac` del Data Store de EUMETSAT, que pide
      cuenta.
    - AAPP-SG 1.0 (MWS e IASI-NG) es posterior al Level 1, no lo sustituye.
  - **Productos, por verificar:** si MiRS acepta MWS y si el Satpy del bundle lee METimage.
  - **Primer paso:** pedir a quien maneja polaracq que active `chain3` unos días, solo para
    ver si llegan crudos completos. Si llegan, se escribe el plan con un crudo real.
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
  nuevo (`nwpsaf`) en el manifiesto y en `obtener_tarballs.sh`.
- **La receta será con AAPP 8.15 y metopizer 3.57, no con las versiones de stratus**
  (decidido el 2026-11-18). Las entradas están en `tahan:/opt/contenedores/aapp_8.15/`
  (85 MB, con `SHA256SUMS`):
  - `AAPP_8.15.tgz`, bajado del área de usuario de NWP SAF.
  - `metopizer_3_57_tar_9b77fef66a.zip`, del User Portal de EUMETSAT. Pide cuenta y
    aceptar la licencia; sin sesión da "acceso denegado".
  - El instalador `install_aapp8_v8.15.sh`.
  - HDF5 1.10.6 y ecCodes 2.38.0, que son las dos dependencias que cambian y se bajan de
    sus sitios públicos.
  - Lo que no cambia, copiado de `aapp_8.12/`: OPS-LRS V8.4, kai 1.12, fftw 3.0.1,
    xerces-c 1.7.0, `iostream.h`, bufrdc, `iasi_pca_comp` y los dos scripts de NWP SAF.

  Pasos del instalador que se usan: 1–4, 6–9 y 11. Se saltan el 5 (atlas de MAIA4), el 10
  (OPSAUX, que va en el host) y del 12 al 14 (netCDF y AAPP-AWS, del Arctic Weather
  Satellite). Lo que hay que saber al escribir el `.def`:
  - **El metopizer no compila con C++17.** Su `enum byte` choca con `std::byte`, y su
    `INSTALL.rst` pide `CXXFLAGS="-std=c++14"` con gcc 11 o más nuevo, que es el de
    `lanot_base_rocky9`.
  - **libfec se carga en tiempo de ejecución** (`dlopen("libfec.so")`), por eso no
    aparece en `ldd`. No hay paquete en Rocky. Se compila `quiet/libfec` (commit
    `9750ca0a6d0a`) con CMake como biblioteca compartida.
  - **El metopizer 3.57 necesita un parche de una línea**: a `rs_decode()` le falta el
    `return`, y con gcc moderno `cadu_to_ccsds` truena en el primer CADU. Está en
    `contenedores/parches/`. Con eso, probado en tahan (gcc 14) sobre
    `chain6-2_pass52_20261118T161249`: código 0, 13 s, 5 MB de RAM, METOP-C, 12 flujos de
    instrumento (IASI 117 MB, AVHRR 49 MB).
  - **`ccsds_to_l0` 3.57 también funciona, sin parche** (mismo crudo, mismos argumentos que
    `metop2.sh`): código 0 en 0.2 s, los siete Level 0 de METOP-C (AMSA, MHSx, HIRS, AVHR,
    IASI, HKTM, ADCS). El MMAM y el TLE que extrae de la pasada salieron **idénticos byte a
    byte** a los de stratus (`…M03_015482…`). Con el caché vacío arranca sin MMAM y lo toma
    en cuanto aparece en los datos; con el caché lleno lo carga del disco desde el inicio.
    Entre las dos corridas, los productos difieren solo en la hora de creación de la cabecera
    (6 bytes), salvo HKTM, que difiere además en sus primeros ~10 KB: son los paquetes
    anteriores al MMAM. Por eso el caché de MMAM tiene que **persistir** entre pasadas, en
    el host y escribible, como en stratus.
  - **La 3.57 no trae `mpr-config-M01`/`M03`**: en stratus se escribieron a mano en 2020 y
    están en `referencia/metop/metopizer_config/`. Dicen `receiving_ground_station=SVL`
    (Svalbard) y `processing_centre=CGS1`, que son valores de ejemplo. Van a la cabecera
    MPHR del Level 0; hay que decidir si se ponen los del LANOT.
  - Cambios de la 3.51 a la 3.57: ninguno en `cadu_to_ccsds`. En `ccsds_to_l0` se
    "reactivó" la herramienta (3.57), y la 3.54 corrigió dónde busca las BRD de M03 el
    lector de IASI en Python, que nosotros no usamos. El atlas de MAIA4 (987 MB) solo hace
  falta si se corre MAIA (máscara de nubes de AVHRR), y `metop2.sh` no lo corre.
- **`aapp_v8.15.sif` compila y pasa su `%test`** (tahan, 2026-11-18, 363 MB, sobre
  `lanot_base_rocky9`; receta en `contenedores/aapp_v8.15.def`). Salió al sexto intento; cada
  fallo fue algo que el instalador de NWP SAF da por presente en una máquina de escritorio y
  que la base mínima no trae. Están explicados en los comentarios del `%post`, pero por orden:
  1. Paso 3 (ecCodes 2.38): `CRITICAL - AEC library was not found`. El instalador solo apaga
     AEC si no existe el programa `aec`, y la base sí lo tiene (llega con el hdf5 del
     sistema) pero sin encabezados → `libaec-devel`.
  2. Paso 9 (OPS-LRS): `flex: command not found` y `bison: command not found` al generar el
     analizador de `SD_BAS_DECOM`. `libfl-static` no basta: hacen falta los programas.
  3. Paso 9: `cannot find -lnsl` al enlazar `MSGS__Serveur`; glibc ya no la trae →
     `libnsl2-devel` (CRB).
  4. Paso 9: `rsync: command not found` en el `make install` de OPS-LRS.
  5. `%test`: no encontraba `cadu_to_ccsds`. La plantilla de `ATOVS_ENV8` **reemplaza el PATH
     entero** por el de la compilación si no ve en él sus propias rutas, y con eso se pierden
     el metopizer y `/opt/aapp/bin`. Se arregla agregando al final de `ATOVS_ENV8` las rutas
     que falten. Ojo al escribir `run_metop_l1.sh`: todo lo que se ponga en el PATH antes de
     cargar `ATOVS_ENV8` puede desaparecer.

  El `%test` comprueba `ATOVS_ENV8`, `AAPP_RUN_METOP`, `get_tle`, `convert_to_hdf5`, los TLE de
  EUMETSAT, el árbol de OPS-LRS y sus módulos de Perl, `cadu_to_ccsds`, `ccsds_to_l0`
  (`3.57`), `ccsds.config` y `libfec.so` en el caché de `ldconfig`. **No corre ninguna pasada**,
  y por eso no vio lo que sigue.
- **La primera pasada dentro de la imagen sacó tres problemas más**, todos ya corregidos en el
  `.def` (la compilación buena es `tahan:/data/tmp/aapp_build_20261118_bz2/aapp_v8.15.sif`, la de las 18 h, ya con la descarga de coeficientes apagada;
  va a `/opt/containers`, donde están las de operación —`/opt/contenedores` es el de tarballs y
  compilación—):
  1. `ccsds_to_l0` abre `libbz2.so` con `dlopen`, igual que el metopizer a libfec, y muere con
     `Cannot open bz2 library`. En la prueba de la tarde no se vio porque el metopizer corrió en
     el host, que tiene `bzip2-devel` → `bzip2-devel` (y `bzip2`, que `AAPP_RUN_METOP` usa con
     HKTM).
  2. `atovpp -g IASI` llama a `iasi_eigenvectors`, que **la primera vez** convierte los
     eigenvectores HDF5 a `.dat` dentro de `data/preproc`: en la imagen, `Read-only file system`
     y la pasada entera abajo. Son de la versión → se generan en `%post`, y el `%test` lo
     comprueba ya con la imagen de solo lectura.
  3. `avh_get_vis_coefs` escribe en `data/calibration/coef/avhcl` en cada pasada, y HIRS guarda
     ahí su historia. **No se puede redirigir con variables**: `ATOVS_ENV8` fija
     `DIR_CALIBRATION`/`PAR_CALIBRATION_COEF` sin `${VAR:=…}` y cada script de AAPP lo vuelve a
     cargar vía `ATOVS_CONF`. Se monta `/data/ancillary/aapp/calibration` encima de la ruta
     interna, como el estático de SDR, y `run_metop_l1.sh` lo siembra desde la imagen la
     primera vez. Las de navegación y OPSAUX sí llevan `:=` y basta exportarlas.

  Además, `net-tools` (OPS-LRS revisa su puerto con `netstat`; sin él solo avisa), y `HOME`
  apuntado al trabajo dentro del contenedor, porque `ATOVS_CONF` carga `$HOME/ATOVS_ENV8` si
  existe y en stratus `lanotadm` tiene uno.
- **`run_metop_l1.sh` probado en tahan el 2026-11-18** sobre `chain6-2_pass52` (METOP-C) y
  `chain6-1_pass51` (METOP-B), con todo dirigido a `/data/tmp/metop_prueba_20261118/`: 3 min
  por pasada, 13 archivos de Level 1 cada una (AMSU-A, MHS, AVHRR, IASI en 1C de EUMETSAT y en
  formato AAPP, con sus HDF5), cero escrituras en la imagen, y el marcador detiene la segunda
  corrida.
- **Comparación con stratus** (mismas dos pasadas, 2026-11-18). Los md5 no coinciden en ningún
  archivo y no tienen por qué: los binarios de AAPP llevan fecha y versión de proceso, y las
  diferencias se reparten por todas las líneas. Leídos con Satpy (`mhs_l1c_aapp`,
  `avhrr_l1b_aapp`):

  | | METOP-C | METOP-B |
  |---|---|---|
  | AVHRR 4, 5 (IR) | 100 % de píxeles iguales | 100 % |
  | AVHRR 1, 2, 3a (VIS) | 100 % | **×1.04, ×1.20, ×1.37** (ver abajo) |
  | MHS | ≥ 99.9 % iguales, el resto ±0.01 K (último dígito empaquetado) | igual |
  | Lat/lon | ≤ 0.0014° (~150 m): AAPP 8.12 → 8.15 y TLE de otra hora | igual |
  | HIRS | no se procesa | **vacío en los dos lados**: el de stratus tampoco sale |

  Tamaños idénticos en todo menos `iasil1d_M01…l1d.h5`. Stratus deja **dos** IASI 1C por
  pasada de METOP-C (OPS-LRS corre en dos de sus cinco llamadas); aquí, uno.

  **IASI, sin cerrar.** En el 1C de EUMETSAT de METOP-C difieren 2.1 M de 218 M bytes: los
  sellos de proceso de la MPHR y, después, bytes contiguos en todos los registros, con
  diferencias casi siempre de pocas unidades. Los auxiliares (BRD/GRD) vigentes son los
  mismos en los dos lados y OPS-LRS es el mismo V8.4, así que lo más probable es redondeo de
  punto flotante por otro compilador (gcc 14 aquí); no está demostrado. Satpy 3.2 no tiene
  lector de IASI 1C. Decidido el 2026-11-18: no se decodifica el EPS; se cierra al comparar
  los NUCAPS de HEAP con los de stratus (pieza 5).
  AAPP sí es determinista: dos corridas de la misma pasada dan el AVHRR idéntico byte a byte.
- **Los visibles de AVHRR: stratus está mal desde el 2026-08-21, y se usan los de 2017.**
  `avh_get_vis_coefs` baja los coeficientes operativos de NOAA STAR (sitio de Libia) cuando la
  última entrada local tiene más de 7 días, y guarda **cualquier** respuesta con código 200. Ese
  día NOAA contestó con una página HTML, que sustituyó a `Metop1_…` y `Metop3_AVHRR_Libya_ch*.txt`
  en stratus: sin una sola línea válida, AAPP calibra con la de base, sin la corrección por
  degradación. Hoy NOAA contesta 404 —dejó de publicarlos— y el archivo de METOP-B que trae
  AAPP 8.15 termina en **agosto de 2017**. Decidido el 2026-11-18: METOP-B con los de 2017 (la
  entrada más cercana a la fecha, que es lo que AAPP hace solo) y **descarga apagada** en el
  `.def` (`AVHRR_VISIBLE_URL` vacía), para que una respuesta rara no los vuelva a borrar.
  METOP-C no tiene archivo en AAPP 8.15 y queda con la de base, como en stratus. Consecuencia:
  los visibles de METOP-B que publique la cadena nueva **no** se podrán comparar con los de
  stratus de agosto en adelante.
- **El HIRS de METOP-B no calibra**: `hirscl_algoV4` da `No enough calib cycles found` (todas
  las líneas de la pasada sin ciclo de calibración). Como `AAPP_RUN_METOP` aborta en cuanto
  falla un instrumento, con HIRS en la llamada no sale nada. **Eso explica las cinco llamadas de
  `metop2.sh`**, que parecían redundantes: la completa revienta y lo publicado sale de las
  sueltas. `run_metop_l1.sh` hace una llamada con lo exigido y otra, opcional, con HIRS. Falta
  confirmar en stratus si su `hirs/level1` de METOP-B lleva tiempo vacío.
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
| Recepción y enrutamiento (`recibe.sh`, `cadenas.tsv`, barrido) | **Hecho** (2026-11-18): rama `metop` en `cadenas.tsv` desde el 2026-11-19, código 4 de `consultar_cadena`; `recibe.sh` lanza `run_metop_l1.sh` y el barrido recoge lo pendiente. Probado con simulados; falta la primera pasada real tras instalar. |
| Level 0 → Level 1 (metopizer + AAPP + OPS-LRS) | Contenedor y `run_metop_l1.sh` **hechos y probados** con una pasada de cada satélite (2026-11-18). Faltan: comparar con stratus, la fase de `preparar_servidor.sh` (`/data/ancillary/aapp/opsaux` con `get_aux_files.sh`), `update_aapp_ancillary.sh`, las filas de `tarballs.tsv`, y que `/data/output/metop` entre en `config/retencion.tsv` y en el catálogo (los dos suponen `/data/output/jpss/`): IASI deja ~800 MB por pasada. |
| Sondeos (IASI + AMSU-A + MHS) | `cspp_heap_v3.0.sif` soporta `m01`/`m03` (manual §1.2 y §1.6.2); falta la rama METOP de `run_heap_edr.sh`. |
| Microondas (AMSU-A + MHS) | `cspp_mirs_v4.0.sif` las soporta; falta la rama en `run_mirs_edr.sh`. Opcional: la vieja no lo produce. |
| AVHRR a GeoTIFF y vistas | `polar2grid_v3.2-mapdrawer.sif` trae `avhrr_l1b_aapp`, y `wgs84_geo_1000m` ya está en `config/grid.yaml`. Falta el script, las CPT y las entradas de `product_map`. |
| Publicación en kawak | Falta la correspondencia en `publicar_kawak.sh`. |

## Trabajo, por pieza

### 1. Contenedor `metop_l1` (metopizer + AAPP + OPS-LRS)

**Hecho el 2026-11-18 como `aapp_v8.15.def`, sobre `_rocky9`** (detalle arriba). Siguen
pendientes de esta pieza: las filas de `tarballs.tsv` con el origen `nwpsaf` y que
`construir.sh` la conozca, el estático en el host y comprobar qué escribe AAPP en su árbol,
lo que se verá al correr la primera pasada con `run_metop_l1.sh`.

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

**Hecho el 2026-11-18** (pruebas arriba). Caché en `/data/ancillary/aapp/{mmam,orbelems,
calibration,opsaux}`, salida en `/data/output/metop/level1/{amsua,mhs,hirs,avhrr,iasi}`,
marcador en `state/aapp/<crudo>.done` con manifiesto `.l1`. Los `mpr-config-M01`/`M03` van en
`config/`, todavía con los valores de ejemplo de stratus (`SVL`/`CGS1`) para poder comparar.
Lo que sigue de esta lista es el diseño original; la clave de pasada para `pasadas.sh` queda
para la pieza 3.

- Patrón de los `run_*.sh`: marcador por crudo, `--force`, `--help`, autoselección, trabajo en
  `/data/tmp`, overrides `METOP_*`, conteo de productos contra una marca de inicio.
- **Éxito = todos los instrumentos esperados** para ese satélite (AMSU-A, MHS, AVHRR, IASI y,
  si se conserva, HIRS en METOP-B), no "salió algo".
- Identificar el satélite con algo más firme que el `grep` actual: la cabecera del Level 0 o
  el nombre que pone AAPP (`_M01_`/`_M03_`), y cotejarlo con lo que diga `cadenas.tsv`.
- Salida en un árbol hermano del de JPSS: `/data/output/metop/{level1,level2,geotiff,vistas,state}`.

### 3. Orquestación

- **Hecho el 2026-11-18.** `config/cadenas.tsv` tiene columna `rama` (`jpss`, `metop`, `-`)
  y `consultar_cadena` devuelve 4 para `metop`, sin cambiar su salida (`<satélite> <xml>`),
  que tres scripts leen con `read`. La fila `metop` de `chain6` vale **desde el 2026-11-19
  00:00 UTC**: es fecha de corte, para que el barrido no procese los 268 `chain6` que ya
  estaban en el buzón (~13 h y >200 GB). Uno de esos se puede procesar a mano con
  `run_metop_l1.sh <crudo>`, que lo acepta con aviso.
- `recibe.sh` lanza `run_metop_l1.sh` en segundo plano con log en
  `cadena/<fecha>_metop_<crudo>.log`; `barrer_pendientes.sh` tiene una tercera tarea con las
  reglas de los crudos de JPSS (intentos, `.fallido`) sobre `state/aapp`, y le pasa
  `METOP_ESPERA_MIN=0`: con AAPP ocupado, `run_metop_l1.sh` sale en 75 y no cuenta.
- Mientras convivan, stratus sigue procesando METOP con `metop2.sh`: los dos lados producen.
- Pendiente: la cola de la fase 0.7 del plan de `/datawork` tiene que admitir los dos tipos
  de boleto.
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

- **Aquí se cierra la comparación de IASI** con stratus (ver "IASI, sin cerrar" arriba): los
  NUCAPS de una misma pasada, de HEAP 3.0 sobre nuestro 1C, contra los de HEAP 2.0 en tsom03.
  Son versiones distintas de HEAP, así que una diferencia ahí no culpa todavía al 1C: si sale
  grande, correr HEAP 3.0 sobre el 1C de stratus para separar las dos causas.
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
