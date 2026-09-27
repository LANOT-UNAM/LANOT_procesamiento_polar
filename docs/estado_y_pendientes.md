# Estado de la migración y pendientes

**Última actualización: 2026-09-27**

**Los doce eslabones corren con datos reales.** La cadena nueva ya cubre lo que hace el
servidor viejo, RGB incluido, y desde el 2026-08-13 también **OMPS**, que era lo último
que faltaba de aquello. Desde el 2026-09-22 el ozono tiene también su vista, sin esperar a
Polar2Grid 3.3 (pendiente 8).

El doceavo, **HEAP**, se escribió y se probó el 2026-08-15: sondeos NUCAPS de CrIS+ATMS,
que van **más allá** de lo que hace el servidor viejo. **Corregido el 2026-08-17: HEAP no
produce sondeos.** Escribe radiancias limpiadas de nube y onda larga saliente, pero ni un
`NUCAPS-EDR`, que es el producto. Y no es culpa de la cadena: los datos de prueba del propio
CIMSS, con su propio comando, reproducen el fallo. Ver el pendiente 4.

La pregunta de si convenía integrar CSPP Sounder QL a alguno de nuestros contenedores
**quedó contestada, y la respuesta es que no hace falta**: el lector `nucaps` de Polar2Grid
3.2 ya rinde los sondeos, probado de punta a punta. Ver el pendiente 4.

Documento vivo. Sustituye en la práctica a `migracion_polares.md` y `README_SCRIPTS.md`,
que describen la primera fase de la migración y ya no reflejan cómo corre la cadena.

---

## 2026-09-27: el disco, y un GFS truncado que tumbó la tarde del 26

**`/data` estaba al 96 %**: 1.7 TB libres de 37 TB, compartidos con los demás proyectos del
servidor. El mismo día se borró `/data/respaldo` (18 TB de tars de 2025 de la cadena vieja,
todos ya en `/depot` salvo una versión reprocesada de un compuesto de inundación) y bajó al
47 %, con 20 TB libres. Lo que sigue es el reparto antes de ese borrado. De la cadena: `level2` 885 GB, `level1` 668 GB, `geotiff` 352 GB, `level0` 75 GB,
`vistas` 1 GB. Y **`/data/tmp`, 872 GB**, que casi iguala a Level 2:

- ~507 GB en directorios de trabajo de corridas fallidas (`atmos_work_*`, `lsr_work_*`,
  `heap_*`, `omps_*`, `sdr_work_*`), que los `run_*.sh` conservan para depurar. Casi todos
  son de ATMOS, a ~10 GB cada uno.
- 285 GB de `viirs_afai_historico` y ~75 GB de pruebas de agosto (`CLAVRx_3_0`,
  `polar2grid_l2`, `data`).

Hay además ~19 GB de GFS de mayo sueltos en la raíz de `/data/ancillary`, de antes de que
ATMOS tuviera su propio caché, y 17 GB en `/data/output/jpss/tmp`, de la primera fase.

**Por qué ATMOS falló toda la tarde del 2026-09-26.**
`atmos/gfs.t12z.pgrb2.0p25.f009.20260926` pesa 277 MB, cuando los demás pesan ~520: la
descarga se cortó a la mitad. Las cuatro pasadas de la tarde lo usaron, y cada corrida dio
`completed 0 products` con `FATAL … wgrib_avn.cpp: End of resource reached when reading
message`. El archivo sigue en el caché, así que nada lo repone: ni el segundo intento de
`run_atmos_edr.sh` (sin `-l`) ni el updater lo vuelven a bajar, porque ya existe. Las
cuatro pasadas agotaron sus tres reintentos del barrido y quedaron en `.fallido`, sin LSR
ni CRYO. Cada intento dejó ~10 GB en `/data/tmp`: 19 directorios solo ese día.

Pendiente, sin urgencia (la idea es observar dos semanas de operación antes de tocar nada):

- **Validar lo que descarga `update_atmos_ancillary.sh`**: tamaño mínimo, o leer el GRIB
  entero. Un archivo truncado no debe quedarse en el caché como si fuera bueno. El de
  arriba se puede borrar ya: ninguna pasada nueva usa ese ciclo.
- **La limpieza del pendiente 5 abarca más de lo que decía.** No es solo quitar duplicados
  de `JRR-*`. Es un script en cron (el crontab de `lanotadm` hoy no tiene ninguno) que
  borre los directorios de `/data/tmp` de más de N días y aplique retención por nivel.
  Level 0 y Level 1 son los candidatos obvios: pesan mucho y nadie los usa fuera de la
  cadena. También barrería los restos viejos: `geotiff/lsr_rgb/`, los DNB viejos de abajo y
  `/data/output/jpss/tmp`.

## 2026-09-27: catálogo de productos

`docs/catalogo_productos.tsv` describe los 46 productos de Level 1 en adelante (Level 0
queda fuera: nadie lo usa fuera de la cadena). Es para dos públicos: el externo, que quiere
saber qué hay, en qué formato y con qué unidades, y el interno, que necesita saber de dónde
sale cada cosa. El TSV es la fuente y `docs/catalogo_productos.md` se genera con
`scripts/generar_catalogo.py`. Con `--verificar`, el script lo contrasta contra los `-p` de
los renderizadores, `PALETAS`, `product_map` y las rutas de los scripts.

Las variables, unidades, patrones de nombre y satélites se confirmaron el mismo día en tahan,
con `ncdump -h` y listados de `/data/output/jpss`. Salió más de lo que se buscaba:

- **`AFIMG_*.txt` es un producto**: la lista de incendios en texto (lat, lon, T4, FRP,
  confianza), que CSPP Active Fire deja junto al `.nc`. Entró al catálogo. Los
  `NOAA_AFIMG_*.log` del mismo directorio son logs.
- **Restos de corridas viejas en `geotiff/`**: `lsr_rgb/` (los RGB de superficie retirados
  el 2026-08-14) y los `adaptive`/`histogram`/`hncc_dnb` de NOAA-20 en `dnb/`. Se pueden
  borrar; ya no se producen.
- **`gdalinfo -stats` escribe un `.aux.xml` junto al GeoTIFF.** Para consultar un GeoTIFF
  del árbol de productos, usar `gdalinfo` sin `-stats`.

Pendiente:

- **Segunda etapa: inventario por pasada.** Un script en tahan que recorra
  `/data/output/jpss`, compare cada pasada contra el catálogo y diga qué productos salieron y
  cuáles faltan. Cuando exista, el TSV se muda a `config/`, porque la operación ya dependería
  de él. LANOT_tools ya emite Items de STAC (`stac_item.py`); cada fila del catálogo sería una
  Collection, y para eso se pensaron los `id`.

---

## 2026-09-26: MiRS, para que ATMS tenga productos propios

**Al retomar:**

1. **Rótulo del 165 GHz, sin urgencia.** Va en la misma recompilación que el punto 5: el
   pin ya está en `a94d579`, que incluye `5868a3c`. Hasta entonces las vistas salen
   "165 GHz".
2. ~~Informe breve que justifique pasar del sistema viejo al nuevo.~~ **Escrito**:
   `docs/informe_transicion_jpss.md`, una página para la junta del lunes 2026-09-28. Se
   convierte con `pandoc informe_transicion_jpss.md -o informe.pdf --pdf-engine=xelatex
   -V geometry:margin=2cm -V papersize=letter -V fontsize=10pt -V mainfont="DejaVu Sans"`;
   con otros márgenes o letra más grande se pasa a dos páginas. Para mostrar en la junta,
   `docs/figuras/comparacion_atms_165ghz.png`: el quicklook viejo del canal 17 contra la
   vista nueva de 165 GHz, la misma pasada de NOAA-20 (26-sep, 09:20 UTC). La nueva va sin
   `--lat-south` por el pendiente 5, así que la barra tapa un poco la orilla sur.
3. **Idioma de los rótulos**, en la junta del lunes 2026-09-28 (ver abajo).
4. **La página de kawak** tiene que mostrar `jpss/atms/`.
5. ~~**`--lat-south` le corta el norte a las pasadas cortas.**~~ **Arreglado el 2026-09-27**
   en LANOT_tools `a94d579` y afinado en `b37ad84`, pin movido en
   `polar2grid_v3.2-mapdrawer.def`. `make_south_room` recortaba del norte tantas filas
   como pedía el espacio sur, sin mirar si tenían dato. Medido en tahan, solo actúa en
   pasadas cortas (en las completas el borde sur ya está al sur de 11°N), y en todas cortaba
   dato: 9.5 % y 24 % en dos sondeos de NOAA-20, y 67 % en un ATMOS de NPP. Ahora solo
   recorta filas vacías y, si no alcanzan para la barra, agranda el lienzo hacia el sur
   solo lo que la barra ocupa (~1/9 de la altura), no hasta 11°N. La primera versión
   (`a94d579`) crecía hasta 11°N, y una vista de incendios que acababa en 28°N pasó de
   1798 a 3353 filas, casi todas de mapa vacío; con `b37ad84` queda en 1998. Con el norte
   vacío hace lo mismo que antes, y ahora también actúa en pasadas de muy pocos gránulos,
   donde el espacio pedido excede la imagen.

   Las 61 vistas que el recorte viejo había dañado (36 pasadas del 14-ago al 27-sep, casi
   todas de incendios) se rehicieron solo vistiendo de nuevo, sin Polar2Grid, con
   `/data/tmp/revestir_latsouth_20260927/revestir.sh` (la lista va al lado, y las vistas
   viejas en `respaldo/`). Se repite con la imagen de `b37ad84`.

Salió de revisar qué se pierde al jubilar los quicklooks de ATMS (ver "Condiciones para
jubilar la cadena vieja", punto 3). En vez de reproducir 22 canales en bruto que nadie mira,
**CSPP MiRS v4.0** (MiRS v11r9, de NOAA/STAR): lluvia, agua precipitable, agua líquida de
nube y las 22 temperaturas de brillo con corrección de limbo en el `NPR-MIRS-IMG`, y
perfiles de temperatura y humedad en el `NPR-MIRS-SND`. Soporta NPP, NOAA-20 y NOAA-21, y
también AMSU-A/MHS de Metop-B/C, que servirá en la fase de METOP.

**Probado en tahan**, primero a mano y luego con `run_mirs_edr.sh` y un `apptainer`
sustituto (base rocky8 con el bundle montado `:ro` en `/opt/cspp_mirs`, que es lo que dará
el `.sif`):

| Pasada | Gránulos | Tiempo (`-p 8`) | Salida |
|---|---|---|---|
| `j02_d20260926_t082141` | 20 | 1m 46s, 5.6 GB de RAM | IMG 6 MB + SND 66 MB |
| `npp_d20260926_t085934` | 20 | 1m 42s | IMG + SND |

La de NOAA-21: 58 % de recuperaciones óptimas y 0 % malas; agua precipitable de 5 a 85 mm
(mediana 47), lluvia en 2166 píxeles (máx. 9.7 mm/h), 88 GHz hasta 215 K. Traía un ciclón
frente a la costa del Pacífico, con el ojo a la vista en 88 GHz. `WindSp` e `IWP` vienen
vacíos. Polar2Grid 3.2 la lee sin avisos con el lector `mirs` (`rain_rate`, `tpw`, `clw`,
`btemp_88v`, `btemp_165h`) a `wgs84_geo_5km`.

**Escrito**: `contenedores/cspp_mirs_v4.0.def` (sin compilar), `scripts/run_mirs_edr.sh`,
su fila en `tarballs.tsv` y sus directorios en `preparar_servidor.sh`. **Falta, en orden:**

1. ~~Compilar el `.sif`, instalar y crear los directorios.~~ **Hecho el mismo día**: la imagen
   (867 MB) pasa su `%test`, y `run_mirs_edr.sh` desde `/opt/lanot/polares` con ella sobre
   `j02_d20260926_t082141` tardó 1m 47s y dio IMG y SND **idénticos** a los de la prueba
   (BT, RR, TPW, CLW, TSkin, geolocalización, PTemp, PVapor). `/data/ancillary/mirs` sigue vacío.
2. ~~La sección `mirs` en `run_polar2grid_edr.sh`.~~ **Escrita y probada el mismo día** en
   tahan, hacia `/data/tmp` y con los CPT y el `metadata.py` nuevos montados encima de la
   imagen, sobre `j02_d20260926_t082036` y `npp_d20260926_t085610`: seis GeoTIFF por pasada
   (`rain_rate tpw clw tskin btemp_88v btemp_165h`, a 5 km) y vista de lluvia, agua
   precipitable y **165 GHz**. Iba a ser 88 GHz y no se lee: ATMS lo mide solo en vertical,
   sin la horizontal no se quita el fondo frío del mar, y el Golfo despejado salió a
   210-230 K, del color de la convección. A 165 el vapor tapa la superficie y solo colorea el
   hielo; los núcleos llegaron a 151 K. Las dos pasadas traían un ciclón al suroeste de
   Manzanillo, con la espiral en las tres vistas. Las paletas y el `product_map` están en
   LANOT_tools `7fc4022`, ya fijado como pin en el `.def` de Polar2Grid. **Para producción**:
   empujar LANOT_tools, `git pull` + `sudo ./install.sh` de LANOT_tools en tahan (los CPT
   van montados desde el host), recompilar `polar2grid_v3.2-mapdrawer.sif` (sin eso los
   JPG salen rotulados "NOAA-21 ATMS" sin producto) y reinstalar esta cadena.
3. ~~Engancharlo.~~ **Hecho el mismo día**: etapa `mirs` en el nivel 2 de
   `procesar_pasada.sh`, con su pasada por traslape sobre `GATMO` (probado en seco sobre
   `j02_d20260926_t082036` y `npp_d20260926_t071801`; en la de NPP HEAP no corre, sin CrIS,
   y MiRS sí). En `publicar_kawak.sh`, `vistas/mirs` → `kawak:/var/www/html/polar/jpss/atms`,
   de los tres satélites: no choca con nada de la cadena vieja. La carpeta ya existe en
   kawak; **falta que la página la muestre**.

   El rótulo del 165 GHz pasó de "165 GHz" a **"Convective Ice (165 GHz)"**, que dice qué se
   busca sin esconder qué se midió. En inglés, como todo `product_map`: **si los rótulos van
   en español se decide en la junta del lunes 2026-09-28**, y en ese caso se cambian todos
   de una vez. El renderizado de producción se verificó con la
   imagen recompilada (`7fc4022`) sobre la pasada de NOAA-21.

   Tropiezo de ese día: correr a mano los `run_*.sh` de operación con el usuario propio deja
   directorios nuevos en 755 y de su grupo —umask 022—, y `lanotadm` ya no puede escribir en
   ellos. Pasó con `geotiff/mirs` y `vistas/mirs`; se corrigió con `chgrp lanotadm` +
   `chmod 775`, y los dos quedaron en `preparar_servidor.sh`. Tampoco se puede reescribir un
   marcador de `lanotadm` (644): un `--force` a mano muere al final, sin daño pero sin resumen.
4. Después, evaluar el SND como segunda fuente de Skew-T: cubre NPP, que HEAP 3.0 dejó.

Quedó en tahan `/data/tmp/mirs_prueba` (bundle extraído, el `apptainer` sustituto y las
salidas de las dos pasadas): sirve para comparar contra el `.sif` y luego se borra.

---

## 2026-09-24: los dos primeros días en automático

**Funcionó lo que se quería probar**: los 15 crudos JPSS del 23 y el 24 tienen su pasada, el
barrido recogió solo una que llegó encimada (NOAA-20, 19:38 UTC del 24), la publicación en kawak
va con `fallos: 0`, salen Skew-T en cada pasada con sondeos y el cron de ancillary corre cada 6 h.
**La duda del CMCSST (plan, 0.2) queda contestada**: ATMOS salió bien todas las mañanas con el
de dos días antes. Pero hubo dos fallas sistemáticas, las dos corregidas el mismo día:

- **LSR falló en las 15 pasadas**: `Read-only file system: '/work_lsr_…'`. El driver crea su
  directorio de trabajo en el `pwd`, sin opción para moverlo, y desde el `cd /` de
  `procesar_pasada.sh` (`3a1b4c8`) el `pwd` es la raíz del contenedor. Era el único `run_*.sh`
  sin `--pwd`: ahora trabaja en `/data/tmp/lsr_work_<job>`, al lado del staging.
- **ATMOS no sacó nada en dos pasadas y la mitad de otra**, y una de ellas quedó marcada `ok`.
  Para un gránulo de las "09z" CSPP pide GFS válido a las 09 y a las 12: `t06z f003/f006` o
  `t00z f009/f012`. `atmos-anc` baja **solo f003–f009** de cada ciclo —probado con `-t` y una hora
  futura: no trae f012—, así que la única pareja es el ciclo 06Z, que se publica hacia las
  09:30 UTC y el cron no trae hasta las 12:17. Lo mismo a las 21 con el 18Z. Resultado:
  NOAA-21 09:17 del 23, `0 of 72`; NPP 21:05 del 23, `0 of 96`; y NOAA-21 08:58 del 24,
  **`24 of 96` con marcador**, porque solo los gránulos anteriores a las 09 tenían GFS.
  Con ATMOS caen también CRYO y LSR.

**La corrección** tiene tres partes:

1. `run_atmos_edr.sh` lee el `completed M products of N` de cada intento. Si `M < N` y el log
   dice que faltó ancillary, descarta lo producido y **reintenta descargando**. Si aun así
   falta, borra el parcial y sale en 1 sin marcador. Un parcial ya no se da por bueno.
2. `barrer_pendientes.sh` tiene una segunda tarea: las pasadas de las últimas 24 h con marcador
   de `p2g_l1` y sin ATMOS, LSR o CRYO se retoman con `procesar_pasada.sh --clave`, una por tic,
   con al menos 60 min entre intentos y tres intentos antes de rendirse
   (`state/reintentos/<clave>.fallido`).
3. `procesar_pasada.sh` pasa `--force` a `p2g_edr` cuando ATMOS, LSR o CRYO acaban de producir.
   Sin eso, al retomar una pasada el renderizado diría "ya estaba", porque ya tenía marcador de la
   primera vuelta.

Probado con `apptainer` y `procesar_pasada.sh` simulados; **falta verlo en tahan**. Al desplegar:

- El barrido va a retomar solo las pasadas de las últimas 24 h, que son todas sin LSR, una cada
  15 min. Las del 23 quedan fuera de la ventana: `REINTENTO_HORAS=48` en una corrida a mano.
- La de NOAA-21 del 24 a las 08:58 (`j02_d20260924_t085827`) tiene marcador de ATMOS con 24 de
  96 productos: **borrar el marcador y sus `JRR-*`** para que el barrido la retome completa.
- La prueba de fuego es la próxima pasada que caiga después de las 09 o las 21 UTC: en su log de
  ATMOS debe aparecer el segundo intento y, si el 06Z o el 18Z todavía no se publicaron, en
  `barrido.log` una línea `↻` una hora después.

**Desplegado y verificado esa misma tarde** (`d5723c0`). Se limpió a mano la pasada parcial —sus
24 productos y los marcadores de ATMOS y CRYO— y un barrido con `REINTENTO_HORAS=48` retomó
**16 pasadas, las 16 completas**, en 1h 50m: las 15 sin LSR más las dos de esa tarde procesadas
antes de instalar. Las tres de ATMOS quedaron en 72/72, 96/96 y 96/96, las tres **al primer
intento**, porque para entonces el cron ya había bajado esos ciclos: el reintento descargando
sigue sin verse en producción, y eso es lo que falta confirmar con la primera pasada después de
las 09 UTC.

### Lo que queda de estos dos días

- **Alerta de etapas que fallan seguido.** LSR falló en quince pasadas y el resumen de cada una
  lo decía; nadie lo vio hasta revisar a mano. Hace falta un aviso cuando una etapa falla en tres
  o más pasadas seguidas. Se decidió hacerlo dentro de un plan de monitoreo común con GOES y
  quizá GeoNetCast: **`docs/plan_monitoreo.md`** (eventos en JSON Lines con un esquema compartido;
  la alerta es la primera consulta sobre ellos).
- **"Más de 0 productos" no es éxito, en ningún EDR.** ATMOS ya exige `M = N`; CRYO, ACSPO, FIRE,
  OMPS y HEAP siguen dando por buena una corrida parcial. CRYO lo hizo el 24 sobre el ATMOS a
  medias (17 SDR, marcador escrito). Hay que ver en tahan qué dice cada driver al terminar
  —OMPS escribe `products of N`; de los otros no se sabe— y, donde no haya esa línea, comparar
  gránulos de salida contra los de entrada.
- **Hecho**: `--pwd` en ACSPO y ATMOS, los dos únicos que heredaban `/`. Funcionaban porque sus
  drivers escriben en `-W`, pero es la misma trampa que tumbó a LSR.

---

## Al retomar el 2026-09-23: ¿funcionó la automatización?

Primer día con todo en automático: recepción por stratus, cadena desde `/opt` como `lanotadm`,
barrido y publicación en cron. Qué mirar después de las pasadas de la mañana (07–09 UTC) y de la
tarde (19–21 UTC), en tahan:

- **Cada crudo JPSS tiene su pasada**: `cadena/<fecha>_recibe.log` contra los logs de pasada de
  `cadena/`, y el resumen de cada uno sin `fallo`. Las claves ya son por hora de inicio
  (`j02_d20260923_tHHMMSS`).
- **ATMOS en las de la mañana**: si sale bien, tolera un CMCSST de dos días; si cae con `Unable to
  find CMCSST`, ver la duda abierta en `plan_operacion_datawork.md` (0.2).
- **Skew-T**: en los logs de `polar2grid/` la sección `--- Skew-T ---`, y en el marcador de cada
  pasada con sondeos la línea `skewt: N diagramas, …`. Archivos nuevos en `vistas/sounder/skewt/`.
- **Barrido** (`cadena/barrido.log`): una línea cada 15 min. Si hubo dos pasadas encimadas, la
  segunda tiene que aparecer recogida ahí, sin intervención.
- **Publicación** (`cadena/publicar_kawak.log`): las vistas de NOAA-21, los sondeos y los Skew-T de
  las pasadas del día, con `fallos: 0`, y visibles en kawak.
- **`cadena/cron.log`**: las descargas de ancillary de las 06 y 18 UTC.

**Desplegado la misma noche**: imagen con LANOT_tools `931ed29` en `/opt/containers`, los 21
Skew-T del 22 regenerados (20 con LI; el que queda "n/d", CDMX 07:57, trae −999 de NUCAPS en CAPE
y LI) y subidos a kawak **por el cron de publicación**, sin intervención (21:27, 21 copiados,
0 fallos). Fue la primera prueba real de `publicar_kawak.sh`.

---

## 2026-09-22, noche: Skew-T en la cadena, el PR a satpy, y qué falta para jubilar la cadena vieja

### Skew-T de NUCAPS, de punta a punta

- **Imagen**: `polar2grid_v3.2-mapdrawer.def` compila MetaGráfica (`mg`, pin `MG_COMMIT`) y
  LANOT_tools trae `skewt`. El pin de LANOT_tools va en `931ed29`, con guardas en `%post` y
  `%test` para cada cosa que degrada en silencio. Recordatorio: `construir.sh` deja la imagen en
  `/opt/contenedores`, y la cadena la lee de `/opt/containers` — **copiarla**.
- **Sitios**: `config/sitios_skewt.tsv`, las 14 estaciones de radiosondeo del SMN que siguen
  reportando (catálogo IGRA2 de NCEI), para poder comparar contra el globo.
- **En la cadena**: `run_polar2grid_edr.sh` dibuja un Skew-T por sitio después de los mapas de
  sondeo, sobre los `NUCAPS-EDR` que ya tiene en su staging. SVG en `vistas/sounder/skewt/`,
  `<sat>_atms-cris_skewt_<omm>_<clave>_<AAAAMMDD_HHMMSS>.svg`. `skewt` sale con **3** cuando el
  sitio cae fuera de la franja o NUCAPS rechazó el perfil: se cuenta aparte, no es error. Con las
  tres pasadas del día salieron 21 de 42 combinaciones; eso es lo normal.
- **La figura** (LANOT_tools): el logo vectorial del LANOT a la izquierda del título (una struct,
  `logos/lanot_logo_struct.mg`, que el `.mg` generado incrusta), el satélite leído del atributo
  `platform` (antes NOAA-21 salía "NOAA"), y **el nivel de superficie aparte**: NUCAPS cierra el
  perfil con un nivel en la presión del suelo cuya temperatura arrastra la de la piel —sobre la
  CDMX, 25 °C con 14 °C 20 hPa arriba—; ahora se dibuja la línea del suelo con T y Td como puntos,
  y la parcela sale del primer nivel sobre él.
- **El Lifted Index salía "n/d" en todas**: `Stability` declara `valid_range = [0, 1e6]`, netCDF4
  lo aplica solo y borraba todo LI negativo. Corregido en `931ed29`; **falta recompilar** y
  regenerar las de hoy (la CDMX de las 19:09 debe dar −3.81 K).
- **kawak**: `jpss/sounder/` (al lado de `viirs/`, porque no es VIIRS) y `jpss/sounder/skewt/`.
  Hoy se copió a mano; también las vistas de NOAA-21, que la cadena vieja no procesa. NPP y
  NOAA-20 **no** se copian: se llaman igual en las dos cadenas y pisarían las de la vieja.

### El PR a satpy: pytroll/satpy#3480

Dave pidió el PR en el foro. Abierto el mismo día (`docs/pr_satpy_nucaps_cape_li.md`): los cinco
parches de CAPE y Lifted Index portados a `main`, más `get_shape` y el enmascarado en un método
aparte. CodeScene objetó el número de argumentos de ese método; corregido en un segundo commit.
Falta la revisión. Cuando llegue a Polar2Grid, se quitan del `.def` esos cinco y los dos de #3450.

### Condiciones para jubilar la cadena vieja

La cadena vieja son dos ramas y se apagan por separado: **JPSS** (`cspp.sh` y compañía, en
stratus) y **METOP** (`metop2.sh`, en tsom03). Aqua no entra en ninguna: ya no se procesa.

**JPSS se apaga cuando se cumpla todo esto:**

1. **Opera sola varios días** (criterio de la fase 0 del plan): ancillary renovado por cron, sin
   intervención, la segunda pasada del día de un satélite con OMPS y HEAP, y ningún crudo JPSS
   sin procesar al final del día. Hoy todavía hizo falta relanzar a mano la NOAA-20 de las 20:02.
2. **Dos pasadas encimadas no se pierden.** Ya sea la cola con dos turnos (0.7), ya sea el barrido
   en cron mientras tanto. Verificado con un par NPP / NOAA-20 real, incluidas las pruebas
   pendientes de 0.6 (puntos 6 y 7: dos satélites en la misma ventana de Level 2, y los cachés
   de ACSPO y Active Fire con dos corridas).
3. **Cubre todo lo que publica la vieja, o se decide dejarlo.** Hoy la cadena nueva tiene su
   equivalente de todo menos **AFAI** (índice de algas flotantes, `jpss/viirs/afai` en kawak), que
   no produce en operación. Hay que traerlo o decidir explícitamente que se deja. Las nubes
   cambian de producto (JRR en vez de CLAVR-x): eso es un cambio de producto, y se anuncia.

   **El AFAI histórico ya corre con nuestros contenedores** (verificado en tahan el 2026-09-26),
   así que traerlo es pasar a operación algo que existe, no empezar de cero. Lo hace urielm, para
   estudiar casos de sargazo: `/opt/lanot_shared/scripts/viirs_afai_{procesar_rango,geotiff,atmos}.sh`
   extrae los SDR de los tar de `/depot/polar/npp_jpss/viirs`, pide a
   `polar2grid_v3.2-mapdrawer.sif` M05, M07, M10 y los cuatro ángulos en `wgs84_geo_750m`, y saca
   la máscara de nubes con **copias** de `run_atmos_edr.sh` y `run_polar2grid_edr.sh`. Todo en
   `/data/tmp/viirs_afai_historico`. Tres cosas a tener en cuenta: **(a)** el índice en sí no lo
   calculan esos scripts, les entregan los GeoTIFF a otro equipo; **(b)** las copias son de
   mediados de agosto (6879e2f y d01d885) y no tienen el criterio `M = N` de ATMOS ni lo posterior;
   **(c)** `/opt/lanot_shared` depende de la interfaz de esos dos scripts y del `.sif` de
   Polar2Grid, así que un cambio ahí puede romperle el histórico.

   **Los quicklooks de ATMS, CrIS y OMPS se dejan, decidido el 2026-09-26.** Son lo que kawak
   sirve en `polar/npp-jpss1/{atms,cris,omps}` —symlinks a `/dataservice/npp-jpss1/<sensor>/vistas`—
   y no los hacemos: los genera `ql_sdr.sh` del bundle de CSPP SDR, que `cspp.sh` llama al
   terminar cada sensor. Son Level 1 en la geometría del barrido: los 22 canales de ATMS en
   temperatura de brillo, tres ventanas de CrIS (solo NOAA-20) y 13 canales del Nadir Mapper
   más 7 del Nadir Profiler de OMPS en radiancia (los del Profiler son una quincena de puntos
   sueltos: no se ve nada). Lo nuevo no los reemplaza uno a uno, porque es Level 2 —mapas de
   NUCAPS, Skew-T, ozono total—; lo único que se pierde de verdad es ATMS por canal. **Nadie los
   usa**: en los `access.log` de kawak del 2025-08-01 al 2026-09-26, de unos 8 300 accesos a esas
   carpetas, ~4 700 son rastreadores (GPTBot sobre todo), ~3 500 un escáner de vulnerabilidades
   y lo humano son cuatro direcciones —dos de la UNAM, una de LANOT y una doméstica— que abrieron
   **5 PNG en catorce meses**, todas entrando por el listado de Apache y ninguna desde una página
   del sitio. `nucaps/` está vacío desde 2022. Al apagar se pueden retirar los symlinks.
4. **Publica sola en kawak**, con las categorías de la página, sin pisar nada y a tiempo — hoy la
   copia es manual. Y **la página muestra lo nuevo**: `noaa21`, `sounder/` y los nombres de nube
   de JRR. Los mapas de sondeo de NOAA-20 existen en tahan pero no se publican, porque salen
   como `j01_atms-cris_…` y no `noaa20_…`: hay que corregir ese nombre antes de publicarlos.
5. **Si una pasada falla, alguien se entera.** El 22 de septiembre de 2025 un error de sintaxis en
   la recepción perdió siete pasadas sin más rastro que un log. Un aviso cuando un crudo JPSS
   llegue a `.fallido` (o a `fallidos/` con la cola), o cuando pase una ventana de pasadas sin
   ninguna procesada.

Cumplido eso: `copypolar.sh` deja de mandar JPSS a la cadena vieja de stratus y se desactiva
`cspp.sh`. Conviene conservar su instalación un par de semanas como vuelta atrás.

**METOP se apaga con la fase 4 del plan**: contenedor de Level 0 → Level 1 (AAPP y el
metopizer), renderizado de AVHRR y sondeos por `run_heap_edr.sh` con IASI/AMSU/MHS.

### Repartir las pasadas entre servidores, y el barrido

**Para mandar pasadas a otro servidor** hacen falta, en este orden:

1. **La cola** (0.7) con dos turnos en tahan: cada pasada espera un turno libre en vez de
   rechazarse.
2. **Las fases 1 y 2**: salidas, `state/`, estáticos y ancillary en `/datawork`. Sin eso, otro
   servidor no sabría qué quedó hecho ni tendría de dónde leer.
3. **Un segundo trabajador** (3a): stratus reinstalado con Rocky 9, Apptainer, los `.sif` y
   `lanotadm` con el mismo uid. Y stratus **solo se puede reinstalar después de apagar la rama JPSS
   vieja que corre en él** — por eso ese apagado va antes, solo con los dos turnos de tahan.

**¿Eso evitaría el barrido?** No lo elimina, pero lo saca del camino normal. Lo que evita que una
pasada encimada se quede esperando al barrido —lo que pasó hoy— es **la cola**, no el segundo
servidor: con turnos, la pasada que llega con todo ocupado se toma en cuanto uno se libera, aun
con un solo servidor. El segundo servidor da capacidad y relevo. Pero hay fallas que ninguna cola
ve, y para ellas el barrido sigue siendo la red de seguridad (en el plan pasa a ser
`trabajar.sh --barrer`):

- **Una señal que nunca llega**: la copia o el `ssh` desde polaracq fallan, o la recepción tiene
  un error como el de 2025. El crudo está en el buzón pero nadie lo encoló.
- **Un servidor que muere a media pasada**: su boleto deja de latir, y quien lo regresa a la cola
  es precisamente el barrido.
- **Los reintentos** de una pasada que falló por algo pasajero.

**Mientras llega la cola**, el barrido actual debería ir ya en cron (cada 15 min, con un
`--dry-run` antes para que no reprocese la historia del buzón). Eso habría recogido la NOAA-20 de
hoy sin intervención.

---

## 2026-09-22, tarde: la órbita dejó de identificar la pasada

Las pasadas de la tarde recorrieron solas los dos sistemas. En tahan:

- **NOAA-21 19:06 (`chain1-2_pass2`) y NPP 19:42 (`chain4-2_pass32`), completas**, 35 y 30 min.
  NOAA-21 de día **sí trae OMPS** (19 V8TOZ y 19 V8PRO), así que lo de "sin datos" era la noche;
  salen los RGB, y HEAP da las cinco familias. En NPP, HEAP queda `sin datos` (no hubo CrIS en la
  ventana) sin contar como fallo.
- **El aislamiento funciona**: `Manifiesto:` en cada log de RT-STPS, los `.rdr` en
  `state/rt-stps/` y ningún `rt_stps_*` en `/data/tmp`. Los logs de pasada salen limpios.
- **NOAA-20 20:15 (`chain2-3_pass13`) quedó sin procesar**: llegó con la de NPP en curso, salió
  con 75 y nadie la recoge porque el barrido no está en cron. Es el caso previsto; hay que
  relanzarla a mano.
- **El CrIS de NOAA-21 20:47 falló** (`SDR_PREREQ_ABSENT CRIS-SCIENCE-RDR`): ATMS y OMPS tienen un
  hueco de ~3 min a las 20:51, y con la ventana de ±4 gránulos de CrIS ningún tramo llegó a 9
  seguidos. Corte de recepción, no de la cadena.
- **El cron de ATMOS corrió a las 18:17 UTC** y no bajó nada nuevo (38 archivos antes y después).
- En stratus, el reenvío entregó los cinco crudos y la cadena vieja procesó NPP y NOAA-20. Sus
  logs quedan cruzados cuando dos pasadas se enciman (`clavrx_d20260922_t1942.log` lleva los
  productos de las 20:02 y al revés); los productos están bien. No se toca: esa cadena se apaga.

**Y la pasada de NOAA-21 de las 20:47 (`chain1-3_pass3`) no produjo nada de Level 2.** CSPP le
puso a sus SDR de VIIRS la órbita **`b20040`, la misma que a la de las 19:06**, aunque están
separadas exactamente por un periodo orbital. ATMS y OMPS del mismo crudo, con los mismos dos TLE,
sí dijeron `b20041`. Con la clave `j02_d20260922_b20040`, las diez etapas encontraron los
marcadores de la pasada anterior y salieron `ya estaba`; la ventana salió de 19:06 a 20:59, y un
`--force` tampoco servía, porque el glob por órbita habría metido las dos pasadas en el staging.
En `level1` de tahan es la única órbita repetida entre 12 pasadas de VIIRS; por qué la repite
CSPP sigue sin saberse.

**La clave ahora es la hora de inicio** (`j02_d20260922_t204743`), y los archivos de una pasada se
eligen **por tiempo**, no por un glob sobre la órbita. Todo vive en `scripts/pasadas.sh`, que
cargan los diez scripts de pasada y `procesar_pasada.sh`: una pasada es un grupo de SDR de
geolocalización del mismo satélite sin huecos de más de 20 min (`PASADA_HUECO_S`); dos sobrevuelos
del mismo satélite están a ~100 min, y un corte de recepción dura minutos. Además:

- Desaparecen diez copias de `clave_de_pasada`/`claves_disponibles`/`resolver_pasada`, y las
  ventanas que LSR, CRYO y el renderizado de Level 2 sacaban de **un** GMTCO representativo, que
  con SDR por gránulo daba una ventana de un gránulo.
- OMPS y HEAP se emparejan con `pasada_que_traslapa`, que ya no se queda con la órbita mayoritaria
  cuando la órbita cambia a media pasada: el grupo por tiempo la toma entera.
- `-p` y `--clave` siguen aceptando las claves viejas (`j01_d20260811_b45236`) y trozos como
  `b45236`; si la órbita la llevan dos pasadas, lo dicen y listan las dos claves nuevas.
- **Los marcadores viejos quedan huérfanos, y no importa**: el barrido decide por los de RT-STPS,
  que van por crudo, y ningún proceso automático vuelve sobre pasadas ya hechas. Rehacer una
  pasada vieja con `--clave` la procesa desde cero, que es lo que se pide al rehacerla.

Probado en bucefalo con un `level1` simulado con los nombres de hoy y un `apptainer` falso que
enseña el staging: cada uno de los diez scripts toma solo los archivos de las 20:47 (VIIRS, I,
M, OMPS, CrIS y ATMS con margen, JRR por ventana), la autoselección, las claves viejas —ambigua
y no ambigua—, `procesar_pasada.sh --dry-run --clave` y la entrada por crudo con manifiestos.
En tahan, solo lectura: `listar_pasadas` sobre los `level1` reales da 12 pasadas de VIIRS, 9 de
OMPS y 8 de CrIS en ~5 ms cada uno. **Falta**: instalar y relanzar la pasada de las 20:47 con
`procesar_pasada.sh --clave t2047`.

---

## 2026-09-22: cada pasada, aislada de las demás

Con esto dos pasadas pueden correr a la vez sin pisarse, que es el prerrequisito de la cola con
turnos (plan, 0.6, puntos 1, 2, 3 y 5):

- **`run_rt_stps.sh` ya no escribe en `level0`.** Trabaja en `/data/tmp/rt_stps_<sello>/salida`,
  cuenta ahí —sin `find -newer`, porque el directorio es suyo—, entrega a `level0` y deja la
  lista de sus RDR en `state/rt-stps/<crudo>.rdr`. Antes, con otra RT-STPS corriendo, un crudo
  corrupto quedaba `.done` gracias a los RDR ajenos.
- **`run_sdr.sh` deja su propia lista** en `state/cspp-sdr/<rdr>.prod`.
- **`procesar_pasada.sh` lee las dos**: a qué RDR llamar al SDR, y de qué `GMTCO` sacar la clave.
  **La clave NO puede salir del RDR**, como decía el plan: los RDR traen la órbita que les pone
  RT-STPS, que en NOAA-21 es `b00001`; la real la calcula CSPP con el TLE y solo está en los SDR.
- **HEAP corre de uno en uno**, con `flock` sobre `$HOST_HEAP_HOME/.candado` (espera 1 h,
  `HEAP_ESPERA`): su bundle es escribible y compartido.
- Una pasada decodificada antes de este cambio no tiene manifiesto; `procesar_pasada.sh` lo dice
  y sugiere `--force` o `--clave` en vez de fallar de forma opaca.

Probado en bucefalo con un `apptainer` simulado: dos pasadas (NOAA-20 y NOAA-21) lanzadas a la vez
sobre los mismos directorios, cada una con su clave (`b45500` y `b20033`); el candado de HEAP con
dos corridas, una esperando y otra venciendo su plazo. **Falta en tahan**: los puntos 6 y 7 del
plan —`de_otro_satelite()` con dos satélites en la misma ventana, y los cachés de ACSPO y Active
Fire con dos corridas a la vez.

---

## Al retomar la tarde del 2026-09-22

Todo quedó listo para que las pasadas JPSS de la tarde (~19–21 UTC) recorran solas los dos
sistemas. Qué mirar en cada una:

- **stratus**: `~/log/reenvio_polar.log` —la copia al buzón y el aviso a tahan— y
  `~/log2/<crudo>.log`, `cspp.sh` de la cadena vieja con los patrones nuevos (`chain2` NOAA-20,
  `chain4` NPP).
- **tahan**: `cadena/<fecha>_recibe.log` y el log de la pasada, que ahora debe salir limpio (sin
  bloques repetidos).
- **NOAA-21 de día**: que OMPS traiga datos (de noche quedaba `sin datos`) y que salgan los RGB.
- **La segunda pasada de NOAA-20 del día**: que OMPS y HEAP ya no aborten por ambigüedad.
- **Dos pasadas encimadas**: con un solo turno, la segunda sale con 75 y **nadie la recoge**,
  porque el barrido no está en cron. Si pasa, relanzarla a mano.
- **Aislamiento** (instalado antes de la tanda, `489a1bb`): la línea `Manifiesto:` en el log de
  RT-STPS, `state/rt-stps/<crudo>.rdr` con los RDR de esa pasada, y `/data/tmp` sin
  `rt_stps_*` al terminar. Con dos pasadas seguidas, que cada una use su clave.
- **Cron**: `cadena/cron.log` a las 18:17 CST, primera descarga automática de ATMOS.
- **Mañana 07–09 UTC**: ATMOS en las pasadas de la mañana decide si alcanza un CMCSST de dos días
  (plan, 0.2).

Estado del despliegue: `/opt/lanot/polares` en `6ee3fa0`, cron de ancillary instalado, METOP ya se
procesa otra vez en la cadena vieja (probado a mano con `chain6-4_pass54`, vistas publicadas).

---

## 2026-09-22: llegó NOAA-21, y TeraScan reasignó todas las cadenas

El 2026-09-21, entre las 20:34 y las 22:36 UTC, polaracq empezó a recibir NOAA-21 y **cambió qué
satélite llega por cada `chainN`**: NOAA-21 es `chain1`, NOAA-20 `chain2`, NPP `chain4`, Aqua
`chain5` y METOP `chain6`. La tabla completa y de dónde sale están en
`plan_operacion_datawork.md` ("Qué satélite es cada `chain`").

- **El mapeo vive ahora en `config/cadenas.tsv`**, que leen `recibe.sh`, `run_rt_stps.sh` y
  `barrer_pendientes.sh` a través de `scripts/cadenas.sh`. Con las expresiones regulares de
  antes, la cadena nueva habría mandado METOP a RT-STPS como NOAA-20 y NOAA-20 como NPP, y no
  habría tomado ni NPP ni NOAA-21. Cada fila lleva desde cuándo vale, porque en el buzón
  conviven crudos de los dos esquemas con los mismos nombres.
- **`recibe.sh` ya no invoca a `noaa2` ni a `metop2.sh`**: lo que no es JPSS se registra y sale
  en 0, como pide el plan (0.4). Esos crudos los sigue enrutando el `recibe.sh` de stratus.
  Acepta también el nombre sin ruta y lo busca en el buzón.
- **El barrido ya hace lo de 0.5**: filtra por la tabla y los marcadores solo cuentan si son
  más nuevos que el crudo.
- Probado en bucefalo con crudos simulados de los dos esquemas (`recibe.sh` con un
  `procesar_pasada.sh` falso, y el barrido en `--dry-run` y en real). **Falta la prueba en
  tahan con crudos reales de cada JPSS.**
- **Primera pasada de NOAA-21, en tahan el mismo día** (`chain1-1_pass1`, 07:55 UTC, nocturna),
  entrando por `recibe.sh` con el nombre suelto: clave `j02_d20260922_b20033`, 22 minutos.
  - **RT-STPS con `jpss2.xml` funciona**: RDR de VIIRS, ATMS, CrIS y el diario suelto
    (`RNSCA_j02_…`). Los RDR salen con órbita `b00001`, pero los SDR la llevan real (`b20033`),
    porque la calcula CSPP con el TLE: la clave de pasada no se afecta.
  - **SDR** 20/20 de ATMS y 10/10 de VIIRS con las LUTs de `j02`, y CrIS completo.
  - **HEAP sale completo a la primera con datos propios**: las cinco familias, 16 de cada una,
    `NUCAPS-EDR` incluido, con la traducción `j02` → `n21`.
  - ACSPO 1, Fire 10 y P2G_L1 43 GeoTIFF + la vista DNB (sin RGB: es de noche). Flood, sin
    productos por la misma razón.
  - **ATMOS falla por falta de CMCSST** del día: `update_atmos_ancillary.sh` nunca se ha
    corrido (plan, 0.2). Con él caen LSR y CRYO. Corrido el updater —que baja el CMCSST del día
    anterior, porque el del mismo día no está publicado todavía— y relanzada la pasada con
    `--clave`: ATMOS 120 productos, CRYO 20 (primera vez con NOAA-21) y LSR 10.
  - **LSR no falla de noche, contra lo que decía el resumen de `procesar_pasada.sh`.** Termina
    bien y escribe sus `.nc`, pero NDVI y EVI salen sin un solo píxel válido, igual que el AOD
    de ATMOS; `vestir()` los descarta con el código 3 y no publica vista. Se quitó el
    recordatorio, que habría hecho pasar por esperado un fallo real de LSR.
  - La primera corrida del updater se cortó a la mitad sin dejar rastro en su log (sin
    `terminó con código` ni resumen): la terminal que lo lanzó se interrumpió. Relanzado con
    `nohup`, completó. Para el cron no importa, pero al correrlo a mano, en segundo plano.
  - **OMPS: el crudo no trae un solo paquete de OMPS** (`Packets Output=0` en los 16 APID). Lo
    más probable es que sea por la noche: los sensores nadir miden luz solar retrodispersada, y
    todas las pruebas de OMPS con NOAA-20 fueron vespertinas. Falta confirmarlo con una pasada
    diurna de NOAA-21.
  - **Resuelto el mismo día, junto con la clave truncada** (plan, 0.6, punto 4).
    `procesar_pasada.sh` ya no les pasa `j02_d20260922` a OMPS y HEAP: saca la ventana de VIIRS
    de todos los `GMTCO` de la pasada y elige la de OMPS y la de CrIS como la clave de los
    `GOTCO`/`GCRSO` **del mismo satélite que se traslapan con ella**, que se pasa completa. Sin
    traslape la etapa no se lanza y el resumen la marca `sin datos`, que no cuenta como fallo:
    es OMPS en cada pasada nocturna. Si se traslapan dos órbitas —puede cambiar a media pasada,
    al cruzar el ecuador— gana la que más archivos aporta, y se avisa. Desapareció
    `marcador_reciente()`: con la clave completa, el marcador se nombra de antemano. Probado en
    bucefalo con `--dry-run` sobre un `level1` simulado: dos pasadas de NOAA-21 el mismo día (la
    nocturna sin OMPS, la diurna con OMPS en otra órbita), NPP a la misma hora y OMPS del día
    anterior, que no se cuelan. **Falta verlo en tahan** con la segunda pasada del día de un
    satélite.
  - El crudo pesa el doble que uno de NOAA-20 de la misma duración (2.4 GB, 11 884 líneas), sin
    que se note en los productos. Sigue sin explicación.
  - **El log de la pasada salía con bloques repetidos y líneas cortadas**: `recibe.sh` redirigía
    la salida de `procesar_pasada.sh` a un archivo con el mismo nombre que el log que ésta abre
    (mismo sello, mismo crudo), y dos escritores se pisaban. Corregido: sin terminal,
    `procesar_pasada.sh` escribe solo a su log, y `recibe.sh` manda lo demás a su log diario.
- **La cadena vieja de stratus no se ajustó** y sigue con el esquema anterior. Por decisión de
  Alejandro, lo que se haga aquí será lo primero que pruebe las cadenas nuevas.

### El despliegue para operar sola

Discutido el mismo día: la cadena se instala en **`/opt/lanot/polares`** con
`sudo ./scripts/instalar.sh`, como ya estaba diseñado, y corre ahí como `lanotadm`; el clon queda
para desarrollar y probar. `/opt/lanot_shared`, que existe en los servidores, es de pruebas de
otra persona y no tiene que ver. Cambios para que `instalar.sh` sirva de verdad, que nunca se
había usado:

- **Espera a la pasada en curso**: toma el candado de `procesar_pasada.sh` con `flock -w` (45 min,
  `INSTALAR_ESPERA`). Instalar a media pasada no rompe el script que corre, pero dejaría la pasada
  hecha con dos versiones, porque cada etapa invoca su `run_*.sh` de nuevo.
- **Comprueba `config/cadenas.tsv`** además de `grid.yaml`.
- **Ya no sugiere el enlace en `~lanotadm/bin`**, que contradecía el plan (0.1).
- **`update_sdr_daily.sh` y `update_atmos_ancillary.sh` trabajan en un directorio propio** bajo
  `/data/tmp`: heredaban el `pwd`, que desde cron sería el `$HOME` de `lanotadm` (el log del
  updater de ATMOS decía `work dir : /home/aguilars/LANOT_procesamiento_polar`).

Probado en bucefalo con `PREFIX` temporal, un candado tomado y un `apptainer` simulado.

**Hecho en tahan el mismo día**: instalado en `/opt/lanot/polares` (commit `f8b9f6f`), los tres
`update_*.sh` corridos a mano como `lanotadm` y **el cron de ancillary instalado** (plan, 0.2, con
horas alineadas a las pasadas). Además, **stratus reenvía cada crudo a tahan**: su `recibe.sh`
(`referencia/recepcion/`) lo copia al buzón de `/datawork` con nombre único y llama por `ssh` al
`recibe.sh` de `/opt`. La llave de `lanotadm@stratus` no entraba porque `/home/lanotadm` en tahan
tenía `g+w` (`sshd` con `StrictModes` la ignora; se arregló con `chmod g-w`). Pendiente: ver
llegar la primera pasada por ese camino, y ATMOS en las pasadas de la mañana del 23 (el CMCSST,
plan 0.2).

---

## 2026-09-14: `/datawork` listo, y el plan para operar sobre él

`/datawork` quedó armado como disco compartido por NFS entre servidores. El diseño para
aprovecharlo —automatizar el ciclo de la antena a las vistas, procesar dos pasadas a la vez y
que otro servidor pueda tomar el trabajo— está en **`plan_operacion_datawork.md`**, acordado y
sin implementar. Lo esencial:

- **Salidas, `state/`, estáticos y ancillary pasan a `/datawork`**; temporales, `.sif`, logs y
  código se quedan en cada servidor.
- **Una cola en `/datawork/input/polar/` con turnos por servidor** sustituye al candado global.
  tahan tiene dos turnos desde la fase 0; stratus se suma después de reinstalarlo. No hace falta
  IP virtual.
- **polaracq pasa a la red 172** y copia los crudos al buzón con nombre único, avisando por
  evento. El barrido queda como red de seguridad.
- **Slurm:** el plan institucional del clúster lo pone en 2027, con la cadena polar como piloto.
  La cola es la vuelta atrás que ese plan pide conservar.

### Dos bugs que ya afectan a la operación en serie

Salieron al revisar el diseño y no esperan a la cola:

1. ~~**OMPS y HEAP fallan desde la segunda pasada del día de un mismo satélite.**~~
   **Resuelto el 2026-09-22** (ver la sección de ese día).
   `procesar_pasada.sh` les pasa la clave truncada (`j01_d20260914`), y `resolver_pasada()`
   sale con 1 si coincide más de una pasada (`run_omps_edr.sh:197`, `run_heap_edr.sh:437`).
   NOAA-20 tiene 2 o 3 pasadas diarias, y ninguna prueba tuvo dos del mismo satélite el mismo
   día. Como el barrido solo reintenta crudos sin `.done`, esas pasadas se quedan sin ozono ni
   sondeos. Arreglo: elegir por traslape temporal con VIIRS (plan, 0.6, punto 4).
2. **El barrido no resiste los nombres reciclados.** El passdisk usa 60 nombres
   (`chainN-M_passNM`) que se repiten continuamente, y `barrer_pendientes.sh:125-126` salta
   cualquier crudo con `.done`, aunque sea de un sobrevuelo anterior, y un `.fallido` bloquea la
   ranura para siempre. `run_rt_stps.sh:237` sí lo previó, con `-nt`. Arreglo en el plan, 0.5.

### Lo que se aprendió de la recepción

- **La cadena de recepción** está en `referencia/recepcion/watchpolar/`: `inotifywait` sobre el
  passdisk de TeraScan en polaracq → `copypolar.sh` (`scp` y `ssh`) → el `recibe.sh` de stratus.
- **Qué satélite es cada `chain`**, cruzando con `referencia/lspass.txt`:
  - activas: 1 Aqua, 2 NPP, 5 METOP-B/C y 6 NOAA-20;
  - sin uso desde abril de 2025: 3 (NPP) y 7 (NOAA-20);
  - sin uso desde agosto de 2025: 4 (NOAA-15/19).

  TeraScan ya ha movido satélites de cadena.
- **El log de producción** registra 7 022 envíos, ninguno doble, con 12 s de latencia media. Pero
  **el 22 de septiembre de 2025 un error de sintaxis en el `recibe.sh` de stratus dejó sin
  procesar siete pasadas en ~9 horas**, sin más rastro que ese log.
- **Los crudos polares no se archivan en ningún lado**, y en stratus cada pasada sobrescribe a la
  anterior de su ranura.

---

## Al retomar el lunes 2026-08-31, en `lanot7`

La sesión del 29 cerró con el trabajo mudándose a una máquina llamada **`lanot7`**,
de la que no se dijo qué papel cumple. **Antes de dar por buena ninguna ruta,
comprobarlo**: `id`, `/etc/os-release`, y si existen `/data/cspp`,
`/opt/containers`, `/opt/contenedores`, `/data/opt` y el clon. Esta sesión perdió
tiempo dos veces por deducir el sistema de un servidor en lugar de medirlo.

### Lo que está a medio camino, en orden

1. ~~**Publicar las dos respuestas del foro.**~~ **Hecho el 2026-08-31**: las
   dos se publicaron casi sin cambios, desde `docs/respuesta_*.bbcode` (ver
   abajo por qué no desde el `.md`). CIMSS ya sabe que el fallo era nuestro y
   que puede dejar de buscarlo.
2. ~~**Recompilar `polar2grid_v3.2-mapdrawer.sif`.**~~ **Hecho**: el `%test` de la imagen del
   2026-09-22 lista los siete parches en su sitio. Los parches de CAPE y Lifted
   Index están escritos y probados pero **no están en ninguna imagen**. El
   mecanismo cambió: ya no son `sed` en el `.def` sino
   `contenedores/parches/aplicar_parches_satpy.py`, que `construir.sh` copia al
   directorio de compilación.
3. ~~**Verificar los permisos finales del bundle de HEAP.**~~ **Hecho**: el 2026-09-22 HEAP
   corrió como `lanotadm` en tres pasadas y dio las cinco familias. La corrida buena se
   hizo con `a+rwX`; después se afinó a `go-w,g+w` y **desde entonces no ha
   vuelto a correr HEAP**. Debería bastar —el usuario está en el grupo
   `lanotadm`— pero está sin comprobar:
   `HEAP_OPTS=--noclean ./scripts/run_heap_edr.sh -p <clave> --force`.
4. **CAPE y Lifted Index hasta la vista.** Falta decidir los rangos de las dos
   paletas, y con eso: las CPT, las entradas de `product_map` y el bloque en
   `run_polar2grid_edr.sh`. El plan detallado está en
   `~/lanot/LANOT_tools/docs/plan_cape_lifted_index.md` — **sin commitear**, que
   es otro repositorio. Ojo al medir los rangos: hasta `931ed29` el LI negativo se
   perdía al leerlo con netCDF4 (el `valid_range` de `Stability`); con satpy no.
5. ~~**Una pasada completa con los trece eslabones**~~. **Hecho el 2026-09-22**: NOAA-21 19:06 y
   NOAA-20 20:02 salieron con todas las etapas en `ok`, HEAP incluido.
6. **El PR a `pytroll/satpy`** con los cinco parches nuestros (`column_index`,
   `extra_fill_values`, la precedencia de `units` y las dos entradas del YAML).
   **Preparado el 2026-09-22**, después de que Dave lo pidiera en el foro: rama
   `nucaps-cape-lifted-index` en `~/lanot/satpy`, cuerpo y pasos para abrirlo en
   `docs/pr_satpy_nucaps_cape_li.md`. **Abierto el mismo día: pytroll/satpy#3480.**
   Falta la revisión; al llegar a Polar2Grid, quitar los cinco parches del `.def`.
7. **Adoptar `lanotadm`**: `instalar.sh`, el `chown -R` de barrido y el cron.
   **Casi todo hecho**: la cadena corre desde `/opt/lanot/polares` como `lanotadm` y el cron de
   ancillary está instalado. **Falta el barrido en cron** (ver la sección del 22 en la noche).

### El foro de SSEC es phpBB: se pega BBCode, no Markdown

Los `docs/reporte_*.md` son la fuente en Markdown, pero **eso no es lo que se pega
en el foro**. `forums.ssec.wisc.edu` corre phpBB (prosilver, `viewtopic.php?t=`),
que nunca ha soportado Markdown. Los dos mensajes del 2026-08-24 sí se convirtieron
a BBCode antes de publicarlos, pero la versión convertida no se guardó y hubo que
reconstruir la regla leyendo el HTML de lo publicado (2026-08-31). Ahora sí queda
versionada, en `docs/respuesta_*.bbcode`, que son **carga útil pura**: seleccionar
todo y pegar.

La conversión, tal como se hizo:

| Markdown | phpBB |
|---|---|
| `## Encabezado` | `[b]Encabezado[/b]` — no hay encabezados |
| `**negrita**`, `*cursiva*` | `[b]…[/b]`, `[i]…[/i]` |
| ` ```bash … ``` ` | `[code]…[/code]` |
| `` `código en línea` `` | **se quitan los backticks**; no hay `[c]` |
| `- ítem` / `1. ítem` | `[list]` / `[list=1]` con `[*]` |
| `[texto](url)` | `[url=url]texto[/url]` |
| tabla | texto alineado dentro de un `[code]` — phpBB no tiene tablas |

Y una que no es de etiquetas: **los párrafos van en una sola línea**. phpBB
convierte cada salto en un `<br>`, así que el corte a 95 columnas del Markdown
saldría dentado. Se comprueba contando los `<br>` de lo publicado: 27 en el hilo
60121, que son los párrafos, no las líneas.

Al pegar, revisar la pestaña **Options** del formulario: si *Disable BBCode* quedó
marcada, ni el BBCode bien escrito se renderiza.

### Lo que se puede borrar cuando toque

- `scripts/diagnostico_heap_cimss.sh`, en cuanto se cierre el hilo con CIMSS: se
  escribió para responder «¿es el contenedor?» y esa pregunta ya está contestada
  por otra vía.

### Sin prisa

- Tres pasadas viejas (`20260508`, `20260811`, `20260814`) no tienen GeoTIFF de
  incendios, y **no es por el bug del sello** —se comprobó—: se renderizaron
  antes de que existiera el bloque. Un `--force` las recupera si se quieren.
- El **Skew-T** de los sondeos: producto nuevo, no encaja en el flujo
  `geotiff → vestir()` y necesita una lista de sitios. Decidido hacerlo con PIL
  y sin matplotlib. Anotado al final del plan de LANOT_tools.

---

## Dónde quedó el 2026-08-29 (cierre de la sesión)

**El parche de `nucaps` está en producción y la cadena entera se revalidó con él.** SSEC
contestó el reporte y mergeó [pytroll/satpy#3450](https://github.com/pytroll/satpy/pull/3450)
(ver pendiente 3, cerrado); `polar2grid_v3.2-mapdrawer.def` lo aplica en el `%post` hasta que
llegue Polar2Grid 3.3. La imagen se recompiló y se instaló en `/opt/containers`.

### Segunda corrida de punta a punta — `j01_d20260828_b45477`

NOAA-20, 19:30Z del 28, **33m 29s**, las quince etapas en `ok`. Es la primera pasada completa
con la imagen parcheada, y sirvió de prueba de no-regresión de la recompilación entera —que es
donde estaba el riesgo real, porque el `%post` reinstala GDAL y reclona LANOT_tools.

| Etapa | 2026-08-17 | 2026-08-29 |
|---|---|---|
| `rt_stps` | — | 2m 51s · 5 RDR |
| `sdr` viirs | — · 28 | 8m 47s · 28 |
| `sdr` atms | — · 63 | 1m 16s · 63 |
| `sdr` cris | — · 32 | 3m 06s · 30 |
| `sdr` omps-nm / -np | — · 38 / 40 | 1m 20s / 44s · 38 / 38 |
| `atmos` | 6m 57s · 108 | 8m 29s · 120 |
| `acspo` | 1m 31s · 1 | 2m 37s · 1 |
| `fire` | 2m 44s · 9 | 2m 55s · 10 |
| `flood` | 4m 36s · 9 + 1 tif | 4m 46s · 10 + 1 tif |
| `omps` | 28s · 38 | 1m 35s · 38 (19 V8TOz + 19 V8PRO) |
| `p2g_l1` | 3m 14s · **59 geotiff, 3 vistas** | 4m 17s · **59 geotiff (M 36, I 14, dnb 7, rgb 2), 3 vistas** |
| `lsr` | 1m 34s · 9 | 1m 38s · 10 |
| `cryo` | 19s · 18 | 21s · 20 |
| `p2g_edr` | 3m 22s · 26 geotiff, 11 vistas | 3m 52s · 27 geotiff (atmos 9, lsr 14, sst 1, fire 3), 12 vistas |
| **total** | **29m 04s** | **33m 29s** |

**Level 1 es la comparación que vale**, porque son bandas fijas y no dependen de la escena:
59 geotiff con el mismo desglose y 3 vistas, idéntico a la referencia. Los conteos de Level 2
**no son comparables**: la escena es otra y ATMOS entregó 120 productos contra 108, de ahí que
salgan 27 GeoTIFF y no 26.

**Las duraciones subieron ~20-70 % y no es del parche.** La prueba está en las etapas que ni
siquiera tocan la imagen de Polar2Grid: `acspo` 1m 31s → 2m 37s y `omps` 28s → 1m 35s corren en
sus propios contenedores CSPP. Lo que se movió es la máquina o el volumen de datos, no el
software; `p2g_l1` subió en la misma proporción que las demás.

### Tercera corrida: S-NPP, y el bug que destapó — `npp_d20260829_b76888`

Primer sobrevuelo de S-NPP que pasa por la cadena nueva de punta a punta (todas las corridas
anteriores son `j01`). 24m 20s, las catorce etapas en `ok`.

**Lo que se confirmó:** `p2g_l1` dio **59 geotiff (M 36, I 14, dnb 7, rgb 2) y 3 vistas**,
clavado a NOAA-20 — la cadena de Level 1 trata a NPP igual. La clave `npp_d…` se resolvió de
punta a punta y `metadata.py` rotula las vistas como "Suomi NPP".

**CrIS no llegó**: 4 RDR en vez de 5, con `atms`, `omps_np`, `omps_nm` y `viirs`. Es uno de los
sensores caídos de S-NPP, que además se da de baja en noviembre de 2026. Los demás conteos
bajos son escena y no fallo: 8 gránulos contra 10, y en esa proporción salen atmos 96, lsr 8,
flood 8, cryo 16 y fire 8.

**Y el hallazgo, que valía la corrida entera:** `fire=0 geotiff` con los 8 `.nc` escritos en
`level2/fires`. No era del renderizado sino del staging —`FIRE: 0 productos en la ventana`— y
la causa es el campo de creación del nombre ganándole al de observación. Está en los hallazgos
y ya corregido. Es un bug de **operación**, no de NPP: se habría comido los incendios de todas
las pasadas en cuanto la cadena procesara en el día, y en silencio.

**Verificado en tahan con el arreglo puesto**, re-renderizando la misma pasada: `FIRE: 8
productos en la ventana` y `fire=3 geotiff, 1 vistas`. La pasada pasa de 24 geotiff y 11 vistas
a **27 y 12**, que son exactamente los números de NOAA-20 del 28, sección por sección. O sea
que con el sello arreglado los dos satélites entregan el mismo inventario.

### Cuarta corrida: en caliente, que es donde el bug habría vivido — `j01_d20260829_b45492`

La confirmación que faltaba. NOAA-20 observado a las 19:11Z del 29 y procesado a las 20:14Z
**del mismo día** —los RDR llevan `_c20260829201430…`—, o sea la configuración exacta que
dejaba los AFIMG fuera de la ventana. Resultado: `FIRE: 9 productos en la ventana` y
`fire=3 geotiff, 1 vistas`. Sin el arreglo habrían sido 0.

Es la primera pasada que la cadena procesa **en caliente**, como en operación, y salió en
29m 46s con las quince etapas en `ok`. Dos cosas más que deja:

- `p2g_l1` en **59 geotiff (M 36, I 14, dnb 7, rgb 2) y 3 vistas** por tercera vez seguida y
  con dos satélites distintos. Ese número ya es una referencia sólida.
- **Los 33m 29s de la pasada del 28 eran ruido de la máquina.** Esta corrida queda en 29m 46s,
  a un minuto de los 29m 04s del 17, lo que confirma por otra vía lo que se había deducido de
  que `acspo` y `omps` —que no tocan la imagen de Polar2Grid— hubieran subido igual.

Un matiz sobre lo que esta corrida **no** probó: el filtro `de_otro_satelite()` seguía sin
ejercitarse de verdad. Los productos de NOAA-20 en esos directorios son del 28 y los de NPP del
29, así que la ventana temporal ya los separa sola. Haría falta que dos satélites cayeran en la
misma ventana.

### La no-regresión de Level 2, y el método que NO sirve

Se re-renderizó la misma pasada con la imagen anterior (guardada como
`/opt/contenedores/polar2grid_v3.2-mapdrawer.sif.pre3450`) hacia `/data/tmp/ab/viejo`, usando
`P2G_CONTAINER` + `P2G_GEOTIFF`/`P2G_VISTAS`/`P2G_STATE_DIR` para no tocar el árbol de
productos. Resultado: **los 27 GeoTIFF con checksum idéntico**, más los mismos conteos y el
mismo desglose.

Pero el primer intento se hizo con `cmp` y salió con **doce archivos "distintos"**, lo que
costó un desvío. Lo que lo aclaró fue el experimento de control —la imagen nueva contra sí
misma—, que dio **quince "distintos", y no los mismos doce**. O sea que la lista cambia de
corrida en corrida. Está en los hallazgos, abajo; el método bueno es
`gdalinfo -checksum`.

### El parche, probado por dos caminos

**En tahan, de punta a punta.** Los 19 gránulos `NUCAPS-EDR_v3r2_n21` de la muestra de CSPP
Sounder QL, pidiendo los cuatro de temperatura **más** `H2O_MR_853mb`: la misma llamada que el
2026-08-17 moría con `KeyError: 'H2O_MR/attr/valid_range'` sin dejar un solo archivo ahora
termina en `SUCCESS` con **5 GeoTIFF**.

Y el vapor sale sano, que era la duda que quedaba: sin `valid_range` **no se aplica el recorte
por `valid_max`** —solo se quita el `_FillValue`—, así que cabía esperar extremos disparatados.
No los hay: `H2O_MR_853mb` da **0.001 a 0.018 g/g, media 0.010** (1 a 18 g/kg, media 10), que
es razón de mezcla física para 853 hPa sobre México, y ese mínimo y ese máximo son los extremos
reales del campo. Una CPT de 0 a 20 g/kg cubriría la escena, si algún día se publica vapor.

**En bucéfalo, a nivel de lector, sin gránulos ni contenedor.** El bundle extraído en
`/data/cspp` trae la suite de tests de Satpy, y los del lector `nucaps` son `unittest.TestCase`
puro, así que corren con el intérprete del propio bundle —el mismo Satpy que viaja dentro del
`.sif`—. Con el `test_nucaps.py` del PR (merge `db2bf48`), que fabrica el caso poniendo `H2O`
sin `valid_range`:

| | test del bundle | test del PR |
|---|---|---|
| `nucaps.py` sin parche | 22/22 OK | **2 errores** |
| `nucaps.py` parcheado | 22/22 OK | 22/22 OK |

Dos cosas que salieron de ahí. **(a)** Los dos que fallan son `test_load_pressure_based`, uno
por lector, y el traceback confirma el mecanismo de forma independiente: no revienta en el
`valid_range` sino después, en `_mask_data_below_surface_pressure`, con
`KeyError: "No dataset matching 'DataQuery(name='H2O')' found"` — buscando un producto que
nunca se cargó. Es el segundo bug, el que el reporte no había identificado. **(b)** El test que
viene **dentro del bundle pasa con y sin parche**, o sea que no sirve como comprobación; por eso
el `%test` del `.def` verifica el contenido del módulo por `inspect` en lugar de correr la
suite. (Receta, por si hace falta repetirlo: `pip install --target` de `pytest` en un directorio
aparte —el bundle no lo trae y no hay que tocarlo—, una copia del árbol `satpy` hecha con
`cp -rs` para poder sustituir un solo archivo, y `PYTHONPATH` delante.)

### HEAP: la causa era nuestra, y era el sistema de archivos de solo lectura

**El fallo de los sondeos no era de CIMSS.** Se encontró el 2026-08-29 haciendo lo que kathys
pidió —correr con `--noclean`—, que es lo que por primera vez conservó los logs internos de
cada módulo. En `TMP_*/swath_001/granule_001/HEAP_Retrieval.log`:

```
At line 330 of file read_nl.F (unit = 40)
Fortran runtime error: Cannot open file 'fort.40': Read-only file system
FATAL: Error in HEAP_Retrieval.pl: Error running airsb103.exe
```

`airsb103.exe` abre una unidad Fortran sin nombre dentro del árbol de instalación. Con el
bundle dentro del `.sif`, que es de solo lectura, muere ahí; eso aborta `HEAP_Retrieval.pl` y
con él los conversores a NetCDF, así que no salen `NUCAPS-EDR` ni `NUCAPS-CCR-AR` — el `OLR`
sobrevive porque lo escribe `main_cris_olr`. Y el wrapper se traga el error: código 0,
`EXECUTION COMPLETED SUCCESSFULLY`, 40 s en vez de 2 min.

**La prueba llegó antes que la explicación:** el mismo `.sif`, con el bundle montado desde
`/data/tmp` en vez de instalado dentro, entrega **las cinco familias** —16 `NUCAPS-EDR`, 16
`NUCAPS-CCR-AR`, 16 `NUCAPS-CCR`, 16 `NUCAPS-ALL-HR`, 16 `NUCAPS-OLR`— en 1m 59s, dentro del
rango que declara §3.3.

Se descartaron por el camino, y conviene que conste para no repetirlas: el sistema operativo
(el host es Rocky 10.2 y los binarios ni cargan fuera del contenedor, así que el experimento
que pidió kathys no era realizable), el symlink `/opt/cspp_heap` (falla igual con la ruta
real), el contenido del bundle instalado (los dos árboles tienen los mismos 15793 archivos,
idénticos salvo un `.pyc`), `--writable-tmpfs` (que no lo arregla, y además hace desaparecer
hasta los productos que sí salían) y la escritura en el árbol al terminar (el `find` de
archivos nuevos da 0 porque el `fort.40` **nunca llega a crearse** — una refutación mal hecha
que costó media hora y descartó la hipótesis correcta).

**Dos afirmaciones nuestras que esto corrige**, y las dos están en el reporte enviado:

- *"El log no menciona `retriev` ni una vez, así que el paso caro nunca se intenta."* Falso: se
  intenta. `HEAP_Retrieval.log` y `nucaps_retrieval.log` existen también en las corridas que
  fallan. Aquella frase describía el log del **wrapper**, el único que sobrevivía sin
  `--noclean`.
- *"El caso de prueba del fabricante reproduce el fallo, luego no es nuestra cadena."* El
  razonamiento tenía un agujero: el caso de prueba del fabricante descarta **nuestros
  insumos**, no **nuestra instalación**. Siempre lo corrimos dentro del mismo `.sif` roto.

**El arreglo:** el bundle sale de la imagen y vive en el host. `cspp_heap_v3.0.def` ya no lo
instala —aporta solo Rocky 8, perl, lftp y los puntos de montaje—, `preparar_servidor.sh` gana
una **fase 7** que lo despliega en `/data/opt`, y `run_heap_edr.sh` lo monta con `--bind` sobre
`/opt/cspp_heap`. Es exactamente la configuración que se probó, y encaja con el contrato
host↔contenedor que ya sigue el resto de la cadena.

**HEAP PRODUCE SONDEOS. 2026-08-29, sobre datos propios:**

```
✅ ÉXITO: 70 productos de la pasada j01_d20260829_b45492
   (14 NUCAPS-ALL-HR, 14 NUCAPS-CCR, 14 NUCAPS-CCR-AR, 14 NUCAPS-EDR, 14 NUCAPS-OLR)
   en 1m 57s
```

Las cinco familias y la duración que declara el manual. **La rama de sondeos deja de estar
bloqueada.**

**Costó tres fallos encadenados, y los tres se escondían detrás del mismo `EXECUTION COMPLETED
SUCCESSFULLY`:**

| # | Qué faltaba | Dónde muere | Mensaje |
|---|---|---|---|
| 1 | que el árbol no fuera de solo lectura | `airsb103.exe` | `Cannot open file 'fort.40': Read-only file system` |
| 2 | permiso de **ejecución** en el host | `main_nucaps_preprocessor` | `sh: …/main_nucaps_preprocessor: Permission denied` |
| 3 | permiso de **escritura** en el host | `airsb103.exe` | `Cannot open file 'fort.40': Permission denied` |

Los tres son la misma historia: **este bundle no es un estático de solo lectura como los demás,
es software que escribe dentro de su propio árbol de instalación.** Y los tres devolvieron
código 0. El 2 y el 3 aparecieron al desplegar en `/data/opt`, donde el `chown` al dueño de
`/data` deja el árbol fuera del alcance de quien corre la cadena; por eso la fase 7 aplica
`a+rX` y `g+w` y avisa si el usuario no pertenece al grupo.

**De aquí salió una decisión de operación, tomada el mismo 2026-08-29: la cadena correrá como
`lanotadm`.** El motivo es este episodio: dos fallos seguidos de permisos que no habrían
aparecido probando con el usuario real, porque **los permisos son parte de lo que se prueba**.
Hoy se ejecuta como una persona (`aguilars`) sobre un `/data` que es de `lanotadm`, y desde un
clon en su `$HOME`.

No hay código que cambiar: `preparar_servidor.sh` e `instalar.sh` ya usan
`DUENO=lanotadm:lanotadm` por defecto, e `instalar.sh` despliega en `/opt/lanot/polares`
exactamente para esto. Lo que hay es que empezar a usarlo, y en este orden:

1. `sudo ./scripts/instalar.sh` — el código de operación deja de vivir en un `$HOME`.
2. Un `chown -R lanotadm:lanotadm` de barrido sobre `/data/output`, `/data/tmp`,
   `/data/ancillary` y `/var/log/lanot/polares`. La fase 1 hace `chown` **sin `-R`**, así que
   los directorios ya son de `lanotadm` pero los archivos escritos hasta hoy son de `aguilars`.
   No rompe nada —el dueño del directorio manda para crear y borrar— pero conviene dejarlo
   limpio antes de que lo herede el cron.
3. El cron (`barrer_pendientes.sh`, `update_sdr_daily.sh`, `update_atmos_ancillary.sh`,
   `update_heap_ancillary.sh`) y lo que invoque la antena, como `lanotadm` y apuntando a
   `/opt/lanot/polares`.

El clon en el `$HOME` sigue siendo el sitio para desarrollar y probar a mano; lo que cambia es
que deja de ser lo que corre en operación.

**Y la cadena de sondeos, entera, con datos propios.** Renderizada la misma pasada:

```
  SONDEOS:  14 productos en la ventana
✅ ÉXITO: 31 geotiff (atmos 9, lsr 14, sst 1, fire 3, sondeos 4)
          y 16 vistas (atmos 8, lsr 1, sst 1, fire 1, sondeos 4, flood 1) en 4m 6s
```

Los cuatro sondeos con su vista —temperatura en 850, 700 y 500 hPa, más la skin—, que es lo que
estaba escrito y probado desde el 2026-08-17 esperando insumos. **HEAP vuelve a
`procesar_pasada.sh`**, en el nivel 2, doce días después de salir.

**Lo que falta:** escribirle a kathys — su software no tiene nada malo y está dedicando tiempo
a un problema ajeno.


### Lo que sigue abierto

- **Publicar vapor de agua exigiría todavía su CPT y su entrada en `product_map`** de
  LANOT_tools. Que cargue no es que salga rotulado: sin eso habría GeoTIFF sin vista, o vista
  sin nombre.
- ~~**HEAP sigue sin producir `NUCAPS-EDR`** con ancillary reciente.~~ **Vencido**: esto se
  escribió en `f13543e`, temprano el 29, y unas horas después `bcaa5b2` lo desmintió —14
  `NUCAPS-EDR` sobre datos propios, y `c180950` devolvió HEAP a la cadena—. Lo que sigue en pie
  de aquel párrafo es solo el dato de fondo: `update_heap_ancillary.sh` **solo poda, no
  descarga**, porque HEAP baja su GFS solo con `lftp`.
- ~~**La respuesta al hilo de SSEC**, redactada al final de `docs/reporte_polar2grid_nucaps.md`.~~
  **Publicada el 2026-08-31**, junto con la de CIMSS.

---

## Dónde quedó el 2026-08-18 (cierre de la sesión)

**Las vistas salieron del servidor.** Están publicadas en
`https://vistas.lanot.unam.mx/polariac/`, con las dos pasadas de NOAA-20 del 17: la diurna
(19:36Z) y la nocturna (08:25Z), la del `dynamic_dnb` que se quería presumir. La galería la
arma `scripts/publicar_vistas.sh` + `publicar_vistas.py`.

### La galería, y por qué el pie de foto sale de LANOT_tools

El publicador corre **dentro** del contenedor de Polar2Grid, con el intérprete del venv
(`/opt/lanot-tools/venv/bin/python`), y no por comodidad: el nombre del producto sale de la
**misma** `product_map` con la que `geotiff2view` rotula la imagen, y la nota de la paleta
del **mismo** CPT con el que la coloreó. Así el HTML y el JPG no se pueden contradecir, y un
producto sin entrada en `product_map` se delata en los dos lados a la vez.

La carpeta es **autocontenida y portátil** —copias reales de los JPG, rutas relativas, cero
recursos externos— porque se copia a mano al servidor web. Se comprueba con
`find … -type l` (vacío) y un `grep` de URL externas. `--anexo RUTA:TÍTULO` cuelga de la
galería un directorio ya armado con su propio `index.html`.

Dos cosas que solo aparecieron con datos reales:

- **Las vistas de inundaciones no llevan sufijo de rejilla** —`…_flood_20260817_193624.jpg`—
  porque su GeoTIFF lo hace `flood2tif.sh` y no Polar2Grid. El patrón del sello temporal
  exigía guion bajo final y las descartaba en silencio; ahora el separador se mira con
  lookahead y acepta punto.
- **`enrich_from_filename` busca el producto en la RUTA COMPLETA como respaldo.** Por eso
  `confidence_cat`, que no tiene entrada propia en `product_map`, sale rotulado "Fire": lo
  aporta el directorio `/output_fire_tif` que le pasa el renderizador. Pasando solo el
  basename, la ficha decía otra cosa que el JPG.

### El logo NO se corta — cierra el pendiente menor del punto 9

`lanot_negro_sn.png` **es** el logotipo completo: L-A-N, el globo como O y el satélite como
T. El recuadro de lo no transparente es (32, 31, 1168, 252) sobre 1188×282 —márgenes
simétricos— y `mapdrawer.py:862` lo pega en x=10 con el ancho entero. Lo que se leía como
"LAN seguido de dos iconos" era la marca entera. El diseño es así.

### Presión de tope de nube, publicada por fin

`CldTopPres` era la única variable de `JRR-CloudHeight` que no pedíamos, aunque el dato se
generaba en cada pasada y su entrada en `PALETAS` existía desde siempre. Se agregó a
`ATMOS_DATOS`; el lector `viirs_edr` descubre las variables del archivo dinámicamente
(`satpy/readers/viirs_edr.py:225`), así que no hizo falta nada más.

Se pinta con `cld_top_press.cpt`, que es **la misma** con la que `hpsatviews` pinta el
producto CTP de ABI (`paper/create_fig2.sh:47`), así que las vistas de GOES y las polares
quedan comparables. Su rango 100–1050 hPa le queda casi perfecto al dato medido sobre la
pasada diurna: **0,23 % por debajo del piso y 0 % por encima**.

**Y de ahí salió un fallo de la cadena.** La primera vista salió con el **fondo blanco**, el
57 % de la escena. El motivo está escrito en el propio CPT: su `B` es blanco y significa
"< 100 hPa", mientras que su `N` es negro y el comentario dice literalmente "No Data /
Cielo Despejado". `run_polar2grid_edr.sh` pasaba `-b` a `geotiff2view` **siempre**, forzando
`B`. Para esta paleta está mal dos veces: pinta el cielo despejado de blanco *y* del mismo
color que el extremo de 100 hPa de la rampa. GOES no lo sufre porque `hpsv` honra `N`.

La excepción es `CPT_CON_NODATA_PROPIO`, lista **explícita** y no una heurística sobre el
archivo: que un `N` "parezca" fondo no dice si el autor lo pensó para eso, y equivocarse
tiñe la escena entera. Al agregar una CPT cuyo `N` sea el fondo que se quiere, agregarla ahí.

### Dos trampas de despliegue, las dos a punto de costar la sesión

- **`/opt/contenedores` ÷ `/opt/containers`.** `construir.sh` compila en el primero y los
  `run_*.sh` leen del segundo. Se diferencian en una letra, y una imagen recién compilada no
  entra en producción hasta copiarla a mano.
- **El pin otra vez.** Se empujó el commit de LANOT_tools y se lanzó el build sin mover
  `LANOT_TOOLS_COMMIT`, que seguía dos commits atrás: habría compilado sin error y la vista
  de presión habría salido rotulada "NOAA-20 VIIRS". Es el mismo patrón del 2026-08-14. Ya
  hay guarda: `%post` y `%test` comprueban que `product_map` conozca `cldtoppres`, y está
  medido que con el pin viejo salen con código 1 y `set -e` detiene la compilación.

Tras recompilar y re-renderizar las dos pasadas, **los productos anteriores salieron byte a
byte del mismo tamaño**: el salto de pin `8bc8f69` → `2df2fbc` no alteró nada de lo que ya
funcionaba.

### Las paletas de nubes: revisadas, medidas, y una decisión pendiente

Alejandro notó que temperatura y altura de tope se ven casi iguales. No era impresión: **son
una sola paleta usada dos veces**, emparejada por un gradiente constante de 5,0 K/km —ocho
de los diez colores de `cld_height_acha.cpt` son los de `cld_temp_acha.cpt`, con 0 m↔295 K,
6 km↔270 K y 14 km↔230 K—. El emparejamiento era deliberado; se decidió **separarlas**,
porque el costo lo paga cualquiera que mire la galería y el beneficio no lo explota nadie.

Medido sobre las dos pasadas del 17, `cld_temp_acha.cpt` tiene dos defectos:

| tramo | ΔE medio entre escalones | croma |
|---|---|---|
| 180–240 K (convección profunda) | **13,5** | 0 → 37 |
| 240–295 K (nube baja) | **23,5** | 32 → 45 |

y su techo de 295 K **recorta el 13,7 % del dato** (el máximo real es 320 K). Los primeros
10 K son ΔE = 0,0: dos blancos idénticos. Además su color más cálido es negro, el mismo del
cielo despejado, así que un tercio de la escena es invisible.

**Por qué importa, y es el argumento que decide: las estructuras que se pierden son
tormentas.** Entre 180 y 260 K la paleta actual recorre **106 ΔE** de camino visual; la de
GOES, **836** — ocho veces más para el mismo rango físico. En 200–260 K, dos nubes que
difieren 10 K se separan en la actual tan poco como **9,8 ΔE**, por debajo del umbral en que
el ojo las distingue, frente a **37–166** en la de GOES. Se ve en el Golfo de California y
en el extremo norte de la pasada diurna: lo que en la actual es una mancha pálida sin forma,
en la de GOES resuelve en un sistema con su núcleo y sus anillos.

Hay seis opciones comparadas en el anexo de la galería, con la misma vara para todas:

| Opción | Rango | Discriminación a 10 K | Dato fuera |
|---|---|---|---|
| En producción hoy | 180–295 K | ΔE 19 | 13,7 % |
| **La de GOES (`atmosrainbow`)** | **180–320 K** | **ΔE 48** | **0,0 %** |
| Conservadora | 180–313 K | ΔE 19 | 0,4 % |
| Viridis invertida | 180–313 K | ΔE 18 | 0,4 % |
| Cividis invertida | 180–313 K | ΔE 13 | 0,4 % |
| Inferno invertida | 180–313 K | ΔE 21 | 0,4 % |

La **favorita es la de GOES**: `atmosrainbow` (`hpsatviews/src/palette.c:11`), la que
`create_nocturnal_pseudocolor()` aplica a la temperatura de brillo de ABI C13, que es la
misma magnitud física. Gana en discriminación, no recorta nada, ya está probada, y sobre
todo **hace comparables las vistas de GOES y las polares**: un solo código de color que
aprender. No es una rampa sino un código de dos regímenes —gris para la nube baja, arcoíris
reservado a los topes bajo 253 K—, así que no se ordena por intuición sin conocerlo.

Dos avisos medidos sobre nuestro dato, que en GOES no molestan: tiene una **banda de negro
puro en 201,7–202,5 K** —allá se lee como el núcleo más frío porque va rodeada de rojo, aquí
se confundiría con el cielo despejado— y el **blanco se repite** en 180–195 K y 255–275 K.
Lo primero se arregla dándole al fondo un color propio, sin tocar la paleta; lo segundo es
inherente al código.

La **conservadora** es el resultado más útil para decidir: mantener el vocabulario actual
corrige el techo y hace visible la nube baja, pero **no** arregla el extremo frío (ΔE 9,8
entre las primeras clases), porque esos pasteles son intrínsecamente parecidos. El cambio de
aspecto no es capricho: el mínimo cambio no basta.

Se descartó una propuesta de curva IR realzada estilo BD porque **cada valor especial choca
con uno del rango**: blanco = 180 K y también 245 K, `N` = rojo puro = 200 K exacto. Y su
justificación era de otro producto —"silencia el ruido de la superficie"—: `CldTopTemp` es
recuperado, solo existe donde hay nube (32–43 % de la escena), así que ahí no hay superficie
que silenciar y el tramo que aplanaba a gris es **nube baja**.

### La decisión: `atmosrainbow`, con el fondo en negro (2026-08-18)

Se eligió la de GOES. Está transcrita en `LANOT_tools/colortables/atmosrainbow.cpt` (commit
`4bf323d`) y `run_polar2grid_edr.sh` ya la pide para `CldTopTemp`; `cld_temp_acha.cpt` se
conserva intacta porque la usa la cadena vieja. Tres decisiones que la transcripción tuvo
que tomar, porque el CPT no puede decir todo lo que dice la tabla en C:

- **Rango 180–320 K**, no 170–380. Recortar al rango que el dato ocupa de verdad (0,0 %
  fuera, medido) no gasta entradas del LUT en temperaturas que `CldTopTemp` no alcanza. Los
  colores a cada temperatura son los mismos: el recorte mueve los extremos, no la escala.
  Verificado entrada por entrada contra la tabla de `hpsatviews`: **error máximo de 1,7
  niveles sobre 255**.
- **El alpha no viaja, y no hace falta.** La tabla en C lo tiene decayendo de 1,0 a 0 por
  encima de 259 K, pero ahí es un velo sobre la superficie, porque se aplica a temperatura
  de brillo, que existe en toda la escena. En `CldTopTemp` ese tramo no es superficie que
  velar: es **nube baja**, y va opaca. Recortar la paleta al tramo opaco habría sido peor
  que no cambiarla: `geotiff2view` recorta el sobre-rango con `np.clip` y nunca cae en `F`
  (`geotiff2view.py:210,221`), así que los 260–320 K se habrían pintado todos del último
  color, en blanco, que es el mismo del extremo frío.
- **`N` es negro**, como en las vistas de GOES, y no un color propio. El riesgo medido era
  que el negro también es un valor de la escala —el núcleo de 201,7 K—, pero sobre la vista
  real de G19 no se confunde: el núcleo frío va siempre rodeado de rojo y ocupa unos pocos
  píxeles, mientras que el fondo es el 32 % de la escena. Y un fondo distinto al de GOES
  habría roto lo único por lo que se adoptó esta paleta, que es que las dos vistas se lean
  igual. `atmosrainbow.cpt` va en `CPT_CON_NODATA_PROPIO` porque su `N` es exactamente el
  fondo que se quiere, que es el criterio de esa lista.

### Lo que sigue, en orden

1. **El `B` de `cld_height_acha.cpt`**: hoy `B`, `N` y el escalón de 0 m son los tres
   `(0,0,0)`, así que cielo despejado y nube apoyada en el suelo se dibujan igual. Es el
   mismo defecto que se acaba de corregir en presión, y ya hay precedente de cómo.
2. `cld_top_press.cpt` como paleta de presión queda **cerrada**; la entrada muerta de
   `PALETAS` dejó de serlo.

---

## Dónde quedó el 2026-08-17 (cierre de la sesión)

**El día se fue en descubrir que HEAP nunca ha producido un sondeo**, y en comprobar —con los
gránulos de muestra— que en cambio el renderizado sí funciona de punta a punta. Los detalles
están en el pendiente 4; aquí queda solo qué hacer al retomar, y en qué orden.

### 1. Camino crítico: el reporte a CIMSS — ENVIADO Y CONTESTADO (2026-08-29)

Está escrito y versionado en **`docs/reporte_cimss_heap_v3.0.md`**. Se envió el 2026-08-24 al
foro de SSEC: <https://forums.ssec.wisc.edu/viewtopic.php?t=60121>. Todo lo demás de sondeos
sigue detrás de esto: sin `NUCAPS-EDR` no hay nada que renderizar sobre datos propios.

**Kathy Strabala contestó el 2026-08-25, y lo primero que dice es que no es culpa nuestra:**
*"I do not think you are executing the software incorrectly. From what you have described, you
have everything you need to successfully run the software. We will work to figure out why it
is failing."*

**Corrige además lo que aquí se había concluido sobre `NUCAPS-ALL-HR`.** Son *"intermediary
files that are input by some of the other NUCAPS modules"*, y —esto es lo que nos faltaba— las
radiancias limpiadas de nube **van en `NUCAPS-CCR-AR`, no en `ALL-HR`**. El 2026-08-17 se
concluyó que "ALL-HR es el CCR": la mitad estaba bien (es un intermedio, una entrada) pero la
etiqueta no. Consecuencia: de los tres productos finales no falta uno, **faltan dos** —`EDR` y
`CCR-AR`—, y su ausencia es *"a symptom of whatever is causing your NUCAPS-EDR to not be
created either"*. Eso mueve el fallo más atrás de lo que suponíamos: tampoco el cloud-clearing
entrega su producto. Corregido en `run_heap_edr.sh`, `run_polar2grid_edr.sh` y `CLAUDE.md`.

**Lo que piden, y es lo siguiente que hay que hacer:**

1. **Correr fuera del contenedor**, para descartarlo como causa.
2. **Repetir sobre los datos de prueba con `--noclean`** y subir el directorio de trabajo a
   `ftp://ftp.ssec.wisc.edu/pub/incoming` (FTP anónimo).

Sobre (1) hay una arruga que conviene decirles si el resultado no es limpio: el contenedor de
HEAP parte de **Rocky 8 a propósito**, siguiendo el manual, así que correr en el host de tahan
no es "lo mismo sin contenedor" sino además otro sistema operativo. Si falla igual fuera, el
resultado es concluyente y descarta el contenedor; si funciona fuera, no se puede atribuir al
contenedor sin separar antes esa segunda variable.

**Corrido el 2026-08-24 en tahan, y cerró el argumento:** `benchmark_edr/` trae los 48
archivos documentados —16 `NUCAPS-CCR-AR`, 16 `NUCAPS-EDR`, 16 `NUCAPS-OLR`— o sea los dos
productos que nuestra corrida no produce, y **ninguno** `NUCAPS-ALL-HR`, que es el único que
sí produce. Su propio benchmark es de un producto que su propio software no genera. Ya está
incorporado al reporte, que además dejó de preguntar si `NUCAPS-ALL-HR` sustituye al CCR-AR
—no está ni en §1.7 ni en el benchmark— y ahora pregunta qué es y cuándo se escribe.

```bash
D=/opt/contenedores/nucaps_test_data
ls "$D"/benchmark_edr/ | sed 's/_v3r.*//' | sort | uniq -c
```

Queda sin correr el otro, que compara contenido y ya no hace falta para el reporte:
`cd "$D" && ./nucaps_compare.bash benchmark_edr/ work/`.

### 2. Higiene, mientras CIMSS responde

- ~~**Desactivar `heap` en `procesar_pasada.sh`.**~~ **Hecho.** La línea quedó comentada en el
  sitio donde iba, con la explicación y la instrucción de devolverla a la lista cuando haya
  producto. El resto de la rama —`run_heap_edr.sh`, el renderizado, las CPT— sigue en su lugar.
- **Borrar los `.done` de `/data/output/jpss/state/cspp-heap/`**: todos se firmaron con el
  criterio viejo y afirman un éxito que no ocurrió. **Pendiente, va en tahan**:

  ```bash
  rm -f /data/output/jpss/state/cspp-heap/*.done
  ```

### 3. Un segundo reporte, este a Polar2Grid — CERRADO, ARREGLADO AGUAS ARRIBA (2026-08-29)

Por el `KeyError: 'H2O_MR/attr/valid_range'` (ver pendiente 4, hallazgo 1). El texto quedó en
`docs/reporte_polar2grid_nucaps.md` y se envió al foro de SSEC el 2026-08-24:
<https://forums.ssec.wisc.edu/viewtopic.php?t=60122>.

Iba con dos peticiones, no una: el `KeyError` —que es lo que bloquea— y, aparte, que un
producto ilegible no tumbe la llamada entera. **Las dos prosperaron.** David Hoese contestó al
día siguiente y el 2026-08-26 mergeó [pytroll/satpy#3450](https://github.com/pytroll/satpy/pull/3450),
que son exactamente dos líneas:

```python
-        valid_min, valid_max = self[var_path + "/attr/valid_range"]
+        valid_min, valid_max = self.get(var_path + "/attr/valid_range", (None, None))
```
```python
         datasets_loaded = super(NUCAPSReader, self).load(
             dataset_keys, previous_datasets=previous_datasets)
+        dataset_keys &= set(datasets_loaded.keys())
```

Tres cosas que dejó la respuesta y conviene no perder:

- **El diagnóstico del todo-o-nada estaba a medias.** El `KeyError` de `valid_range` **no**
  aborta por sí solo: Satpy lo atrapa al cargar y sigue. Lo que mata la corrida es el segundo
  bug, que el reporte no había identificado — el lector no depura la lista de productos
  pedidos con los que de verdad cargaron, así que el filtrado por presión posterior busca el
  que faltó. De ahí la segunda línea del parche.
- **`--list-products` no se va a arreglar**, y la razón es razonable: Polar2Grid no puede saber
  que un producto fallará sin intentar cargarlo, y el lector `nucaps` no trae la detección
  previa que sí tienen otros lectores. Seguirá anunciando las 100 capas de `H2O_MR`.
- **El lector `nucaps` no tiene mantenimiento activo** (sin financiamiento dedicado). Merece
  tenerse en cuenta antes de apoyar nada más en él: lo que se rompa, lo reportamos nosotros.

**A nosotros no nos llega solo.** El bundle 3.2 lleva `satpy 0.59.1.dev110` congelado dentro,
así que el arreglo vendría con Polar2Grid 3.3 —la misma versión que traerá el lector de OMPS—.
Mientras tanto lo aplica `contenedores/polar2grid_v3.2-mapdrawer.def` en el `%post`, sobre el
bundle recién extraído y **antes** del calentamiento, para que el `__pycache__` se genere ya
parcheado. El bloque se ancla con `grep` sobre las dos líneas originales y aborta la
compilación si el archivo dejó de ser el que espera; el `%test` comprueba por `inspect` —no con
un `grep` sobre la ruta— que el módulo que Satpy importa de verdad trae los dos cambios.
**Al pasar a Polar2Grid 3.3: quitar ese bloque, en `%post` y en `%test`.**

Sacar vapor de agua sigue sin ser gratis aunque ya cargue: falta su CPT y su entrada en
`product_map` de LANOT_tools.

Queda una cosa por hacer del lado del foro: davidh preguntó a qué se refería el reporte con
que "el remuestreo ya está pagado", con razón — si la carga falla, no se llega a remuestrear.

**Lo que hizo que el reporte pasara de "tenemos un `KeyError`" a "aquí está la línea":** el
bundle de Polar2Grid está extraído en **`/data/cspp/polar2grid_v_3_2/`**, en esta máquina, con
todo el `site-packages` de su runtime de Python. O sea que el código de los lectores de Satpy
se puede leer aquí, sin tahan y sin contenedor:

```
/data/cspp/polar2grid_v_3_2/libexec/python_runtime/lib/python3.11/site-packages/satpy/
```

De ahí salieron las tres cosas que sostienen el reporte, y ninguna necesitó reproducir el
fallo: que `nucaps.py:193` usa `self[...]` mientras la línea 194 usa `self.get(...)` para
`_FillValue`; que `get(item, default=None)` existe en el handler
(`satpy/readers/core/netcdf.py:319`) y que `__getitem__` indexa `file_content` directo, que es
de dónde sale el `KeyError` con ese texto; y —lo que lo vuelve concluyente— que la línea 218
**ya contempla** `valid_min is not None`, así que el arreglo de una línea encaja con lo que el
código de abajo ya espera. También de ahí sale que no es cosa del vapor de agua: `nucaps.yaml`
define otros dieciocho datasets `pressure_based` igual, y cualquiera cae en la misma ruta.

Vale la pena recordarlo para la próxima: **antes de dar por perdido un detalle porque "está en
tahan", mirar `/data/cspp`.** Es el mismo tarball que se mete en el `.sif`.

### 4. Lo que se puede avanzar sin esperar a nadie — ESCRITO el 2026-08-17

Las tres piezas están hechas, en una sola pasada por LANOT_tools como estaba previsto. Lo que
falta de esto es **de servidor, no de código**: ver "Para que la vista de sondeos quede lista
en tahan", abajo.

1. **El bloque de sondeos en `run_polar2grid_edr.sh`** — hecho. `-p` explícito con los cuatro
   campos, `-g wgs84_geo_5km` con `--grid-configs`, sin `--method` (se deja el del lector, que
   es con lo que se probó), máscara de calidad puesta, y `vestir` con `geotiff2view`. Entra al
   staging **solo** `NUCAPS-EDR*`, emparejado por ventana temporal y no por órbita, y con la
   deduplicación por `_c<sello>` que ya usaban ATMOS y LSR.
2. **Los CPT de temperatura**, uno por nivel — hecho: `nucaps_temp_850.cpt` (270–305 K),
   `nucaps_temp_700.cpt` (260–290), `nucaps_temp_500.cpt` (245–275) y `nucaps_skin_temp.cpt`
   (265–325). Mismos colores que `sst.cpt`, para que las vistas de temperatura de LANOT se
   lean igual; lo único que cambia entre niveles es el rango, que es lo que no se puede
   compartir. **Rango fijo y no percentiles**: la temperatura a nivel fijo es un campo con
   rango climatológico estable, así que la paleta fija es justo lo que hace comparables dos
   pasadas — el argumento de los percentiles era del DNB, que es radiancia con cola larga.
   De regalo, `geotiff2view` dibuja la barra de color solo con que haya CPT.
3. **Las entradas de `metadata.py`** — hechas, y son más de dos: el sensor `atms-cris` →
   `CrIS+ATMS` (con `cris` y `atms` sueltos de respaldo), los cuatro productos que se rinden,
   `Surface_Pressure` y `Topography`, y un `temperature` genérico **al final** de `product_map`
   para que los otros 96 niveles no salgan sin nombre si algún día se piden. Con pruebas en
   `tests/test_metadata.py`, incluida una que fija el orden: el genérico no debe ganarle a
   `CldTopTemp`.

Una decisión que no estaba prevista: los sondeos se visten **sin el `-s 0.5`** del resto. A
5 km la imagen ya sale de 772 × 797, y a la mitad la barra de color no se puede leer. `vestir()`
acepta ahora un noveno argumento con banderas extra, que van después de `DECORACION` y por lo
tanto ganan (argparse se queda con la última).

Verificado en bucefalo con un `apptainer` simulado: el staging deja los 3 gránulos de la
ventana y descarta el reproceso duplicado, el que cae fuera, el de otro satélite y las familias
`NUCAPS-ALL-HR`/`NUCAPS-OLR`; salen los cuatro GeoTIFF con su CPT correcto y el `-s 1` final.

### Los rangos de las paletas, medidos — 2026-08-17, en tahan

`run_polar2grid_edr.sh` corrió entero contra los 19 gránulos de muestra, inventándole una
pasada: un `GMTCO` vacío `j02_d20260630` basta para que la ventana los alcance, y los demás
conjuntos, al no tener nada de esa fecha, se saltan solos. **4 GeoTIFF y 4 vistas en 43 s.**
Con `P2G_STATE_DIR` y `P2G_LOG_BASE` desviados a `/data/tmp`, que si no el marcador falso se
escribe en el árbol de producción.

| Producto | válidos | p2 | media | p98 | max | CPT | ocupa |
|---|---|---|---|---|---|---|---|
| `Skin_Temperature` | 47.8 % | 279.4 | 303.8 | 315.2 | **319.3** | 265–315 | 72 %, **saturaba** |
| `Temperature_497mb` | 47.8 % | 259.6 | 265.3 | 267.8 | 270.1 | 245–275 | 27 % |
| `Temperature_707mb` | 47.8 % | 275.4 | 282.8 | 286.7 | 288.4 | 260–290 | 38 % |
| `Temperature_853mb` | 47.8 % | 283.6 | 291.9 | 296.9 | **301.6** | 270–300 | 44 %, **saturaba** |

Dos correcciones, y las dos por el mismo criterio: lo que se mira es **`max` contra el techo**,
no `p98`. Con `p98` los dos casos pasaban desapercibidos.

**El skin estaba mal de concepto**: se dimensionó como si fuera un campo de atmósfera libre. No
lo es —tiene ciclo diurno y depende del tipo de superficie—, así que su variación es mucho más
ancha que la de cualquier nivel. Pasa a **265–325**, paso de 6 K.

**El techo de 850 hPa sube a 305** (paso de 3.5 K, que no es redondo porque son once colores; da
igual, las etiquetas de la barra las alinea el código y no los cortes del CPT). Los 301.6 K de
esta escena solos no lo ameritarían —para eso está el último color—, pero junio no es el caso
extremo: sobre el desierto en mayo ese nivel pasa de 305 K, y una ola de calor es justo cuando
alguien mira el producto.

**Los otros dos niveles se dejan como están, y la ocupación baja no es un defecto.** Están
sesgados al frío a propósito: ésta es una escena de junio y en enero los mismos campos ocupan la
mitad de abajo de la rampa. Apretarlos por lo que se ve hoy sería optimizar la vista de verano a
costa de la de invierno, que es justo lo que la paleta fija está para evitar. Lo que sí es
intrínseco: **el rango de una escena a nivel fijo es estrecho** (8 K de p2 a p98 en 500 hPa), así
que ninguna paleta fija va a dar mucho contraste ahí. Es el precio de que dos pasadas se puedan
comparar, y se paga a sabiendas.

Que saturar no se note es parte del problema: **`ColorPaletteTable.apply` recorta al último
color en vez de usar el color F**, así que un techo corto no se ve como un aviso sino como una
zona plana. Tenerlo presente al escribir cualquier CPT nueva.

**No hay que recompilar** por ninguna de las dos: las CPT se montan desde el host, o sea
`git pull` + `sudo ./install.sh` en tahan y volver a correr la prueba.

Y una advertencia sobre el propio guion de verificación: la primera versión llevaba los rangos
**escritos a mano**, así que no podía comprobar la instalación — las estadísticas salen del
GeoTIFF, que es dato y no cambia con la paleta. El que sirve carga el CPT con
`ColorPaletteTable` desde `/usr/local/share/lanot/colortables` y compara contra `c.max_val`.

La otra lectura de la tabla: el 47.8 % de válidos es idéntico en los cuatro productos, que es lo
que se espera si quien decide es la máscara de calidad y no cada campo por su cuenta.

### Para que la vista de sondeos quede lista en tahan — HECHO salvo lo visual

Se hizo el mismo 2026-08-17: `git push`, `git pull` en los dos repos, `sudo ./install.sh` y
recompilación de `polar2grid_v3.2-mapdrawer.sif`. Comprobado que la imagen tomó el pin nuevo,
por dos caminos:

```bash
apptainer inspect /opt/containers/polar2grid_v3.2-mapdrawer.sif | grep -i lanot_tools
#   LANOT_tools_commit: edb225339b79123e47bc2a137d30b5528a2dab31

apptainer exec /opt/containers/polar2grid_v3.2-mapdrawer.sif \
  /opt/lanot-tools/venv/bin/python -c "
from metadata import Metadata
m = Metadata()
m.enrich_from_filename('noaa21_atms-cris_Temperature_497mb_20260630_184728_wgs84_geo_5km.tif')
hp = bool(m.get('product') or m.get('band'))
print(m.format_timestamp(include_satellite=True, include_sensor=not hp, include_product=hp))"
#   NOAA-21 Temp 500 hPa 2026/06/30 18:47Z
```

La segunda es la que vale: reproduce la llamada que hace `geotiff2view` al dibujar. La primera
puede engañar si alguien edita `%labels` sin mover el pin del `%post` — están juntos por eso.

**La etiqueta NO lleva el sensor**, y conviene no volver a esperarlo: `geotiff2view.py:698` pasa
`include_sensor=not has_product`, o sea que el sensor es un **respaldo** para cuando no hay
producto, no un añadido. La entrada `atms-cris` de `metadata.py` sirve igual —es lo que evita
que un producto sin match salga como "NOAA-21" a secas— pero hoy no se ve en ninguna de las
cuatro vistas.

### La revisión visual, hecha — y de ahí salió `--font-bg`

Se trajeron dos JPG y se miraron. **Lo que estaba bien**: la etiqueta correcta, la barra de color
legible a tamaño natural (a la mitad esos números habrían quedado marginales, o sea que quitar el
`-s 0.5` era necesario), el logo sobre negro sin tapar dato, y el encuadre con Mexico completo y
la barra en la franja que libera `--lat-south 11`. El skin ya no satura: rojo sobre tierra al
noroeste, verde sobre el Golfo, cian donde hay nube.

**Lo que estaba mal**: en la vista de 500 hPa el título va en blanco sobre el amarillo brillante
del dato y no se lee. Y **no es de sondeos**: es de cualquier producto cuyo swath llegue a la
esquina superior derecha, que es donde `--timestamp-pos 1` pone la fecha.

Mover la fecha no es salida, y esto se midió en vez de suponerse: **`--timestamp-pos 2` no la
pone en la esquina inferior izquierda del mapa sino al pie de la imagen, encima de la barra de
color** — el título y las etiquetas `245 250 255…` quedan superpuestos e ilegibles los dos. Por
la misma razón cae la 3, y la 0 la ocupa el logo. **La 1 es la única esquina libre**, no una
preferencia.

La solución ya existía a medias: `draw_fecha` sabe dibujar una caja oscura semitransparente
detrás de la fecha (alfa 140) y `mapdrawer` la expone como `--font-bg`; lo que faltaba era el
paso por la CLI de `geotiff2view`, que llamaba sin `bg_color`. Agregado en LANOT_tools `8bc8f69`,
por omisión `None` para que nada cambie si no se pide. Probado **en bucefalo**, sin tocar tahan y
sin recompilar: aquí están `/usr/local/share/lanot/{logos,gpkg}` y las dependencias, así que
`python3 geotiff2view.py` renderiza un GeoTIFF traído por `scp`.

**Decidido: `--font-bg black` va en las DOS `DECORACION`** (Level 1 y Level 2), no solo en
sondeos. El problema es compartido y la inconsistencia entre productos se nota más que la caja.

> **ORDEN OBLIGATORIO AL DESPLEGAR ESTO.** Las `DECORACION` ahora piden una bandera que el `.sif`
> de hoy no tiene, y esto **no degrada**: `geotiff2view` muere con `unrecognized arguments:
> --font-bg black` en **todas** las vistas de las dos etapas. Los GeoTIFF sí se escriben, así que
> la pasada se marca como hecha con cero vistas. Primero **recompilar** el contenedor, y solo
> después `scripts/instalar.sh`.

Un tropiezo del método, el tercero del día: la primera comparación antes/después salió sin
`NOAA-21 Temp 500 hPa` en la etiqueta, y no era culpa del cambio — al traer el GeoTIFF por `scp`
se le había puesto otro nombre, y `metadata.py` saca producto y satélite **del nombre del
archivo**. Renombrar un archivo de prueba no es inocuo.

Y falta reinstalar las dos CPT corregidas (`87251ca`, `fbcaef8`), que no necesitan recompilar.

### Órdenes que reproducen la prueba de hoy

Para no reconstruirlas desde cero. En tahan, con la rejilla temporal ya escrita en
`/data/tmp/grid_nucaps.yaml` (o usando `config/grid.yaml`, que ya trae `wgs84_geo_5km`):

```bash
IN=/opt/contenedores/sample_data/input/nucaps
OUT=/data/tmp/prueba_nucaps5km

apptainer exec --bind "$IN:$IN" --bind "$OUT:/output" \
    --bind /data/tmp:/data/tmp --pwd /output \
    /opt/containers/polar2grid_v3.2-mapdrawer.sif \
    polar2grid.sh -r nucaps -w geotiff \
        --grid-configs /data/tmp/grid_nucaps.yaml -g wgs84_geo_5km \
        -p Temperature_853mb Temperature_707mb Temperature_497mb Skin_Temperature \
        --dtype float32 --no-enhance \
        -f "$IN"/NUCAPS-EDR_v3r2_n21_*.nc

apptainer exec --bind "$OUT:$OUT" \
    /opt/containers/polar2grid_v3.2-mapdrawer.sif \
    geotiff2view "$OUT"/noaa21_atms-cris_Temperature_497mb_20260630_184728_wgs84_geo_5km.tif \
        --percentiles 2,98 --layer COASTLINE:white:1.0 \
        --logo-pos 0 --timestamp-pos 3 -j -o "$OUT"/vista.jpg
```

Dos tropiezos que costaron un intento cada uno: **`-o` no existe** en `polar2grid.sh` (el
escritor nombra la salida y la deja en el `pwd`; para separar corridas, cambiar el directorio
montado en `/output`), y **el glob hay que expandirlo en el host**, o sea montar el directorio
de entrada sobre sí mismo — si se pasa `-f /input/*.nc` llega el asterisco literal y responde
`No filenames found for reader: nucaps`.

---

## Dónde quedó el 2026-08-15 (cierre de la sesión)

Nota: el humano se encarga de empujar así que dejar de reportar que nada está empujado, porque es falso. Inmediatamente después de que lo escribes aquí, yo lo empujo.

**Nada está empujado.** Quedan **once commits** en la cadena (de `1e5b74f` a `0de1b1b`) y
**uno** en LANOT_tools (`af02825`, que solo toca comentarios del `.cpt`).

La sesión hizo dos cosas: cerró el tipo de nube, y escribió la orquestación entera junto con
la instalación. Todo lo nuevo está probado en bucéfalo con eslabones y tarballs simulados;
**nada de esto ha corrido en tahan todavía**.

### Al retomar el lunes, en orden

**1. `git push` de los dos repositorios**, y `git pull` en tahan.

**2. `obtener_tarballs.sh --registrar`, y va PRIMERO.** Es lo que llena los sha1 del
manifiesto a partir de los tarballs buenos que ya están en tahan; nacen en `-` porque no se
inventan. **Registrar antes de limpiar nada**: de un tarball ya borrado no se puede sacar el
sha1, y esa fila se queda apoyada solo en el destino. Aprovechar para confirmar que el
estático de ATMOS se llama `CSPP_VIIRS_ATMOS_V1.0_STATIC.tar.gz`, que salió del manual y no
de haberlo visto en el disco.

Ojo con una limitación conocida: los siete estáticos de SDR se extraen todos sobre `SDR_4_1/`,
así que `--registrar` guarda un archivo de dentro de cada tarball para distinguirlos. Si dos
comparten archivo, `--verificar` avisa de la comprobación repetida y hay que corregirla a
mano. Ese aviso está probado.

**3. `preparar_servidor.sh --verificar` sobre tahan, ANTES de tocar nada.** No cuesta nada y
es la prueba de que la fase 1 del script viejo estaba incompleta: debería reportar como
faltantes los ocho `state/` que nunca creó, `vistas/`, `cspp-edr`, `orquestador` y
`/data/ancillary/atmos`.

**4. `instalar.sh`**, y comprobar que un `run_*.sh` corre desde `/opt/lanot/polares/scripts/`
sin el clon de por medio. Después, el enlace que ve la antena:
`ln -sf /opt/lanot/polares/scripts/recibe.sh /home/lanotadm/bin/recibe.sh`.

**5. La cadena de verdad**: `procesar_pasada.sh --clave j01_d20260811_b45236 --force`, contra
los conteos registrados —22 GeoTIFF y 9 vistas de Level 2— y con dos cosas que mirar en el
resumen: que las etapas que no tenían nada que hacer salgan como "ya estaba" y no como "ok"
(se distingue por el sello del marcador, no por el código de salida), y qué pasa con OMPS,
cuya clave truncada puede resultar ambigua si ese día hubo dos pasadas.

**6. Montar el cron**: `barrer_pendientes.sh` cada 15 minutos y `--novedades` mensual, con las
rutas de `/opt/lanot/polares/scripts/`. Y de paso cotejar contra un `crontab -l`, porque
ninguna de las tareas de la tabla de más abajo está confirmada como activa.

### Lo que se cerró hoy

- **HEAP, escrito y probado con datos reales** (pendiente 4): receta, `run_heap_edr.sh`,
  podador de caché y cableado. Es el único eslabón que **no** tiene equivalente en el
  servidor viejo. Cinco defectos salieron en la puesta en marcha y están anotados abajo; el
  que más vale la pena recordar es que dos de ellos estaban emparejados — el margen de ATMS
  se encontró **porque** el rescate de logs ya existía.
- **El tipo de nube**, con la enumeración del ATBD y la comparación contra CLAVR-x. Ver abajo.
- **La orquestación**: `procesar_pasada.sh`, `barrer_pendientes.sh` y `recibe.sh` corregido.
  `plan_orquestacion.md` queda como registro del diseño, con las cuatro cosas que salieron
  distintas anotadas.
- **La instalación**: `/opt/lanot/polares` con `instalar.sh`, y `preparar_servidor.sh` en
  lugar de los dos scripts de despliegue, que se borraron.
- **El manifiesto de tarballs**, que no existía completo en ningún lado.
- **`procesar_cadena_completa.sh` se borró**, y con él el árbol `/data/products/*` y la última
  referencia a `polar2grid_v3.1.sif`. Cierra el pendiente 7.

### Lo que sigue abierto, sin orden

- Confirmar los **59 GeoTIFF y 3 vistas** de Level 1 con una pasada **diurna**. Con la
  nocturna la cuenta cuadra por aritmética (43 + 14 bandas reflectivas + 2 RGB), no de frente.
- Las **dos asperezas de la barra de color** (el recuadro negro sobre negro, y `--lat-south`,
  que casi nunca reserva espacio con rejillas dinámicas). Van con el pendiente 9.
- **Qué más se pide de ATMOS** (pendiente 14): hay que enseñarle la lista de
  `--list-products-all` a los colegas. Es decisión de producto, no técnica.
- **Cómo llega un RAW a tahan.** `recibe.sh` está listo para cuando exista ese camino, pero
  hoy tahan no está conectado a la antena y el camino —copia, montaje, `rsync`— no está en el
  repositorio. No bloquea nada: la cadena se prueba con `--clave`.
- **Criósfera** sigue dándose por bloqueada por la misma clase de argumento que resultó falso
  en inundaciones. Ver la advertencia sobre `referencia/` en `CLAUDE.md`.

---

### El DNB nocturno salió bien: `--percentiles` funciona con datos reales

Era el último de los tres pendientes del 0814 que seguía probado solo con un `apptainer`
simulado. La vista de `dynamic_dnb` de la pasada nocturna del 2026-08-14 (09:23 UTC,
`wgs84_geo_750m`) enseña luces de ciudad de todo el occidente de México y del suroeste de
Estados Unidos, con estructura de nubes visible sobre el Pacífico y el golfo de California:
o sea que el estirado por percentiles hace exactamente lo que tenía que hacer, y de paso es la
primera prueba con datos reales del `vestir()` nuevo en Level 1. El rótulo sale completo
—`NOAA-20 DNB Dynamic 2026/08/14 09:23Z`—, así que la entrada `dynamic_dnb` de `product_map`
también quedó ejercitada.

Las franjas negras horizontales de la mitad norte son la interferencia de antena de siempre
(ver "Hallazgos"), no un problema del renderizado.

La corrida (`j01_d20260814_b45273`, 1m 18s) dejó **43 GeoTIFF y 1 vista**: M 25, I 11, DNB 7,
RGB 0. No son los 59 GeoTIFF y 3 vistas que esperaba la nota anterior, y la diferencia se
explica sola: **de noche no hay bandas reflectivas ni RGB**.

```
M  25 + 11 reflectivas (M01–M11) = 36
I  11 +  3 reflectivas (I01–I03) = 14
DNB 7                            =  7
RGB 0 +  2                       =  2
                                   --
                                   59
```

O sea que la cuenta de 59, que llevaba sin confirmarse desde que se pasó a un solo algoritmo
de DNB, **queda verificada por la vía indirecta**: es exactamente lo que sale al sumarle a esta
pasada las 14 bandas reflectivas y los dos RGB que la noche se lleva. Falta confirmarla
directamente con una pasada diurna, que es trámite.

Lo importante es **quién filtra los RGB**: los filtra Polar2Grid, que directamente no los
produce. No salen en negro, así que el código 3 de `geotiff2view` ni tuvo que actuar. La cadena
de Level 1 se comporta bien de noche sin que nadie lo hubiera previsto explícitamente, y con
7 GeoTIFF de DNB (6 son ángulos) sale la única vista, que es la que se quería.

### El tipo de nube: la enumeración autoritativa, y no era ninguna de las dos hipótesis

La comparación con la vista de CLAVR-x de la misma pasada (`j01_d20260813_b45264`) había
mostrado un corrimiento de −1, y de ahí salió la hipótesis de que JRR fuera "CLAVR-x sin
Prob. clear". El `ncdump -h` completo del `JRR-CloudPhase` descartó que el archivo traiga la
respuesta: `CloudType` solo declara `long_name`, `coordinates`, `_FillValue`, `units` y
`valid_range = 0b, 8b`, **sin `flag_meanings`**. Tampoco está en el manual de CSPP ATMOS ni en
la documentación de Polar2Grid, que no trae realce para `CloudType` (sí para `CloudPhase`, con
paleta embebida de seis clases).

Donde sí está es en la **Tabla 30 del ATBD del algoritmo empresarial de nubes de NOAA**
([ATBD_EPS_Cloud_CldType_v3.0](https://www.star.nesdis.noaa.gov/JPSS/documents/ATBD/ATBD_EPS_Cloud_CldType_v3.0.pdf)),
que es de donde viene el producto:

```
0 Clear                     6 Optically Thin Ice
1 Spare                     7 Multilayered Ice
2 Liquid Water              8 Cloud type could not be determined
3 Supercooled Liquid Water
4 Mixed Phase
5 Optically Thick Ice
```

Explica las dos observaciones —el 2 es agua y el 6 es hielo delgado, o sea cirros— pero la
hipótesis fallaba en los extremos: el **1 es un hueco reservado** que el algoritmo nunca emite,
no Fog, y el **8 es "no se pudo determinar"**, no Overshooting. JRR no tiene Fog, ni
Overshooting, ni Unknown, ni Dust, ni Smoke: son dos algoritmos distintos, no una lista
recortada. La misma tabla, en su versión de fase (Tabla 31), confirma las seis clases de
`CloudPhase` —`0 Clear, 1 Liquid Water, 2 Supercooled, 3 Mixed, 4 Ice, 5 no determinada`—, que
son las que ya pinta la paleta embebida de Polar2Grid.

`cloud_type_jrr.cpt` quedó corregido con esas etiquetas, y con los colores mapeados **por
significado** a los de `cloud_type.cpt` (agua azul, sobreenfriada cian, mixta rosa, hielo
grueso rojo, hielo delgado amarillo, multicapa naranja) para que las dos vistas se puedan
comparar de un vistazo.

### La comparación con CLAVR-x: pasa, y por qué se puede afirmar

Hecha el 2026-08-15 sobre `j01_d20260813_b45264`, con la vista nueva ya recompilada (rótulo
`NOAA-20 Cloud Type 2026/08/13 19:11Z`) contra la PNG de `ql_clavrx.sh` de la misma pasada.

Lo que hay que verificar no es que las dos imágenes se parezcan —son dos algoritmos con dos
listas de clases— sino que el mapeo de las trece de CLAVR-x a las nueve de JRR sea
**consistente**: varias clases de CLAVR-x cayendo en una sola de JRR, y nunca una clase de JRR
repartida entre clases físicamente incompatibles. Eso es lo que se observa:

| CLAVR-x | JRR | Dónde se ve |
|---|---|---|
| Water (azul) **+ Fog (verde)** | Agua | filigrana de la Sierra Madre, cúmulos del Pacífico, y las manchas verdes de CLAVR-x sobre el sur de México y Yucatán |
| Opaque Ice (rojo) **+ Overshooting** | Hielo grueso | los núcleos convectivos del golfo y del sur, en las mismas posiciones |
| Cirrus (amarillo) | Hielo delgado | los yunques alrededor de esos núcleos |
| Super cool (cian) | Sobreenfriada | los mismos parches, p. ej. el del centro de México junto al complejo convectivo |
| Clear + Prob. clear (dos grises) | Despejado | el interior de México y el golfo |
| Unknown (blanco) | Indeterminado | el borde superior del swath |

**El verde de CLAVR-x saliendo azul en la nuestra es la confirmación clave**: JRR no tiene
clase Fog, la niebla es agua líquida. Y explica al revés el síntoma que abrió todo esto — con
las etiquetas viejas no es que la niebla se rotulara mal, es que *todas* las nubes bajas de
agua salían rotuladas "Fog".

Un corrimiento de índice no puede producir un mapeo así: repartiría nuestro azul entre clases
sin relación física entre sí. Que sea muchos-a-uno y coherente en las seis familias es la
prueba, no el parecido.

**El recuadro `Sin uso` no aparece en el mapa**: ni un píxel gris oscuro en toda la escena, que
es lo que predice el "Spare" del ATBD para el valor 1.

Queda una diferencia real, que no es de etiquetas: **JRR detecta bastante más hielo delgado**
que CLAVR-x, sobre todo del lado del golfo, donde CLAVR-x pone Clear o Water. Es diferencia de
algoritmo —un error de etiquetas sería sistemático y este no lo es— pero conviene vigilarla
cuando se compare con otra pasada, porque es lo que más va a saltar a la vista de quien esté
acostumbrado a la imagen vieja.

El rótulo vacío tenía otra causa, más simple de lo que decía la nota del cierre anterior: la
entrada `cloud_type` **ya estaba** en `product_map`, pero es la de CLAVR-x. Polar2Grid nombra al
producto de JRR con el nombre de la variable del NetCDF, `CloudType`, que en minúsculas es
`cloudtype` y no casa con ese token. Se agregó la pareja, igual que ya existía para la fase
(`cloudphase` de JRR junto a `cloud_phase` de CLAVR-x).

**Cómo llegan los dos arreglos a producción es distinto**, y conviene no confundirlo: el `.cpt`
es colortable, va montada desde el host, así que basta con `git pull` + `install.sh` en tahan.
`metadata.py` es código y viaja dentro del `.sif`, así que hay que recompilar con el pin en
`f1d0c60` — y para eso el commit tiene que estar **empujado** a GitHub, porque el `.def` clona
de ahí y no del host. Los dos pasos ya se hicieron el mismo día; de ahí que la vista de la
comparación traiga el rótulo completo.

De paso: el pin estaba escrito **dos veces** en `polar2grid_v3.2-mapdrawer.def` —en `%post` y
en la etiqueta `LANOT_tools_commit` de `%labels`, que es lo único consultable con
`apptainer inspect` sobre un `.sif` ya hecho— y la etiqueta se había quedado en `a5d8d98`
mientras el pin iba en `a7c774a`. Ahora las dos apuntan a `f1d0c60` y hay un comentario que
pide moverlas juntas.

### Lo que sí quedó bien, verificado con datos reales el 2026-08-15

- **La barra de color de inundaciones**, con sus 18 recuadros y las etiquetas del propio
  producto. La vista se lee sola: océano en `Agua nor.`, tierra en `Suelo/veg.`, nubes en
  `Nube` y las manchas rojas del delta del Misisipi en el extremo alto de la fracción.
- **El nombre uniforme** `noaa20_viirs_flood_…`, que ya ordena junto al resto de su pasada.
- **El `-p` explícito de ATMOS**, que entrega los siete de siempre más `CloudType`.

### Dos asperezas menores de la barra de color

Las dos se ven en la vista de inundaciones y no valen una corrida por sí solas:

- **El recuadro "Sin datos" es negro sobre fondo negro**: se lee la etiqueta pero no se ve el
  color. Lo mismo le pasaría a cualquier paleta con una clase negra. Opciones: quitarlo del
  CPT —el negro se explica solo— o darle un borde a los recuadros en `_draw_colorbar()`.
- **La barra se encima al mapa** en vez de tener espacio propio. `--lat-south 11` solo reserva
  espacio *si el borde sur de los datos está al norte de esa latitud*, y en esta pasada el
  swath llega a 5°S. O sea que no es un fallo, es la condición documentada de la bandera; pero
  con las rejillas dinámicas actuales casi nunca se va a cumplir. Va con el pendiente 9.

### Lo que sigue, en orden

El tipo de nube quedó cerrado: etiquetas, rótulo, despliegue y comparación. Lo que sigue
abierto de esta tanda es menor:

1. **Confirmar de frente los 59 GeoTIFF y 3 vistas de Level 1 con una pasada diurna.** Con la
   nocturna la cuenta cuadra por la vía indirecta, pero conviene verla directa. Es trámite.
2. **Las dos asperezas de la barra de color** de aquí arriba, que no valen una corrida por sí
   solas y se pueden juntar con el pendiente 9.
3. **Decidir qué más se pide de ATMOS** (pendiente 14), que es decisión de producto: hay que
   enseñarle la lista de `--list-products-all` a los colegas del laboratorio.

Y una advertencia que vale para la próxima paleta categórica, ya sea de ATMOS o de otro
bundle: la imagen contra la que se compara **no la hace Polar2Grid**.
`referencia/cspp_7_clavrx.sh`, que se trajo el 2026-08-15, muestra que ahí Polar2Grid solo
produce GeoTIFF `float32` sobre la misma rejilla `wgs84_geo_750m`; la PNG la hace
`ql_clavrx.sh`, el quicklook del propio bundle, con su paleta. Es el mismo patrón de flood, y
ya van dos. Así que la comparación es siempre **por significado, no por color**.

---

## Dónde quedó el 2026-08-14 (cierre de la sesión)

**Lo primero al retomar**: en el repositorio quedaron **cuatro commits sin empujar**
(`3a29383`, `dd2a5ce`, `59619d7`, `16f933a`). Sin ese `push`, un `git pull` en tahan no trae
nada. `LANOT_tools` sí quedó al día en el remoto, en `a5d8d98`.

**Secuencia de despliegue, y el orden importa:**

1. `git push` del repositorio (LANOT_tools ya está).
2. `git pull` de los dos en tahan.
3. **Recompilar `polar2grid_v3.2-mapdrawer.sif`.** El pin subió a `a5d8d98`, que es donde vive
   `--percentiles`; sin recompilar, `run_polar2grid_l1.sh` le pasa a `geotiff2view` una
   bandera que su contenedor no conoce.
4. Correr la **cadena de Level 2 completa** antes de los renderizadores. Ya no basta con los
   dos `run_polar2grid_*.sh`: `run_flood_edr.sh` es ahora quien produce el `.tif` de
   inundaciones que el renderizador viste.

**Qué se probó y qué no.** Con datos reales: la SST corregida (verificada en la pasada
nocturna del 0814), las paletas, los nombres de producto, y la comparación de los cuatro
algoritmos de DNB sobre tres pasadas. **Solo con un `apptainer` simulado**, o sea sin
ejercitar nunca: el bloque de **incendios**, el de **inundaciones**, y el `--percentiles` del
DNB. Esos tres son lo primero que hay que mirar en la próxima corrida.

**Primera corrida real de inundaciones (tahan, 2026-08-14 19:38, pasada `j01_d20260814_b45273`)**:
falló con código 2, y por dos razones encadenadas que conviene separar.

1. **Comillas sin escapar** en el `bash -c` de `run_flood_edr.sh`: el `echo "--- Fusionando…"`
   cerraba la cadena del shell de afuera y partía el guion. Como bash ejecuta lo que va
   leyendo, CSPP corrió entero y el guion murió al final, en el `if` sin `fi`
   (`Fusionando: -c: line 38: syntax error: unexpected end of file`). Corregido, y verificado
   sin contenedor con el truco que quedó anotado en `CLAUDE.md`.
2. **La pasada era nocturna** —09:23 UTC ≈ 03:23 local—, así que no había productos que
   trasladar de todos modos: flood trabaja con las bandas reflectivas I01–I05. O sea que el
   `.tif` fusionado **sigue sin ejercitarse**, igual que el bloque de incendios.

**Segunda corrida, ya sobre una pasada diurna** (`--pasada d20260813`, opción nueva; la
autoselección toma la más reciente y esa era la nocturna): **10 productos en 4m 3s**, y por fin
se ejercitaron `cspp_viirs_flood2tif.sh` y `cspp_viirs_tifmerge.sh`. Los dos funcionan. Lo que
falló fue el destino: **`cspp_viirs_tifmerge.sh` no acepta `-o`**. No protesta, pero tampoco
escribe en la ruta pedida: nombra él la salida —sello de inicio del primer gránulo, de fin del
último, su propia marca de creación y sufijo `_merged`— y la deja junto a la entrada. O sea que
la fusión **sí se había hecho** y estaba en `/data/tmp/flood_work_479021`, mientras
`geotiff/flood` quedaba vacío; sin `-k` se habría borrado sin dejar rastro. Ahora el script
busca el `*_merged.tif` y lo renombra al nombre que el renderizador filtra
(`SAT_viirs_flood_FECHA_HORA`), y el resumen distingue "hay `.nc`" de "hay `.nc` y GeoTIFF" —
antes decía `✅ ÉXITO` sin haber mirado nunca el `.tif`.

Lo que sí quedó confirmado del nombre: los `.nc` de v2.0 llevan `_s<15 dígitos>`
(`VIIRS-Flood_v2r0_n20_s202608131911067_e…_c….nc`), que es de donde sale el `AAAAMMDD_HHMMSS`.

**A vigilar**: el fusionado pesa **211 MB** por pasada, sin comprimir. Es un Byte con paleta,
así que un `-co COMPRESS=DEFLATE` lo bajaría muchísimo; hoy son ~400 MB diarios en
`geotiff/flood` si hay dos pasadas diurnas.

De paso salió que la verificación de "cero productos" estaba mal: usaba `successful_runs`,
que aquí venía lleno pese a no haber generado nada, así que la pasada nocturna habría dado un
error falso. Ahora se decide con `VIIRS Flood output files = [...]` (ver "Hallazgos"), y `-k`
conserva también el directorio de trabajo, que es donde quedan los logs por gránulo.

**Y con eso se cerró el renderizado de Level 2**: `run_polar2grid_edr.sh --pasada d20260813`
entregó 25 GeoTIFF y 11 vistas en 3m 24s, incluidas por primera vez la de incendios y la de
inundaciones. Las dos se revisaron a ojo:

- **Inundaciones**: correcta. El rótulo dice "NOAA-20 Flood", que es la prueba de que
  `product_map` tiene su entrada — sin ella `mapdrawer` no tiene respaldo y habría salido
  "NOAA-20" a secas. La paleta viene embebida en el `.tif`, así que quedó validada la rama de
  `mapdrawer` de `vestir()`, que se había quedado sin usuarios al retirar los RGB de
  superficie.
- **Incendios**: la barra de confianza y el rótulo salen bien, pero los detectados son
  píxeles sueltos de 375 m sobre fondo negro, así que a pantalla completa la vista se lee
  como una imagen negra con motas. Habría que dilatar los puntos o componerlos sobre el
  `true_color` de la misma pasada; es trabajo de `geotiff2view`, no de estos scripts.
  **Se deja como está**: así se generan hoy en producción.

**La barra de color de flood, resuelta el 2026-08-14.** La vista salía sin barra, o sea sin
forma de saber qué significan el azul, el verde o el rojo. No hizo falta tocar `mapdrawer`:
su `--colorbar` busca la paleta en tres lugares por prioridad —el tag de texto `colormap` del
TIFF, el `--cpt` externo y el colormap nativo de rasterio— y el `--cpt` gana sobre el nativo.
Con solo `--colorbar` habría salido una barra de las 256 entradas, **70 de ellas negro de
relleno**, sin etiquetas y numerada 0-255.

El `colortables/flood.cpt` nuevo toma los colores de la tabla que incrusta
`cspp_viirs_flood2tif.sh` y las etiquetas del atributo `WaterDetection:TypeDescription` del
propio NetCDF —10 clases más la fracción de agua—, no de inferir de los colores. Dos detalles
que importan si alguien lo edita:

- **La primera columna es el número de recuadro, no el valor del dato**, como en `glm_fed.cpt`.
  Con los valores reales (1, 15, 16, 20, 27, 30, 38, 50, 99, 100-200) la barra saldría casi
  toda negra: `_draw_colorbar()` pinta todos los índices entre el mínimo y el máximo y la rama
  discreta de `load()` deja en negro los que el archivo no menciona. Sirve para la leyenda, no
  para recolorear: `mapdrawer` no recolorea, y la imagen ya trae su paleta.
- **`Bareland` y `Vegetation` comparten color** en la tabla original, así que van en un solo
  recuadro. Dos recuadros idénticos harían creer que se distinguen.

Como las paletas se montan desde el host, esto **no necesita recompilar**: basta `install.sh`
de LANOT_tools en tahan y un `git pull` de la cadena.

**La vista de inundaciones NO está en otro marco**, aunque lo parezca. Se anotó primero que sí
—su `.tif` sale de `gdal_translate` del bundle de CSPP y nunca pasa por el remuestreo de
Polar2Grid, y la imagen muestra el swath como un paralelogramo rotado sobre negro— pero los
números dicen lo contrario. El log de flood reporta
`límites detectados: (-116.353, 48.314, -71.279, -5.020)` y el GeoTIFF de NDVI de la misma
pasada, que sí pasó por Polar2Grid en `wgs84_geo_750m`, va de `(-116.3074, 48.3209)` a
`(-71.2726, -5.0304)`: **la misma extensión, con diferencias de centésimas de grado**. El
paralelogramo es el swath dibujado dentro del mismo rectángulo que usan todas.

Lo que sí es cierto es que ese rectángulo llega de 48°N a 5°S, muy fuera del dominio — pero
eso le pasa a **todas** las vistas de la pasada, no a flood: las rejillas de `config/grid.yaml`
son **dinámicas**, fijan proyección y resolución pero no extensión, así que cada pasada
enmarca lo que abarque su swath. Es el pendiente 9, y flood no necesita ningún `gdalwarp`
propio: se arregla cuando se arreglen todas.

También quedó una inconsistencia de nombres, **resuelta el 2026-08-14**: la vista de flood
salía como `j01_viirs_flood_…` y el resto como `noaa20_viirs_…`, porque el prefijo de flood lo
ponemos nosotros y el del resto lo pone Polar2Grid, así que en `vistas/` el archivo de
inundaciones quedaba ordenado aparte de todo lo demás de su pasada. Ahora los dos scripts
traducen el código con la misma función `sat_polar2grid()` (`j01`→`noaa20`, `j02`→`noaa21`,
`npp`→`npp`): `run_flood_edr.sh` la usa para nombrar el `.tif` y `run_polar2grid_edr.sh` para
construir el ERE con que lo busca. **Las dos definiciones tienen que moverse juntas**; están
duplicadas a propósito, como el resto de los ayudantes, porque cada `run_*.sh` es autónomo.

El código de los SDR (`j01`) se sigue usando para todo lo demás: leer nombres de entrada,
armar la clave de la pasada y nombrar el marcador. Lo que cambia de forma es solo la salida
que comparte árbol con Polar2Grid. Los archivos ya generados con el nombre viejo **no se
renombran solos**: hay un `j01_viirs_flood_20260813_191106.tif` de 211 MB en `geotiff/flood` y
su JPG en `vistas/flood` que hay que mover o borrar a mano.

**Lo que cambió en la cadena**, por si el resumen no cuadra con lo esperado:

| Script | Antes | Ahora |
|---|---|---|
| `run_polar2grid_l1.sh` | 62 GeoTIFF, 6 vistas | 59 y 3 — un solo algoritmo de DNB |
| `run_polar2grid_edr.sh` | 24 GeoTIFF, 11 vistas | + incendios, + vista de flood, − RGB de superficie |
| `run_flood_edr.sh` | solo `.nc` | `.nc` + el `.tif` fusionado en `geotiff/flood` |

**Decisiones que quedaron tomadas y no hay que rediscutir**: los RGB salen de Level 1 y no de
Level 2; del DNB se pide solo `dynamic_dnb`; `evi.cpt` va de 0 a 1; el falso color se llama
Day Land Cloud Fire. El razonamiento de cada una está en "Revisión de las vistas".

**Lo siguiente, en orden**: la orquestación (`plan_orquestacion.md`, diseñado y sin escribir),
y criósfera — que hoy se da por bloqueada por falta de lector, pero con el antecedente de
flood conviene revisar antes si CSPP Cryosphere trae su propio convertidor.

---

## Lo que corre hoy de punta a punta

Probado en tahan con datos reales, todo sobre la misma pasada: **`j01_d20260811_b45236`**
(NOAA-20, 11 gránulos, 19:47–20:03 UTC). La excepción es OMPS, que corrió sobre
`b45237`: es el mismo sobrevuelo (19:49–20:02 UTC), pero sus archivos llevan la órbita
siguiente. Ver el pendiente 8.

| Eslabón | Script | Resultado |
|---|---|---|
| RAW → Level 0 | `run_rt_stps.sh` | 10 RDR |
| Level 0 → Level 1 | `run_sdr.sh` | 28 SDR de VIIRS |
| Level 2 atmósfera | `run_atmos_edr.sh` | 132 productos, 7m 30s |
| Level 2 superficie | `run_lsr_edr.sh` | 11 productos, 1m 37s |
| Level 2 criósfera | `run_cryo_edr.sh` | 22 productos, 5s |
| Level 2 incendios | `run_active_fire_edr.sh` | 11 productos, 2m 47s |
| Level 2 SST | `run_acspo_edr.sh` | 1 producto, 1m 48s (la imagen ahora la hace Polar2Grid) |
| Level 2 inundaciones | `run_flood_edr.sh` | 11 productos, 4m 34s |
| Level 2 ozono | `run_omps_edr.sh` | 39 productos (V8TOz 20, V8PRO 19), 28s — pasada `b45237` |
| Vistas de Level 1 | `run_polar2grid_l1.sh` | 62 GeoTIFF (M 36, I 14, DNB 10, RGB 2) y 6 vistas (dnb 4, rgb 2), 4m 8s |
| Vistas de Level 2 | `run_polar2grid_edr.sh` | 24 GeoTIFF (atmos 7, lsr 14, lsr_rgb 2, sst 1) y 11 vistas (atmos 6, lsr 2, lsr_rgb 2, sst 1), 3m 46s |

Los conteos de vistas de esas dos filas estuvieron mal hasta el 2026-08-14, cada uno por su
lado: el de Level 1 decía 12, que es de antes del filtro ERE, cuando los
`--dnb-angle-products` también se vestían (10 + 2); el de Level 2 decía 8, que es de antes
de que existieran `cloud_fraction.cpt`, `ndvi.cpt` y `evi.cpt` (atmos 5 + lsr_rgb 2 +
sst 1). Los de arriba son los del árbol real de la corrida del 2026-08-13, 17 vistas en
total.

El 2026-08-14 se revisaron esas 17 vistas y salieron cinco correcciones (ver "Revisión de
las vistas"). Dos cambian los conteos:

- **Level 2**: **medido el 2026-08-14** sobre `j01_d20260813_b45264`, ya con incendios e
  inundaciones: **25 GeoTIFF (atmos 7, lsr 14, sst 1, fire 3) y 11 vistas (atmos 6, lsr 2,
  sst 1, fire 1, flood 1)** en 3m 24s. La predicción de 22 y 9 era de antes de incendios;
  incendios aporta 3 GeoTIFF y **una sola** vista, porque de sus tres productos solo
  `confidence_cat` tiene paleta, y flood aporta una vista sin GeoTIFF propio en este script
  —el suyo lo hizo `run_flood_edr.sh`—.
- **Level 1**: del DNB se pide un solo algoritmo en vez de cuatro, así que el bloque pasa
  de 10 a 7 GeoTIFF (6 son los ángulos) y de 4 a 1 vista: **59 GeoTIFF y 3 vistas**. Falta
  volver a correrlo para confirmarlo.

De esa misma corrida salió confirmada **la trampa de la órbita en los incendios**: los
AFIMG de la pasada se repartieron `b45264` (el primer gránulo) y `b45265` (los otros
nueve), y el staging por ventana temporal enlazó los diez. Enlazar por órbita, que es como
se hace con los SDR, habría perdido nueve.

Cada eslabón sabe qué le toca procesar, no repite trabajo y distingue "terminó sin error"
de "produjo algo". Las convenciones comunes están en `CLAUDE.md`.

---

## La cadena completa, de RAW a vistas — 2026-08-17

**Primera corrida del orquestador de punta a punta sobre una pasada nueva.** Hasta hoy los doce
eslabones se habían probado uno por uno; `procesar_pasada.sh` solo se había ejercitado en
`--dry-run`. Pasada `j01_d20260817_b45321` (NOAA-20, 13:36 CST, diurna), **29m 04s**, las diez
etapas en `ok`.

| Etapa | Duración | Productos |
|---|---|---|
| `rt_stps` | — | 5 RDR |
| `sdr` (5 sensores) | — | VIIRS 28, ATMS 63, CrIS 32, OMPS-NM 38, OMPS-NP 40 |
| `atmos` | 6m 57s | 108 |
| `acspo` | 1m 31s | 1 |
| `fire` | 2m 44s | 9 |
| `flood` | 4m 36s | 9 + 1 geotiff fusionado |
| `omps` | 28s | 38 |
| `p2g_l1` | 3m 14s | **59 geotiff, 3 vistas** |
| `lsr` | 1m 34s | 9 |
| `cryo` | 19s | 18 |
| `p2g_edr` | 3m 22s | **26 geotiff, 11 vistas** |

Los conteos de renderizado **coinciden con la referencia** del 11 y 13 de agosto (59/3 y 25/11).
El GeoTIFF de más en Level 2 es `CloudType`, que se agregó el 14 y no estaba en aquella medición;
por eso también son 7 vistas de ATMOS y no 6.

La estimación previa a la corrida —25 min por ruta crítica, 30 con holgura, calculada de las
duraciones de los marcadores— salió a 29m 04s. Vale la pena recordar el método: las duraciones
de Level 2 están en los marcadores, y para RT-STPS y SDR, que no las registran, se sacan del
mtime del log menos la hora que lleva su nombre.

Tres cosas que se aprendieron de la corrida:

- **`lsr` dio 1 vista y no 2**, y está bien: el EVI salió sin un solo píxel válido y
  `geotiff2view` devolvió 3, así que no se publicó un JPG en negro. Es el diseño funcionando.
- **`omps` se reportó como "ya estaba" habiendo corrido.** Defecto del resumen, no de la etapa:
  ver el pendiente 17.
- **Las vistas traen franjas negras horizontales al pie**, idénticas en el RGB y en el DNB. Como
  esos dos no comparten lector, el origen está en los SDR y no en el renderizado: son las
  costuras de gránulos truncados, o interferencia de antena, que se ven igual. **Preguntar por el
  estado de la antena antes de buscarlo en el código.**

El directorio de logs de esa capa pasó de `orquestador/` a **`cadena/`** el mismo día. El nombre
viejo describía a un solo script, pero ahí escriben tres —`recibe.sh`, `procesar_pasada.sh` y
`barrer_pendientes.sh`—, y lo que comparten no es orquestar sino operar sobre la cadena entera,
frente a las carpetas hermanas, que se llaman como el software de su etapa (`rt-stps`,
`cspp-sdr`, `cspp-edr`, `polar2grid`). La variable de entorno es ahora `CADENA_LOG_BASE`. En
tahan el directorio se movió con `mv`, así que los logs viejos siguen ahí.

Y es la primera vez que se ve `--font-bg` sobre un producto real de VIIRS: el título se lee
limpio sobre nube brillante, que es el caso que un sondeo no podía probar.

## Tareas programadas

Qué debe quedar en el `crontab` de `lanotadm`. **Ninguna está confirmada como activa**:
falta cotejar contra un `crontab -l` en tahan.

| Tarea | Frecuencia | Por qué | Estado |
|---|---|---|---|
| `update_sdr_daily.sh` | diaria | LUTs de calibración y TLE/GFS de CSPP SDR. Sin esto, la calibración se degrada con los días. | Existe desde antes; **verificar si está en cron** |
| `update_atmos_ancillary.sh` | 4× al día (`17 2,8,14,20 * * *`) | CMCSST, GFS y mapa de nieve de ATMOS. El manual pide cuatro por las cuatro corridas del GFS. Incluye el podado a 14 días. | **Pendiente de montar** |
| `update_heap_ancillary.sh` | semanal (`40 3 * * 0`) | **Solo poda.** HEAP baja su GFS por su cuenta al correr, pero el manual (§1.6.3) avisa que no lo borra nunca. Sin esto, `/data/ancillary/heap` crece indefinidamente. | **Escrito el 2026-08-15; pendiente de montar** |
| `barrer_pendientes.sh` | cada 15 min (`*/15 * * * *`) | Recoge los RAW que se quedaron atrás: los `run_*.sh` no miran hacia atrás, y una pasada que llegue con el candado tomado se descarta. | **Escrito el 2026-08-15; pendiente de montar** |
| `obtener_tarballs.sh --novedades` | mensual | CSPP no tiene lista de correo ni RSS: de una versión nueva uno se entera si entra a la página. | **Escrito el 2026-08-15; pendiente de montar** |
| Rotación de logs | diaria | `/var/log/lanot/polares/*/*.log` crece sin límite. Hay una configuración de `logrotate` propuesta en `README_SCRIPTS.md`. | **Pendiente de aplicar** |
| Limpieza de productos | por definir | Los `JRR-*` se duplican en cada reproceso (pendiente 5). | **Sin escribir** |

Los `run_*.sh` **no van en cron**: los encadena `procesar_pasada.sh`, que a su vez lo dispara
`recibe.sh` cuando llega un RAW. Lo único periódico de la cadena es el barrido.

Las rutas del cron son las de la instalación, `/opt/lanot/polares/scripts/`, no las del clon.

La preparación del servidor —`preparar_servidor.sh`— se ejecuta una sola vez, nunca en cron.
`instalar.sh` va en cada despliegue, a mano.

---

## Revisión de las vistas — 2026-08-14

Se miraron las 17 vistas de `j01_d20260811_b45236`. Cinco problemas, los cinco resueltos —
el del DNB necesitó además una pasada nocturna, corrida el 2026-08-14. Lo que hay que
saber de cada uno:

**1. La SST salía con fondo rosa.** No era la paleta: `sst.cpt` ya traía `B 0 0 0`. Era que
la llamada de ACSPO en `run_polar2grid_edr.sh` usaba `$P2G_COMUN` en vez de `$P2G_DATOS`,
o sea sin `--dtype float32 --no-enhance`, y entregaba una **imagen realzada de 8 bits con
el sin-dato en un canal alfa** que `geotiff2view` no lee. Detalle en los hallazgos. Ya
corregido; el rango 268–310 K se queda como estaba.

**2. Nombres de producto en la etiqueta.** Cinco vistas decían "NOAA-20 VIIRS" y dos solo
"NOAA-20", porque `product_map` de `LANOT_tools/metadata.py` no tenía sus tokens. Se
agregaron `false_color`, `cldbasehght`, `cloud_fraction`, `aod550`, `ndvi`, `evi` y los
cuatro algoritmos de DNB. Ahora las 17 llevan nombre.

**3. DNB: resuelto el 2026-08-14 con tres pasadas.** Se queda **solo `dynamic_dnb`**; el
detalle está abajo, en "El DNB, resuelto".

**4. NDVI y EVI.** Las rampas están bien; el fondo ya estaba arreglado y `evi.cpt` pasó a
0..1 (pendiente 1). Se levantó una duda —que las nubes se pintaran como suelo desnudo— y
resultó falsa alarma: LSR ya las enmascara. Ver el pendiente 12.

**5. `rgb` y `lsr_rgb` no eran duplicados, pero lo parecían.** Son dos composiciones
distintas —`viirs_sdr` sobre los SDR (TOA + Rayleigh + afilado con I01) y `viirs_edr` sobre
los `SurfRefl_*` de LSR— que se ven casi iguales porque TOA con Rayleigh ≈ reflectancia de
superficie, y que además quemaban el mismo texto. **Se decidió quedarse de momento con los
de Level 1**: `run_polar2grid_edr.sh` ya no hace RGB de superficie. El criterio fue la
disponibilidad — los de Level 1 salen siempre, los de superficie exigen que corra LSR, que
a su vez exige ATMOS. El falso color resultó ser el RGB **Day Land Cloud Fire** (M11 SWIR
2.25 µm / I02 NIR 0.86 µm / I01 rojo 0.64 µm), y ese es el nombre que lleva ahora.

Es reversible y está pensado para serlo: el encabezado de `run_polar2grid_edr.sh` explica
cómo recuperar la llamada, y `vestir()` conserva su rama de `mapdrawer` aunque hoy no la
use nadie. Falta comparar los dos con la corrección atmosférica en mente antes de dar la
decisión por definitiva.

---

## Pendientes, en orden sugerido

### 0. Infraestructura para producción — lo único que no es software

Rescatado de `notas.txt` el 2026-08-17, antes de borrarlo. Era lo último que ese archivo
listaba como faltante y no estaba anotado en ningún otro lado:

- ~~**Terminar de armar `/datawork` con los dos discos que faltan.**~~ **Hecho el
  2026-09-14.** El plan para operar sobre él está en `plan_operacion_datawork.md`.
- **Organizar el clúster con Slurm**, de acuerdo al plan. El plan institucional *Plan Cluster
  LANOT 2026-2027* lo pone en operación en Q4 2027, con la cadena polar como piloto; mientras
  tanto, el reparto entre servidores lo hace la cola de `plan_operacion_datawork.md` (fase 3).
  Siete `run_*.sh` traen cabecera `#SBATCH`, pero piden una partición, `normal`, que no existe
  en el borrador de `slurm.conf`. Todos usan `${SLURM_CPUS_PER_TASK:-N}` /
  `${SLURM_JOB_ID:-$$}` para funcionar igual con o sin Slurm.

Todo lo demás de esta lista es software. **Poner el sistema en producción ya no espera a
Slurm**: la cola del plan cubre el reparto entre servidores.

### 1. Paletas — revisadas con datos el 2026-08-14
`ndvi.cpt`, `evi.cpt` y `cloud_fraction.cpt` ya están en `LANOT_tools/colortables` y
registradas en la tabla `PALETAS`. **En el servidor tienen que llegar a
`/usr/local/share/lanot/colortables`** (con `install.sh` de LANOT_tools), que es el
directorio que los scripts montan sobre el del contenedor; si solo están en el clon de
git, el contenedor no las ve.

Vistas con datos: las tres rampas están bien y no se tocan. Lo que salió mal fue el fondo,
y ya estaba corregido antes de mirarlas — las imágenes se renderizaron a las 13:42-13:43 y
el commit `2a9b2d2` de LANOT_tools, que puso `B 0 0 0` en las tres, es de las 13:58 del
mismo día. **Lo único que falta es correr `install.sh` en tahan y volver a renderizar.**

Sí cambió `evi.cpt`: pasó de −1..1 a **0..1**. Era byte-idéntico a `ndvi.cpt` y eso volvía
las dos vistas casi indistinguibles (RMSE 4.7 % entre los JPG), aunque los datos sí
difieren. El EVI está diseñado para no saturarse en vegetación densa, así que vive entre 0
y ~0.6; la mitad negativa de la rampa de NDVI se iba en valores que sobre tierra no
ocurren, y el tramo azul de agua no hace falta porque LSR solo entrega superficie
terrestre. EVI < 0 satura ahora en el beige del 0.0, que es lo correcto: suelo desnudo.

**`CloudLayer` no lleva vista y no necesita paleta.** Su `long_name` lo dice: *"Cloud
Layer Flag. Bit1(lowest flight layer); Cloudy (1); Clear(0)"*, con `valid_range 0..62`.
Es una **máscara de bits** —cinco capas de vuelo, las mismas que enumera `Layer_Frac`,
con el bit 0 sin usar, de ahí que el máximo sea `0b111110`—, así que sus 32 valores son
combinaciones y no una escala. Pintarlos en una rampa sugiere un orden que no existe. Si
alguna vez se quiere ver, el producto es el **número** de capas nubosas (popcount de los
bits, ordinal 0-5), y eso hay que calcularlo.

Decidido el 2026-08-13: **no llevan vista** las bandas M/I con sus ángulos y radiancias,
los 14 `surf_refl_*` ni los ángulos del DNB. Son datos por banda; lo visible son el RGB,
el DNB y los productos geofísicos. Ya está aplicado con el filtro de `vestir()`.

No reciclar un CPT de rango distinto: una paleta equivocada es peor que ninguna vista.
Mientras tanto el script lo anota en el log y sigue, que es lo correcto.

### 2. Precarga de ancillary de ATMOS
`update_atmos_ancillary.sh` no se ha ejecutado nunca. Correrlo a mano una vez y luego
montarlo en cron **cuatro veces al día** (el manual §2.4 lo pide por las cuatro corridas
del GFS):

```
17 2,8,14,20 * * * /opt/lanot/polares/scripts/update_atmos_ancillary.sh
```

Mientras no exista ese cron, `run_atmos_edr.sh` fallará con una fecha nueva, porque usa
`-l` (solo caché local). `--download` es la salida de emergencia.

### 3. Vistas decoradas — decidido el 2026-08-13, falta probarlo
La regla quedó así: **Polar2Grid remuestrea una vez por (lector, rejilla, conjunto de
bandas) y entrega GeoTIFF de datos; lo visual sale de LANOT_tools.** `geotiff2view` para
lo que llega sin paleta, `mapdrawer` para lo que ya es imagen. Está escrita en
`CLAUDE.md`.

Decisiones tomadas:

- **Dos scripts, uno por nivel.** `run_polar2grid_l1.sh` (nuevo) cubre bandas M, bandas
  I y DNB, y sustituye a `referencia/cspp_1_ptog.sh`; `run_polar2grid_edr.sh` se
  queda en Level 2. Con esto la cadena nueva **ya produce RGB**.
- **Los RGB se componen en Polar2Grid**, no apilando bandas con `geotiff2view`: Satpy
  aplica corrección de Rayleigh y afilado por razón con I01, y `geotiff2view.py` solo
  recorta y escala a uint8. Como P2G ya los entrega como imagen, `mapdrawer` solo los
  viste.
- **Los RGB salen de Level 1, no de Level 2** (decidido el 2026-08-14). Al principio se
  componían por los dos caminos: `true_color`/`false_color` con el lector `viirs_sdr` sobre
  los SDR, y `true_color_surf`/`false_color_surf` con `viirs_edr` sobre los `SurfRefl_*`.
  Salían casi idénticos —TOA con Rayleigh ≈ reflectancia de superficie— y encima quemaban el
  mismo texto, así que eran indistinguibles al abrirlos. Se conservaron los de Level 1
  porque están siempre disponibles: los de superficie exigen que corra LSR, y LSR depende de
  ATMOS, así que una falla de ATMOS dejaba la pasada sin ningún RGB. Es reversible —el
  encabezado de `run_polar2grid_edr.sh` dice cómo— y falta compararlos con la corrección
  atmosférica en mente antes de darlo por definitivo.
- **El falso color es el RGB Day Land Cloud Fire**: M11 (SWIR 2.25 µm), I02 (NIR 0.86 µm),
  I01 (rojo 0.64 µm). Vegetación verde brillante, agua negra, nubes de hielo cian, nubes de
  agua blancas. Ese es el nombre que lleva en `product_map`.
- **El DNB se remuestrea una sola vez**, en float32. `cspp_1_ptog.sh` lo hace dos veces
  (datos y realce) sin necesidad: `adaptive_dnb`, `dynamic_dnb`, `hncc_dnb` e
  `histogram_dnb` son productos que calcula Satpy, así que el algoritmo ya está dentro
  del float32 y lo único que falta es el escalado a 8 bits, que hace `geotiff2view`.
  **Verificar una vez con datos reales**: generar un producto por los dos caminos y
  comparar. Si no coinciden, revisar el realce en `$POLAR2GRID_HOME/etc/enhancements/`.
- **Datos y vistas en árboles separados**: `geotiff/{m_bands,i_bands,dnb,rgb,atmos,lsr,acspo}`
  para los `.tif`, `vistas/{dnb,rgb,atmos,lsr,acspo}` para los `.jpg`. Los directorios
  `lsr_rgb` de ambos árboles quedaron huérfanos al retirar los RGB de superficie; se pueden
  borrar a mano en tahan.
- **Una sola imagen de Polar2Grid**, la `-mapdrawer`; se retiró
  `contenedores/polar2grid_v3.2.def`. Consecuencia: esa receta solo compila en un host
  con `/usr/local/share/lanot/{gpkg,logos,docs}`.
- Las rejillas propias están en **`config/grid.yaml`** y se pasan con `--grid-configs`,
  montándolo en `/config/grid.yaml`. Son dinámicas —solo proyección y resolución—, así
  que cada pasada da una extensión distinta.
- Los argumentos de decoración validados en producción están en
  `LANOT_tools/crea_vistas_viirs.sh:96-118` y ya están copiados en los dos scripts.

Preguntas sin responder:

- **Paletas**: resuelto. De los 7 productos de ATMOS llevan paleta 6 — los 4 que ya hacían
  match (`AOD550`, `CldTopHght`, `CldTopTemp`, `CloudPhase`), `CldBaseHght`, que comparte
  unidades con `CldTopHght`, y `Total_Cloud_Fraction`, con `cloud_fraction.cpt` hecho a
  propósito. El único sin paleta es `CloudLayer`, y es deliberado: es máscara de bits. Un
  producto sin paleta no genera vista y no es error.
- ¿De dónde salen hoy los `.tif` de `acspo` y `fire` que consume `crea_vistas_viirs.sh`?
  Los scripts que los generarían no están en cron.
- **Lo que Polar2Grid 3.2 NO cubre.** `--list-products` con el lector `viirs_edr` sobre la
  pasada de prueba devuelve exactamente los 7 productos de ATMOS y los 16 de LSR que ya
  renderizamos. `JRR-ADP`, `JRR-VolcanicAsh` y los `JRR-CloudDCOMP`/`NCOMP` **no están
  soportados**: no es que no los pidamos. Si se quieren, hay que renderizarlos por otra
  vía o esperar a una versión que los incluya. En la lista por omisión aparece además un
  `VLST` (temperatura de superficie) que tampoco está disponible con estos archivos.
- **OMPS** ya está cubierto (`run_omps_edr.sh`, 2026-08-13), y desde el 2026-09-22 también
  su vista, con un convertidor propio en vez del lector de Polar2Grid 3.3. Ver el pendiente 8.

Resuelto de paso: el renderizado de la SST salió de `run_acspo_edr.sh` y ahora es un
bloque más de `run_polar2grid_edr.sh`, que queda como **renderizador único de Level 2**.
Además de unificar rejillas y decoración, corrige un problema real: ACSPO generaba la
imagen ya realzada a 8 bits y encima se le aplicaba `sst.cpt`, una paleta definida en
temperaturas, sobre un arreglo estirado a 0-255. `run_acspo_edr.sh` ya solo produce `.nc`
y perdió su bandera `--no-render`.

**La mudanza quedó a medias hasta el 2026-08-14**: se movió la llamada pero con
`$P2G_COMUN`, sin `--dtype float32 --no-enhance`, así que el realce a 8 bits volvió por la
puerta de atrás —ahora del lado de Polar2Grid— y la vista salía con fondo rosa. Ya corregido
a `$P2G_DATOS`; el detalle está en los hallazgos.

### 4. HEAP (rama ATMS/CrIS) — CORRE, pero NO produce sondeos (2026-08-17)

La imagen (1.45 GB) está en `/opt/containers/cspp_heap_v3.0.sif` y la cadena entera corrió
sobre la pasada `j01_d20260813_b45265`:

```
CrIS 30 archivos (15 gránulos) · ATMS 42 archivos → 30 productos en 23 s
  15 NUCAPS-ALL-HR   intermedio de NUCAPS   ← ni perfiles ni producto final
  15 NUCAPS-OLR      onda larga saliente
```

> **Esto se leyó mal durante dos días.** Se dio por hecho que `NUCAPS-ALL-HR` era "EDR y CCR
> juntos" y que solo faltaba la vista. Es falso: un `ncdump` de ese archivo muestra
> `CrIS_Radiances`, `ATMS_Brightness_Temps`, `Cloud_Fraction` y `Cloud_Height`, y **no tiene
> `Pressure`, `Temperature`, `H2O_MR` ni `Stability`**. El "ALL" es por todos los FOV, no por
> "todo junto". El producto —`NUCAPS-EDR`, los perfiles— **nunca se ha generado**.
>
> El indicio que se dejó pasar fue la duración: 15 gránulos en 23 s. Una recuperación NUCAPS
> es físico-iterativa con transferencia radiativa y no corre a esa velocidad. Ese número se
> celebró como logro cuando era la señal de que el paso caro no se ejecutaba.

**No es la cadena, es el build.** Descartado en este orden, todo verificado en tahan:

| Hipótesis | Cómo se descartó |
|---|---|
| La bandera `-o RO` mal formada | Con `-o R` desaparece el OLR: se parsea letra por letra |
| Falta el ancillary GFS | `/data/ancillary/heap/2026_08_13_225` existía, el día correcto |
| Gránulos rechazados por calidad | El log no menciona `retriev` **ni una sola vez** |
| Nuestros insumos o nuestro staging | **El caso de prueba del fabricante reproduce el fallo** |

La prueba definitiva es §3.3 del manual, con los datos y el comando de CIMSS
(`run_heap.bash -s n21 -i ../input -o RO -p 4 -d $PWD/anc` sobre `nucaps_test_data`):

| | Manual §3.3 | Lo que sale |
|---|---|---|
| Archivos | **48**, 16 por familia | **32** |
| Familias | `NUCAPS-EDR`, `NUCAPS-CCR-AR`, `NUCAPS-OLR` | `NUCAPS-ALL-HR`, `NUCAPS-OLR` |
| Duración | 1–3 min | 41 s |

De los tres productos finales solo sale el OLR. **Corregido el 2026-08-29 con la respuesta de
CIMSS** (ver el pendiente 1): aquí se leyó que "el manual llama `NUCAPS-CCR-AR` al CCR y este
build escribe `NUCAPS-ALL-HR`", como si fuera el mismo archivo con otro nombre. No lo es. El
`ALL-HR` es un intermedio y el `CCR-AR` **tampoco se produce**, así que faltan dos de los tres.
Mientras tanto la rama de sondeos no tiene producto, y todo lo que cuelga de ella queda en
pausa.

`run_heap_edr.sh` ya no puede firmar en falso: exige `NUCAPS-EDR` por nombre, y su diagnóstico
recoge lo ya descartado para que nadie repita el recorrido.

**Los 15 gránulos salen**, pero costó encontrar por qué al principio salían 14. La
recuperación necesita microondas que **envuelvan** al gránulo, no solo que lo toquen: con
traslape estricto, al primer gránulo de la pasada solo le tocaba un ATMS que empieza ya dentro
de él, y se perdía. Medido sobre la misma pasada, cambiando solo `HEAP_MARGEN_ATMS`:

| margen | ATMS enlazados | gránulos con producto |
|---|---|---|
| 0 s | 32 | 14 de 15 |
| **90 s** (por omisión) | 42 | **15 de 15** |

Descartado antes que el gránulo perdido viniera truncado: los 15 `SCRIF` pesan lo mismo
(~28.97 MB). Y el rastro que lo identificó fueron los `NUCAPS-GranuleInfo_*.txt`, que HEAP
deja en el directorio de trabajo y que `run_heap_edr.sh` ahora rescata al directorio de logs
—antes se borraban con el directorio, así que una corrida "exitosa pero parcial" no se podía
investigar después.

Lo que se aprendió costando dos corridas:

**`NUCAPS-ALL-HR` no está en el manual.** §1.7 documenta `NUCAPS-EDR` y `NUCAPS-CCR-AR` por
separado, y aquí se dedujo que la ruta JPSS con `-m HR_IRMW` los entregaba **en un solo archivo
combinado**. Esa deducción era falsa —CIMSS la corrigió el 2026-08-25: `ALL-HR` es un
intermedio y no sustituye a nada—, pero la consecuencia de método se sostiene igual, y es lo
que vale conservar de este párrafo. Por eso
`run_heap_edr.sh` cuenta las familias por lo que hay en el directorio y no contra una lista de
patrones: con la lista, una corrida buena se reportaba como "EDR 0, CCR 0, OLR 14" sobre 28
archivos, y el marcador —del que sale el resumen del orquestador— mentía.

**Los SDR no siempre salen agregados**, aunque `CLAUDE.md` lo daba por hecho. En `level1`
conviven las dos convenciones según cómo haya salido cada corrida de `run_sdr.sh`: la pasada
del 11 dejó un `GCRSO` de 3 min y un `GATMO` de 11; la del 13, quince `GCRSO` de 30 s. La
primera versión sacaba la ventana temporal de un archivo "representativo" y con la segunda
convención le salía de **30 segundos**: enganchaba 4 archivos de ATMS en vez de 32 y HEAP
terminaba en 0 sin un mensaje de error. Ahora la ventana recorre todos los `GCRSO` de la
órbita.

Falta todavía la prueba del propio manual (§3.3) con `CSPP_HEAP_TESTDATA_V3.0.tar.gz`, que no
se bajó. No es urgente ahora que la cadena real funciona, pero sería la forma de separar un
problema del contenedor de uno del script si algo se tuerce más adelante.

Seis cosas del diseño que conviene tener presentes al depurar:

- **El margen de ATMS no es opcional** (`HEAP_MARGEN_ATMS`, 90 s). Con 0 se pierde el primer
  gránulo de cada pasada, en silencio y con la etapa reportando éxito.

- **NPP quedó fuera.** HEAP 3.0 retiró el soporte a S-NPP (§1.2). El script sale en 0 con un
  aviso, no en 1: es trabajo imposible, no un fallo, y el orquestador no debe contarlo como
  error en cada sobrevuelo de NPP. Si algún día hace falta NPP, la única vía es un HEAP 2.x
  aparte.
- **El nombre de misión no es el del archivo**: `-s n21` para lo que los SDR llaman `j02`.
- **CrIS y ATMS se emparejan por tiempo**, con traslape de intervalos, porque la órbita no se
  cruza entre instrumentos y porque los dos SDR salen agregados: sus bordes no coinciden.
  La pasada la fija CrIS (`GCRSO*`).
- **El ancillary va al revés que en ATMOS.** HEAP baja su GFS solo, al correr; lo que no hace
  es borrarlo (§1.6.3). Por eso `update_heap_ancillary.sh` solo poda, y `run_heap_edr.sh`
  corre **con** red. Si una pasada sale sin productos, la primera sospecha es el GFS: sin dos
  pronósticos que acoten la ventana, HEAP avisa y salta esos gránulos.
- **Es el único contenedor de EDR sobre Rocky 8**, porque §1.3 declara 8.10 como SO destino y
  el paquete es binario puro. No "uniformarlo" a la 9 sin probar.

Sin resolver, en orden:

1. **El producto**, que es lo que de verdad falta: sin `NUCAPS-EDR` no hay nada que ver. Ver
   arriba. Todo lo demás de esta lista está río abajo de eso.

   **La vista, en cambio, ya está resuelta y escrita** (2026-08-17): el bloque de sondeos de
   `run_polar2grid_edr.sh`, las cuatro CPT por nivel y las entradas de `metadata.py`. Lo que
   sigue de esta entrada es cómo se llegó ahí, y los siete hallazgos que no hay que volver a
   averiguar. El lector `nucaps` de
   Polar2Grid 3.2 **sí sirve**: probado con `--list-products` sobre un `NUCAPS-EDR_v3r2_n21`
   real del paquete de muestra de Sounder QL, responde con `Topography`, `Surface_Pressure`,
   `Skin_Temperature` y las 100 capas de `Temperature_*mb` y `H2O_MR_*mb` — incluidas
   `_853mb`, `_707mb` y `_497mb`, que son 850/700/500 hPa. O sea que el camino es el de
   siempre y **sin excepción al renderizador único**, a diferencia de flood:

   ```
   NUCAPS-EDR → polar2grid.sh -r nucaps → GeoTIFF float32 → geotiff2view + CPT → vista
   ```

   Y no se quedó en el papel: el 2026-08-17 se corrió **de punta a punta** —remuestreo,
   GeoTIFF, `geotiff2view`, JPG decorado con costas, logo y sello— sobre los 19 gránulos
   `NUCAPS-EDR_v3r2_n21` del paquete de muestra de Sounder QL, que son los únicos sondeos
   reales a la mano mientras HEAP no produzca los suyos. `Temperature_497mb` salió entre 257 y
   270 K con media 265 y desviación 2.0, y el campo mostró una bolsa fría al norte y aire
   cálido hacia el Golfo: físicamente creíble. De esa corrida salieron siete cosas que ya no
   hay que averiguar.

   **1. El vapor de agua NO se puede leer por este camino.** `H2O_MR_*mb` revienta con
   `KeyError: 'H2O_MR/attr/valid_range'`: `satpy/readers/nucaps.py:193` da por hecho que la
   variable trae el atributo `valid_range`, y los `v3r2` no lo traen (otras sí: `Stability`
   tiene `valid_range = 0.f, 1000000.f`). Es un desajuste entre el lector y el formato, ambos
   de CIMSS. Va reporte aparte, a Polar2Grid. Mientras tanto el vapor tendría que salir por un
   lector propio o por Sounder QL, que lo lee con `--dset wvap`.

   **2. Un producto ilegible aborta la llamada completa.** No degrada ni se salta: pedir los
   cuatro `Temperature_*` más un `H2O_MR_*` no produjo nada, ni siquiera los que sí cargaban.
   Al implementarlo hay que tenerlo en cuenta, por la misma razón por la que `vestir()` corre
   una herramienta por archivo en vez de concatenar.

   **3. La rejilla es `wgs84_geo_5km`**, ya versionada en `config/grid.yaml`. Sin `-g`,
   Polar2Grid usa su rejilla dinámica y eligió 633 m: 44 Mpx y 1.7 MB de JPEG para 2 280
   puntos de dato, con el logo tan pequeño que no se veía. A 5 km son 772 × 797 y 104 KB.

   **4. La máscara de calidad se queda puesta**, y esto cierra la duda de si convenía rellenar.
   Los huecos negros que se ven entre huellas **no son del remuestreo**: subir
   `--radius-of-influence` a 35 km casi no los movió, y con `--no-mask-quality` se llenan
   todos. O sea que son recuperaciones que NUCAPS marcó como malas. Peor aún, quitar la
   máscara mete valores disparatados que se pintan como frío extremo y arrastran el estirado
   por percentiles. **El aspecto moteado es una característica del producto, no un defecto**:
   NUCAPS es una recuperación infrarroja, así que los huecos correlacionan con nubosidad. Igual
   que las costuras de los gránulos truncados de VIIRS, hay que documentarlo para que nadie lo
   persiga como bug.

   **5. Faltan DOS entradas en `metadata.py`**, no una. La vista salió rotulada
   "NOAA-21 2026/06/30 18:47Z", sin nombre de producto **y sin sensor**: el nombre que genera
   Polar2Grid es `noaa21_atms-cris_Temperature_497mb_...`, y ni `Temperature_*mb` está en
   `product_map` ni `atms-cris` en el mapa de sensores (que solo conoce viirs, avhrr, modis,
   abi, mhs, amsu).

   **6. Cada nivel de presión necesita su propio rango de color.** 497 hPa vive en 257–270 K y
   850 andará cerca de 285: una sola `nucaps_temp.cpt` no sirve para los tres. O son tres CPT,
   o se estira por percentiles como se hizo con el DNB.

   **7. La lista por omisión son 203 productos** (100 niveles × 2 variables + 3). Hay que pasar
   `-p` explícito o cada pasada escribe 203 GeoTIFF. También hay `--pressure-levels MIN MAX`
   (por omisión 110–987).

   Lo que Polar2Grid **no** expone: punto de rocío, humedad relativa, CAPE e índice de
   levantamiento. Los dos índices no necesitan software de terceros —el propio `.nc` se
   describe: `Stability:description = "1 CAPE; ... 10 Lifted Index (LI) @ 500 hPa"`,
   `_FillValue = -9999.f`—. Para el rocío y la HR hacen falta fórmulas sobre `H2O_MR`, y para
   el Skew-T, `CSPP Sounder QL` o un módulo con matplotlib.

   **Sobre CSPP Sounder QL**, que se descargó para esto y quedó archivado como opción: son
   1.6 GB de conda-pack para 664 KB de código propio, bajo GPLv3, con tres trampas de
   contenedor documentadas (cartopy sin los shapefiles de Natural Earth y sin `110m_coastline`
   en el stock reutilizable de `cspp-geo-grb`; `unpack_check` que compara `dev:inode` y aborta
   dentro de un `.sif`; y los ejecutables que terminan en un pipe a `grep` sin `pipefail`, así
   que su código de salida es el de `grep`). Solo valdría la pena por el Skew-T y el vapor.
2. **`update_heap_ancillary.sh` en cron**, semanal. Ahora sí urge: `/data/ancillary/heap` ya
   tiene datos y nadie los borra.
3. **`level2/sounder` acumula en cada reproceso**, como `level2/atmosphere`: los `NUCAPS-*`
   llevan campo de creación. Tres `--force` seguidos dejaron 86 archivos de una sola pasada.
   Incluirlo cuando se escriba el `limpiar_productos.sh` del pendiente 5, reutilizando el
   criterio de `enlazar_en_ventana` (`run_lsr_edr.sh`): el `_c<sello>` más reciente por
   gránulo.
4. **La prueba §3.3 del manual**, con `CSPP_HEAP_TESTDATA_V3.0.tar.gz`, que no se bajó. Ya no
   urge, pero sería la forma de separar un problema del contenedor de uno del script.

### 5. Productos duplicados
`/data/output/jpss/level2/atmosphere` crece con cada reproceso: los `JRR-*` llevan campo
de creación en el nombre, así que una segunda corrida agrega en vez de sobrescribir. El
staging ya se protege enlazando solo la versión más reciente, pero falta decidir la
política de limpieza. La propuesta sobre la mesa es un `limpiar_productos.sh` en cron que
conserve la versión más reciente de cada producto y borre lo que pase de N días.

### 6. Recompilar con la base común
Las recetas ahora parten de `lanot_base_rocky8.sif` / `lanot_base_rocky9.sif`. Ninguna
imagen se ha recompilado con eso. Orden sugerido: primero las de Rocky 9 (menor riesgo,
ya validadas hoy), y al final RT-STPS y CSPP SDR, que sostienen los dos primeros eslabones
y pasan de 8.9 a 8.10. Conservar el `.sif` viejo hasta comprobar los conteos.

### 7. Polar2Grid v3.1 — cerrado
`contenedores/polar2grid_v3.1.def` ya no está en el repositorio; la nota que pedía
decidir sobre él quedó obsoleta. Lo único que sigue apuntando a esa imagen es
`scripts/procesar_cadena_completa.sh`, que no está en uso y se conserva a propósito.

---

### 8. OMPS — probado el 2026-08-13; vista desde el 2026-09-22
Los RDR **ya estaban llegando** a `level0` desde enero sin que nadie los procesara
(`RNSCA-ROTCS*` y `RNSCA-RONPS*`, incluida la pasada de prueba `d20260811`). El camino
completo hasta Level 2 ya corrió con datos reales:

```bash
scripts/run_sdr.sh --sensor omps_nm     # Nadir Mapper  (ROTCS)
scripts/run_sdr.sh --sensor omps_np     # Nadir Profiler (RONPS)
scripts/run_omps_edr.sh                 # V8TOz y V8PRO
```

Resultado sobre `j01_d20260811_b45237`: **39 productos en 28 s** (20 V8TOz y 19 V8PRO,
uno por gránulo de cada instrumento). Es con mucho el EDR más rápido de la cadena.

**Dos trampas que costaron la primera corrida**, ambas ya corregidas en
`run_omps_edr.sh`:

1. **El staging por symlinks necesita que la ruta de origen esté montada.** Los enlaces
   apuntan a `/data/output/jpss/level1/omps`, que dentro del contenedor no existía
   porque solo se montaba el staging. El driver vio los *nombres* —el log lista los 39
   gránulos, uno por línea— pero ningún `open()` funcionó, y remató con
   `0 products of 20 without errors`, sin un solo mensaje de error. La pista es la marca
   de tiempo: los 39 gránulos "procesados" en **el mismo segundo**. Se arregla con
   `--bind "$HOST_SDR_IN:$HOST_SDR_IN"`, que los demás EDR ya traían y a este se le
   había olvidado.
2. **El driver borra lo que cuelga de `-W`.** El staging estaba en `$HOST_WORK/input`, y
   la limpieza final de `omps_l2.sh` (`removed dir` en el log) se lo llevaba: el
   directorio "conservado para depurar" aparecía vacío. Ahora staging y directorio de
   trabajo son hermanos bajo `/data/tmp`, como en ACSPO y flood.

**La órbita es por instrumento.** Los SDR de OMPS de este sobrevuelo llevan `b45237` y
los de VIIRS `b45236`, aunque cubren la misma ventana (19:49–20:02 frente a 19:47–20:03
UTC). No es que la pasada se parta en dos: no hay **ningún** `GOTCO*_b45236_*` en
`level1/omps` (verificado en tahan), así que `run_omps_edr.sh` procesó el sobrevuelo
entero y la unidad de trabajo por órbita es correcta. Lo que no se vale es cruzar claves
entre instrumentos: para encontrar el OMPS de una pasada de VIIRS hay que emparejar por
tiempo, no por el `b#####`.

CSPP OMPS EDR v1.0 produce **V8TOz** —columna total de ozono en unidades Dobson, más
índice de aerosoles y reflectividad a 331 nm— y **V8PRO**, perfil de ozono en 21 capas.
Dos cosas lo hacen más simple que los demás EDR: **no usa ancillary dinámico** (nada de
caché ni cron) y su driver recibe un solo argumento, el directorio de entrada. V8TOz
necesita solo el Nadir Mapper; V8PRO necesita los dos instrumentos, así que
`run_omps_edr.sh` sigue adelante con lo que haya y avisa si no pudo hacer V8PRO. Solo
procesa gránulos diurnos: ambos algoritmos miden radiancia ultravioleta retrodispersada.

**La vista de ozono exige Polar2Grid 3.3** (manual de OMPS §4: *"Starting with Polar2Grid
Version 3.3, a subset of key OMPS V8TOz EDR parameters are supported"*). Tenemos la 3.2, y
**no hay a qué subir: el bundle 3.3 no existe todavía.**

Ojo con el tag `v3.3.0` del GitHub de SSEC, que parece ser ese release y no lo es. SSEC
numera dos cosas por separado y publica ambas como "releases":

| Tag | Nombre | Qué es |
|---|---|---|
| `v3.3.0` | "Python Package Version 3.3.0" | el paquete de Python (PyPI/conda) |
| `p2g-v3.2.0` | "Polar2Grid Version 3.2.0" | **el bundle de CSPP**, que es lo que instalamos |

Ambos son del 2 de marzo, con notas de release idénticas y el mismo commit: son dos
etiquetas de **una** entrega. El bundle 3.2 ya contiene el paquete 3.3.0, así que
recompilar desde `v3.3.0` daría exactamente el mismo software y costaría revalidar VIIRS
a cambio de nada. Lo confirma la documentación pública de Polar2Grid 3.2: lista quince
lectores y **ninguno de OMPS**.

Qué sí se puede hacer, en orden: preguntarle a SSEC cuándo sale el bundle 3.3 (publicaron
el manual de OMPS prometiendo ese soporte, así que tienen la fecha), y mientras tanto
publicar el ozono en NetCDF. Un renderizador propio es el último recurso: Satpy trae un
lector `omps_edr`, pero sus patrones son para los productos operativos de NASA/NOAA
(`OMPS-NPP_NMTO3-L2*`, `TC_EDR_TO3*.h5`), no para los `V8TOZ-EDR_v4r5*.nc` de CSPP, así
que habría que escribir el lector — y tirarlo el día que salga el 3.3.

**Resuelto el 2026-09-22 sin esperar a la 3.3**, con la lección de flood: lo único que
Polar2Grid haría por nosotros es pasar el swath a la rejilla, y eso no necesita lector.
`scripts/omps_a_geotiff.py` lee los `V8TOZ-EDR_*.nc` de la pasada y escribe
`<sat>_omps_ColumnAmountO3_<sello>_wgs84_geo_5km.tif` en `geotiff/omps`; de ahí en adelante
es un producto más de `run_polar2grid_edr.sh` —sección "Ozono (OMPS)", `vestir` con
geotiff2view y `omps_toz.cpt`, marcador y resumen—. Corre dentro de la imagen de Polar2Grid
con el Python de su bundle (rasterio, netCDF4, yaml), montado desde el repositorio: se
corrige sin recompilar y se borra al pasar a 3.3. Escribir el lector de Satpy habría costado
más para tirarlo igual: el `omps_edr` que ya trae exige la órbita en el nombre del archivo,
que los de CSPP no llevan.

Lo que se midió en tahan sobre las nueve pasadas diurnas que había (agosto y septiembre,
los tres satélites, 409 mil pixeles):

- **El archivo es fácil.** NetCDF plano, CF-1.8: `Latitude`/`Longitude` 2D y
  `ColumnAmountO3` en DU con `units`, `valid_range` y `_FillValue`. Los arreglos vienen
  rellenados (30 × 240) y el dato real ocupa menos: 15 × 139 por gránulo en NOAA-20.
- **El pixel cambia mucho entre satélites**: 177 columnas en NOAA-21, 139 en NOAA-20 y 35
  en NPP; en NOAA-20 va de 18 km en nadir a 49 en el borde. Por eso no hay vecino más
  cercano: ningún radio sirve para los tres. Cada pixel se pinta con **su huella**, las
  cuatro esquinas que trae el archivo (`LatitudeCorners`/`LongitudeCorners`, en orden y
  bien orientadas en los tres), rasterizada con `all_touched`. Sin esa bandera la vista
  salía salpicada de puntos negros: celdas cuyo centro caía en la rendija entre dos huellas.
- **`ErrorFlag = 7` se enmascara.** Junta exactamente los valores absurdos: 8 pixeles de
  NPP, de 4 a 80 DU. Los demás códigos (0, 1, 4, 5) dan valores físicos. `QualityFlag` no
  sirve para filtrar: vale 0 en todos.
- **Rango de la paleta**: los datos fueron de 242 a 332 DU. `omps_toz.cpt` va de 220 a 380
  en pasos de 10, fijo como los de sondeos, con techo holgado para el invierno.
- **Arcos negros en los extremos** de algunas pasadas (NOAA-21 19:07): no son del
  renderizado sino líneas de barrido con geolocalización y sin recuperación de ozono —5 en
  el primer gránulo, 13 en los dos últimos—. Quedan como hueco, igual que en NUCAPS.
- **Rápido**: 1 a 2.3 s por pasada el GeoTIFF, unos 6 s la sección con su vista.

**Qué falta** para que esto llegue a operación:

1. ~~Empujar LANOT_tools (`3d9e6c0`)~~ y ~~mover `LANOT_TOOLS_COMMIT` del `.def`, con la
   comprobación de `columnamounto3` en `%post` y `%test`~~ (2026-09-23). **Recompilada e
   instalada el 2026-09-23** (`apptainer test` en 0, `LANOT_tools_commit 3d9e6c07…`); la
   galería rotula ya "Total Ozone". Solo afecta al
   pie de foto de la galería, que rotula por nombre de archivo: el JPG ya sale rotulado
   "Total Ozone", porque el GeoTIFF lleva la etiqueta `product` y geotiff2view la lee
   antes que el nombre.
2. Instalar `omps_toz.cpt` en `/usr/local/share/lanot/colortables` de tahan, que es el
   que se monta sobre el de la imagen. Sin ella la sección escribe el GeoTIFF y no la vista.
3. ~~Decidir si el ozono se publica en kawak.~~ **Sí, desde el 2026-09-23**: va a
   `jpss/omps/`, al lado de `viirs/` como `sounder/`, y de los **tres** satélites —la cadena
   vieja no produce ozono, así que no hay nombre con que chocar—. Ya están ahí las vistas de
   la prueba del 2026-09-22 (NOAA-20, NOAA-21 19:07 y NPP). Para que el cron siga solo falta
   reinstalar (`sudo ./scripts/instalar.sh`), porque corre desde `/opt/lanot/polares`. La
   galería de `publicar_vistas.sh` también lo lleva ("Ozono total").

V8PRO, el perfil en 21 capas, sigue sin vista: no es un mapa.

### 9. Recorte y encuadre de las vistas
En el `true_color` de la pasada de prueba, más de la mitad del cuadro es negro: la rejilla
dinámica cubre el rectángulo que envuelve un swath diagonal y el resto es relleno. Hoy
solo se recorta por abajo, con `--lat-south 11`.

`geotiff2view` acepta `--clip` con cuatro coordenadas o con el **nombre de una región**,
que resuelve contra `/usr/local/share/lanot/docs/recortes_coordenadas.csv` (ya viene en el
contenedor). Falta decidir qué región usar por producto — probablemente una para México y
otra más amplia para los productos oceánicos como la SST.

Pendiente menor del mismo tema: ~~confirmar si el logo se está cortando en el borde
izquierdo o si el diseño es así~~. **CERRADO el 2026-08-18: el diseño es así.**
`lanot_negro_sn.png` es el logotipo completo —L-A-N, el globo como O y el satélite como T—,
su recuadro no transparente va de (32, 31) a (1168, 252) sobre un lienzo de 1188×282, o sea
con márgenes simétricos, y `mapdrawer.py:862` lo pega en x=10 con el ancho entero. No se
corta en ninguna vista.

### 10. El README está una generación atrás
Es la puerta de entrada del repositorio y describe la primera fase de la migración. Lo
concreto que hay que corregir:

- Dice que el orquestador es `procesar_cadena_completa.sh`, que **no está en uso**.
- ~~El diagrama Mermaid muestra tres contenedores y termina en Polar2Grid **v3.1**.~~
  **Rehecho el 2026-08-24** (ver pendiente 15): ya trae las cuatro ramas de sensor, las dos
  que no publican vista y por qué. Lo demás de esta lista sigue igual.
- Las instrucciones de compilación listan tarballs viejos (`CSPP_SDR_V4.1.tar.gz`,
  `CSPP_POLAR2GRID_V3.1.tar.gz`) y mandan a `apptainer build` a mano, sin mencionar las
  imágenes base ni `contenedores/construir.sh`, que resuelve el orden.
- No menciona `referencia/`, `config/grid.yaml`, el árbol de salida
  (`level0/1/2`, `geotiff/`, `vistas/`, `state/`, `/data/tmp`) ni los once `run_*.sh`.
- Trae una nota del propio autor: *"Falta actualizar con el paso Level1 -> Level2"*.
- La regla de "no hagas commits directos a `main`" sigue escrita, pero ya se decidió lo
  contrario: se trabaja directo sobre `main` porque tahan es servidor de desarrollo, no el
  que alimenta la antena (`CLAUDE.md`, 2026-08-13). El README es lo único que falta
  corregir; si algún día `main` vuelve a la antena, hay que revisar la decisión.

Lo que sí está al día es este documento y `CLAUDE.md`; el README debería remitir a ellos
en vez de repetir su contenido.

### 11. El DNB, resuelto — 2026-08-14
**Se queda solo `dynamic_dnb`.** Se pedían los cuatro a Polar2Grid; con tres pasadas reales
(diurnas del 0811 y 0813, nocturna del 0814) quedaron dos cosas claras.

**`adaptive_dnb` es idéntico a `histogram_dnb`, bit a bit, en las tres.** No es que se
parezcan: mismo hash del arreglo, mismos tags, cero píxeles distintos. La causa es la que se
sospechaba —Satpy solo ecualiza localmente cuando la escena tiene región de día *y* de
noche—, pero la consecuencia es más fuerte de lo previsto: **sobre nuestra rejilla esa
condición no se cumple nunca**. NOAA-20 es heliosincrónico con cruce ecuatorial a las 13:30
y 01:30 locales, el swath del DNB abarca ±1 hora de hora local, y el terminador está a las
06:00 y 18:00. Medido con el ángulo cenital solar de las propias pasadas:

| Pasada | SZA | Composición |
|---|---|---|
| 0811 19:47Z | 0–41.9° | 100 % día |
| 0813 19:11Z | 0–42.9° | 100 % día |
| 0814 09:23Z | 111.2–147.2° | 100 % noche |

El tramo de 43° a 111° no se muestrea jamás. No hay pasada de terminador que buscar: pedir
los dos era remuestrear lo mismo dos veces.

**`dynamic_dnb` es el mejor de los tres restantes, y el veredicto anterior estaba viciado.**
Se había anotado que "dynamic sale plano y lavado, hncc oscuro". Era el estirado, no el
algoritmo: `normalize_band()` de `geotiff2view` escalaba entre el mínimo y el máximo del
dato, y esos dos traen colas de varios órdenes de magnitud. En la nocturna:

| | mediana | máximo | nivel de la mediana con min-max |
|---|---|---|---|
| histogram | 0.617 | 0.999 | 157 de 255 |
| dynamic | 0.300 | 66.9 | **1** de 255 |
| hncc | 0.023 | 261 | **0.1** de 255 |

`histogram` se veía bien solo porque la ecualización ya entrega una distribución uniforme en
[0,1], que es justo lo que el estirado lineal supone. Con recorte al 1-99 % se invierte:
`dynamic` separa luces de ciudad, nubes y océano; `histogram` sale lavado, con las nubes en
blanco; `hncc` da las luces más limpias pero pierde terreno y nubes, que es lo esperable de
un algoritmo que normaliza por luz lunar cuando hay poca luna. De día los tres empatan.

De ahí salió `--percentiles LO,HI` en `geotiff2view`, que es **requisito** del cambio: con
min-max, `dynamic_dnb` sale negro. Los otros tres algoritmos siguen disponibles agregando
sus nombres a `-p` en `run_polar2grid_l1.sh`.

### 12. Nubes en NDVI y EVI — falsa alarma, cerrado el 2026-08-14

**Añadido el 2026-08-14, tarde: el EVI vacío no es de esta cadena.** En la pasada del 0813 la
vista de EVI salió en negro. Rastreado hasta el origen: la variable viene con cero píxeles
válidos desde el `SurfRefl_*.nc` de CSPP LSR, con el NDVI y las tres reflectancias de entrada
sanas en la misma pasada (ver "Hallazgos"). No hay nada que arreglar en el producto.

**Lo que sí se arregló es que la cadena lo publicara como bueno**, el mismo día:

- `geotiff2view` ya no escribe imagen cuando el GeoTIFF no tiene un solo píxel válido: avisa
  por stderr y sale con **código 3**, reservado para eso (el 1 queda para fallos de verdad y
  el 2 lo usa argparse). Va en el `--help` y en el README de LANOT_tools, que es contrato con
  quien llama. Con pruebas en `tests/test_geotiff2view.py`, que no existía.
- Los dos `run_polar2grid_*.sh` llaman a la herramienta **una vez por archivo** para poder leer
  ese código, y distinguen "generada" de "sin datos" y de "con error". Antes concatenaban las
  órdenes de toda una sección en un solo `bash -c`, donde el código del conjunto es el de la
  última orden: el de EVI se habría perdido igual, porque `EVI` va antes que `NDVI` en el
  orden alfabético.

Queda una consecuencia que conviene recordar: el `RuntimeWarning: All-NaN slice encountered`
que puso sobre la pista **ya no aparece**. Salía de dos f-strings de depuración que se
evaluaban aunque `VERBOSE` fuera falso —recorriendo el arreglo completo para tirar el
resultado—, y eso se corrigió de paso. El síntoma ahora es explícito: `· sin datos válidos, no
se genera vista` en el log, y el recuento por sección al final de cada bloque.

Se había anotado que las nubes se pintaban como suelo desnudo, por una mancha beige sobre
el norte de México y Texas en la vista del 2026-08-11. **Es incorrecto: LSR ya enmascara
las nubes.** Comprobado comparando el NDVI del 2026-08-13 con su `true_color`: el banco de
nubes del Pacífico y de Centroamérica sale negro en el NDVI, y las nubes dispersas sobre
Texas aparecen como motas negras dentro de la zona verde. Son NaN, no valores bajos.

La mancha beige es suelo árido de verdad —el desierto chihuahuense en agosto, café en el
`true_color`, con NDVI de 0 a 0.2, que es lo que le toca—.

Tiene sentido de diseño: **LSR consume `JRR-CloudMask` como entrada** (por eso ATMOS corre
antes), así que el enmascarado ocurre río arriba, en espacio de swath y con la
geolocalización nativa, antes de remuestrear. Rehacerlo río abajo sería duplicar trabajo con
peor información.

De paso quedan aclarados dos límites de Polar2Grid, por si el tema vuelve:

- ~~**`JRR-CloudMask` no se puede remallar**: de los 110 productos de ATMOS en la ventana, P2G
  3.2 solo entrega 7, y la máscara no está entre ellos.~~ **FALSO, corregido el 2026-08-15.**
  Sí se puede: `CloudMask` está disponible, junto con `CloudMaskBinary`, `CloudProbability`,
  `CloudType`, `CldOptDpth`, `CldTopPres`, la microfísica (`CloudMicroEffRad`, `IWP`, `LWP`),
  `Dust`, `Smoke`, `SnowIce`, `Fire_Mask`, `Shadow_Mask` y un centenar más. El error vino de
  usar `--list-products`, que **oculta** una sección: `_print_list_products()` imprime tres
  listas —las de P2G, las de usuario y las de Satpy— y la de Satpy solo sale con
  **`--list-products-all`**, con un `*` delante que es marca y no parte del nombre. Los 7 que
  veíamos son el catálogo curado de P2G para ese lector, no el límite de lo que se puede leer.
  Verificado además de punta a punta: `-p CloudType` produce su GeoTIFF sin problema.

  Lo que **no** cambia es el obstáculo de fondo para combinar dos productos en malla: las
  rejillas de `config/grid.yaml` siguen siendo dinámicas y cada llamada da una extensión
  distinta (ver el párrafo de más abajo). Se destrabó el insumo, no el enmascarado.
- **Las banderas de calidad de LSR tampoco son alcanzables**: el lector `viirs_edr` expone
  16 productos de los `SurfRefl_*.nc` —los 14 `surf_refl_*` más NDVI y EVI— y las QF no
  están ahí.

Si algún día hace falta combinar dos productos en malla (enmascarar uno con otro, o comparar
pasadas), el obstáculo real no es el soporte de P2G sino que **las rejillas de
`config/grid.yaml` son dinámicas**: solo fijan proyección y resolución, así que cada llamada
da una extensión distinta —atmos 3177×4017 y lsr 3178×4017 en la misma pasada—. Con
extensión fija todo quedaría alineado y el enmascarado sería álgebra de rásters. Es lo mismo
que habilitaría el pendiente 9: los dos problemas tienen esa raíz.

### 13. Level 2 sin renderizar: flood y cryosphere
Incendios se resolvió el 2026-08-14 (bloque nuevo en `run_polar2grid_edr.sh`). Quedan dos, y
los dos están bloqueados por falta de lector, no por falta de trabajo:

- **flood**: resuelto el 2026-08-14, **sin Polar2Grid**. El lector `viirs_edr_flood` existe
  pero solo lee la salida HDF de CSPP Flood v1.x (`WATER_VIIRS_Prj_SVI_*_01.hdf`), y nosotros
  generamos NetCDF v2.0. La pregunta estaba mal planteada: `referencia/cspp_6_flood.sh`, que
  es lo que corre hoy en producción, muestra que **las vistas de inundaciones nunca salieron
  de Polar2Grid** — las hace `flood2tif.sh`, del propio bundle de CSPP. Ese script exporta
  `POLAR2GRID_HOME` sin llegar a usarlo nunca, y eso me tuvo buscando en el lugar equivocado.

  CSPP Flood v2.0 sí trae el convertidor, y toma el NetCDF nuevo: el ejemplo de su propio
  `usage` es un `VIIRS-Flood_v2r0_n20_s…nc`. Lo que hace es
  `gdal_translate -a_srs EPSG:4326 -ot Byte -a_ullr …` sobre el dataset `WaterDetection`,
  tomando las esquinas de los atributos del archivo, y después le pega la paleta con
  `add_colormap.py … flood.ct`. **El `.tif` sale como imagen con colormap embebido, no como
  dato**, así que le toca `mapdrawer` y no `geotiff2view` — es el único usuario que le queda
  a esa rama de `vestir()` desde que se retiraron los RGB de superficie.

  El reparto quedó así: `run_flood_edr.sh` convierte y fusiona (`cspp_viirs_tifmerge.sh`, un
  `.tif` por gránulo no sirve de vista) y deja el resultado en `geotiff/flood`;
  `run_polar2grid_edr.sh` solo lo viste. Es generación de producto, como el `.nc`, así que no
  rompe la regla del renderizador único — lo que no se hace fuera de ahí es la *vista*.

  Dos detalles que costaron: el convertidor escribe **junto a la entrada**
  (`OUTPUT=${INPUT/.nc/.tif}`), por eso corre sobre `/work` y no sobre la salida en Lustre; y
  `vestir()` filtraba con `-newer "$REF_FILE"` para vestir solo lo de la corrida actual, lo
  que dejaba fuera el `.tif` de flood por haberlo escrito otro script antes. De ahí el
  séptimo parámetro `solo-nuevos`, que en ese caso va en 0 y deja que el ERE acote la pasada.

- **cryosphere**: no aparece ningún lector de criósfera en la lista de P2G 3.2. Está en la
  misma situación que el ozono (pendiente 8): el producto se genera y no hay forma de
  remallarlo con lo que tenemos.

Flood y ozono comparten causa raíz: **Polar2Grid va por detrás de CSPP**. El lector de flood
se quedó en la v1.x y el de ozono llega hasta la 3.3. Al preguntarle a SSEC por la fecha del
bundle 3.3 (pendiente 8), conviene preguntar de paso si trae lector para `VIIRS-Flood_v2r0`:
son dos huecos que cerraría la misma actualización.

Lo que dejó el caso de incendios, y que aplica a flood:

- Los `AFIMG` **se bastan solos**: `--list-products` corrió con `-f AFIMG_*.nc` y nada más.
  Por eso no aplicó nada de lo que complicaba `referencia/test_render_fires.sh` — ni quitar
  `_cspp_dev` (que además rompe el lector `viirs_sdr`) ni pasar `j01` a `J01`. Ese script
  metía `viirs_sdr` en la misma llamada y de ahí venían sus problemas.
- **La órbita cambia a media pasada** en los nombres de los AFIMG: `b45264` en el primer
  gránulo del 2026-08-13 y `b45265` en los siguientes. Enlazar por órbita, que es como se
  hace con los SDR, dejaría fuera gránulos; hay que emparejar por ventana temporal.
- De los tres productos disponibles (`confidence_cat`, `T4`, `power`) solo el primero tiene
  paleta. Los otros dos salen como GeoTIFF sin vista, que es el comportamiento correcto.

### 14. Un centenar de productos de ATMOS que no estábamos ofreciendo
Descubierto el 2026-08-15 persiguiendo por qué la cadena nueva no generaba la vista de **tipo
de nube** que la vieja sí publica con CLAVR-x. No era que el producto faltara: `CloudType`
está en `JRR-CloudPhase`, que ya leemos.

Lo que pasaba es que **`--list-products` oculta la mitad de lo disponible** (ver "Hallazgos").
Con `--list-products-all` aparecen, además de `CloudType`: `CloudMask`, `CloudMaskBinary`,
`CloudProbability`, `CldOptDpth`, `CldTopPres`, `CldTopEmss`, la microfísica
(`CloudMicroEffRad`, `CloudMicroIWP`, `CloudMicroLWP`, `CloudMicroVisOD`), `Dust`, `Smoke`,
`SnowIce`, `Fire_Mask`, `Shadow_Mask`, toda la familia de ceniza volcánica y un largo etcétera.

`CloudType` ya está pedido, corregido y verificado contra la vista de CLAVR-x de la misma
pasada (2026-08-15, ver arriba). **Lo que queda por decidir es el resto**, y
es una decisión de producto y no técnica: ahora que se sabe que están disponibles, conviene
enseñarle la lista a los colegas del laboratorio antes de elegir. El costo de agregar
cualquiera es una palabra en el `-p` de ATMOS más su paleta y su entrada en `product_map`.

Dos que se ven especialmente prometedores: **`CloudMask`**, que reabre el enmascarado del
pendiente 12 —aunque siga topando con las rejillas dinámicas—, y **`Dust`/`Smoke`**, que en
esta región tienen uso operativo evidente.

### 15. Los dos diagramas de la cadena — CERRADO el 2026-08-24
Anotado el 2026-08-17. Los dos colgaban los once eslabones de Level 2 de un solo
`cspp_sdr_v4.1.1.sif`, como si todos comieran de lo mismo, y de ahí no se podía saber que HEAP
no toca VIIRS ni que flood y ACSPO no tienen nada que ver con CrIS. Rehechos los dos, con las
cuatro ramas de sensor explícitas y lo que se pedía: qué sensor alimenta a qué, que HEAP es el
único que consume **dos** a la vez —de ahí el traslape con margen (`HEAP_MARGEN_ATMS`) en vez de
clave de pasada— y que la órbita no es común entre instrumentos.

**El del README** (Mermaid) dibuja los tres flujos de SDR como nodos propios y de cada uno cuelga
su rama; punteadas las dos que hoy no publican vista, con su motivo. Se **renderizó** con
`mmdc` antes de darlo por bueno, y menos mal: con las ramas saliendo directo del nodo de SDR, la
etiqueta del renderizado de Level 1 aterrizaba debajo de `OMPS NM + NP`, como si fuera de esa
rama. Eso no se ve leyendo el bloque.

`mmdc` está instalado en bucefalo desde el 2026-08-24, pero de fábrica falla con
`Could not find chrome-headless-shell`: puppeteer no trae navegador descargado. No hace falta
bajarlo, hay Chrome del sistema —basta apuntarlo con un archivo de config:

````bash
cat > puppeteer.json <<'EOF'
{ "executablePath": "/usr/bin/google-chrome-stable",
  "args": ["--no-sandbox", "--disable-dev-shm-usage"] }
EOF
# la cerca de cuatro backticks es porque el sed lleva backticks dentro
sed -n '/^```mermaid$/,/^```$/p' README.md | sed '1d;$d' > cadena.mmd
mmdc -p puppeteer.json -i cadena.mmd -o cadena.png -w 1600 -b white
````

Se descartó PlantUML para esto: GitHub no lo renderiza en markdown, así que obligaría a
versionar el SVG generado —en un repositorio que no tiene una sola imagen versionada— o a
depender de un servidor de render ajeno.

**El de `CLAUDE.md`** (ASCII) tenía además dos errores que no eran de estructura y que se
encontraron al rehacerlo:

- Listaba el Level 1 como `SV*, GMTCO*, SATMS*, SCRIS*, SOMTC*`. `SATMS` y `SCRIS` **no son lo
  que la cadena consume**: `run_heap_edr.sh` enlaza `SCRIF*`/`GCRSO*` y `TATMS*`/`GATMO*`. Son
  nombres que CSPP SDR sí emite, así que el error no saltaba a la vista, pero mandaba a buscar
  archivos equivocados. Ahora cada rama lista los suyos.
- **Flood no aparecía**, pese a que `contenedores/cspp_flood_v2.0.def` existe desde el 2026-08-14
  y la prosa de abajo del propio diagrama lo explica. Eran ocho eslabones dibujados de nueve.

De paso, LSR y CRYO cuelgan ahora de ATMOS en el árbol, en vez de decirlo con un `[requiere
ATMOS]` al margen.

### 16. Alinear la decoración de las vistas con las de GOES — DECIDIDO A MEDIAS
Anotado el 2026-08-17. **No aplicar todavía**: falta resolver la legibilidad, ver abajo.

Las vistas L2 de GOES (`LANOT_procesamiento_goes/crea_vistas_l2.sh`) ponen la fecha **abajo a
la izquierda** sobre una caja de fondo, con los números de la barra **dentro** de la rampa. Las
polares la ponen arriba a la derecha, encima del dato. La diferencia no era una decisión de
diseño: **`geotiff2view` iba detrás de `mapdrawer` en dos pasos de CLI**, y las dos capacidades
existían en la biblioteca desde antes.

| Capacidad | En `draw_fecha`/`draw_legend` | `mapdrawer` | `geotiff2view` |
|---|---|---|---|
| Caja tras la fecha | `bg_color` | `--font-bg` | agregada el 2026-08-17 (`8bc8f69`) |
| Números dentro de la barra | `text_pos` | `--colorbar-text-pos` | agregada el 2026-08-17 (`72f5cd3`) |

El cambio que quedaría pendiente, en las **dos** `DECORACION` (`run_polar2grid_edr.sh` y
`run_polar2grid_l1.sh`):

```diff
-    --timestamp-pos 1
+    --timestamp-pos 2
     --font-color white
-    --font-bg black
+    --font-bg gray
+    --colorbar-text-pos middle
```

Probado en bucefalo sobre la vista de sondeos de 500 hPa: sale limpio, el mapa queda **sin nada
encima** y es la disposición que ya se publica en GOES. `--timestamp-pos 2` sin `middle` NO
sirve —la fecha cae sobre los números de la barra y quedan ilegibles los dos, medido el mismo
día—, así que las dos banderas van juntas o ninguna.

**Lo que lo bloquea**: con `middle` los números se dibujan **sobre la paleta**, y con texto
blanco se pierden en las zonas claras. No es un caso raro — **las 23 CPT del repositorio tienen
anclas claras**, y `cld_temp_acha.cpt` (9 de 30, arranca en blanco puro) perdería los números en
todo el extremo frío. O sea que `middle` no se puede aplicar a ciegas a todos los productos.

Tres salidas, de menos a más robusta:

1. **Por producto**: `middle` solo donde la paleta es oscura. Deja las vistas desiguales entre sí,
   que es justo lo que este pendiente quiere quitar.
2. **Color del texto por paleta**: `draw_legend` ya acepta `color` (`colorpalettetable.py:336`),
   pero **ninguna de las dos herramientas lo expone**. Habría que sacarlo a la CLI y elegir uno
   por CPT: 23 decisiones a mano, y cada CPT nueva vuelve a plantearla.
3. **Contorno en el texto** (`stroke_width`/`stroke_fill` de PIL, que Pillow soporta desde la
   6.2): una sola vez en `draw_legend` y los números se leen sobre cualquier fondo. Es la que yo
   haría; de paso arregla `mapdrawer`, y por lo tanto las vistas de GOES, que **hoy ya usan
   `middle`** con `cld_height_acha`, `modis_lst` y `aod550` — las tres con anclas claras. Vale la
   pena mirar una vista publicada de LST o AOD antes de suponer que allá el problema no existe.

Y de paso, la divergencia de estilo que es **más visible que la fecha** y que nadie ha decidido:
las capas van en **blanco** en GOES y en **amarillo** en las polares. Si se va a unificar la
decoración, esto es lo primero que se nota.

### 17. El resumen del orquestador mentía con OMPS — ARREGLADO el 2026-08-24
Anotado el 2026-08-17, arreglado el 2026-08-24.

En la corrida de `j01_d20260817_b45321` el resumen dio **`omps  ya estaba`**, y es falso: OMPS
corrió en esa misma corrida, tardó 28 s, dejó 38 productos y escribió su marcador
`j01_d20260817_b45322.done` a las 19:54.

La causa está en las claves. `procesar_pasada.sh` decide el estado comparando el mtime del
marcador antes y después de la etapa (`sin-cambio` → "ya estaba", línea 234), y el nombre lo da
`marcador_de`, que para OMPS devuelve `$DIR_OMPS/$CLAVE_OMPS.done` con la clave **truncada**
(`j01_d20260817`). Pero `run_omps_edr.sh` escribe la clave **completa, con su propia órbita**
(`j01_d20260817_b45322`), que resuelve de los archivos y que el orquestador no puede saber de
antemano — de ahí la clave truncada en primer lugar. O sea que vigila un nombre que nunca
existe, no ve cambio y concluye que no hubo trabajo.

Es la misma clase de mentira que ya costó una lectura equivocada con HEAP —"el marcador, del que
sale el resumen del orquestador, mentía"— y `CLAVE_HEAP` es literalmente `CLAVE_OMPS`, así que
en cuanto HEAP vuelva a la cadena hará lo mismo.

**No es grave por lo que hace sino por lo que oculta**: el código de salida se revisa antes, así
que una etapa que falla nunca se reporta como buena. Lo que se pierde es lo contrario — una
etapa que sí trabajó y se reporta como si no— y con ella la duración y los conteos, que en el
resumen salen vacíos.

**Lo que se hizo**, en `procesar_pasada.sh` y sin tocar `run_omps_edr.sh`, que hace lo correcto:

1. `marcador_reciente()`, nueva: busca por glob `${prefijo}_b*.done` en el directorio de estado
   y devuelve el más reciente por mtime. Si no hay ninguno devuelve el nombre truncado, que no
   existe y por lo tanto pesa 0 en la comparación — que es justo lo que se quiere decir.
   `marcador_de` la usa para `omps` y `heap`; las otras diez etapas siguen con su nombre exacto.
2. **El marcador dejó de viajar en la tarea.** Era la causa de fondo: la tupla llevaba
   `etiqueta <TAB> marcador <TAB> script <TAB> arg...`, así que el nombre se fijaba al armar la
   tarea y `marcador_de` lo volvía a calcular al cosechar. Dos fuentes para el mismo dato, y con
   OMPS discrepaban siempre. Ahora la tupla es `etiqueta <TAB> script <TAB> arg...` y las dos
   tomas de mtime —la de antes, en `ejecutar_nivel`, y la de después, en `cosechar_tanda`— pasan
   forzosamente por `marcador_de`. `armar_tarea` perdió un parámetro y las trece llamadas
   quedaron más cortas.

Varias pasadas del mismo día comparten la clave truncada (`j01_d20260817`), pero eso no rompe la
comparación: el marcador que escribe la corrida en curso es forzosamente el más nuevo de los que
casan, así que el glob lo encuentra.

**Probado en bucefalo** con stubs en lugar de los `run_*.sh` (`SCRIPTS_DIR`, `ESTADO_BASE`,
`RTSTPS_OUTPUT_DIR` y `SDR_LEVEL1_VIIRS` apuntando a un árbol de juguete), en los cuatro casos
que importan:

| Caso | Antes | Ahora |
|---|---|---|
| OMPS corre por primera vez (le dan `j01_d20260817`, escribe `…_b45322`) | `ya estaba`, sin duración ni conteos | `ok  0m 28s  productos=38` |
| Se repite la misma pasada | `ya estaba` | `ya estaba` (correcto: no reescribió nada) |
| Segunda pasada del mismo día, con `…_b45322` ya en el directorio | `ya estaba` | `ok` — el glob encuentra el nuevo `…_b45337`, más reciente |
| Cadena entera desde un RAW (rt_stps + dos SDR + los nueve de Level 2) | — | las doce etapas `ok`, sin regresión |

Cuando HEAP vuelva a la lista queda arreglado de nacimiento: `CLAVE_HEAP` es `CLAVE_OMPS` y
`marcador_de` ya lo trata igual.

## Hallazgos que conviene no volver a descubrir

Cosas que costaron trabajo y no son evidentes leyendo el código:

- **El campo de creación `_c<sello>` compite con el de observación al leer el sello de un
  producto, y gana cuando las dos fechas coinciden.** Un AFIMG se llama
  `AFIMG_npp_d20260829_t1852513_..._c20260829192258365504_cspp_dev.nc`: la fecha va DOS veces.
  La regla de "fecha + 7 dígitos" de `sello_de_archivo()` no casa en el campo de observación
  —entre la fecha y la hora va `_t`, no un dígito— pero sí en el de creación, así que los ocho
  gránulos de la pasada de NPP del 2026-08-29 salieron con el **mismo** sello, el de cuando se
  escribió el archivo, siete minutos fuera de la ventana. Resultado: `FIRE: 0 productos en la
  ventana`, etapa en `ok`, marcador escrito y cero incendios publicados. **No se había visto
  por casualidad de calendario**: hasta ese día solo se habían procesado crudos de fechas
  anteriores, donde la creación no coincide con `FECHA_NUM`; en operación real las dos fechas
  son la misma siempre y esto habría fallado en cada pasada. Corregido quitando el campo de
  creación antes de buscar, en las **tres** copias de la función (`run_polar2grid_edr.sh`,
  `run_lsr_edr.sh`, `run_cryo_edr.sh`) — en LSR y cryo no se manifestaba, pero solo porque los
  `JRR-*` llevan el campo `s` antes que el `_c` y `head -1` acertaba por orden de aparición.
  **No llegó a producción, y se comprobó en vez de suponerse.** Faltaban los GeoTIFF de
  incendios de tres fechas (`20260508`, `20260811`, `20260814`), pero ninguna es víctima suya:
  las dos primeras se procesaron cuatro días y un día después de observadas —`_c20260512` y
  `_c20260812`—, así que el sello no podía confundirse; y en la del 14, aunque `_d` y `_c`
  coinciden, el log de aquella corrida
  (`p2g_20260814_161626_j01_d20260814_b45273.log`) **no menciona `FIRE:` ni una vez**: el
  bloque de incendios se agregó ese mismo día (`ace41d7`) y llegó a tahan después. Desde
  entonces todas las pasadas se procesaron con crudos de días anteriores, así que la primera
  vez que coincidieron observación y creación fue la de NPP del 29 — el bug se estrenó y se
  corrigió el mismo día.
- **Los GeoTIFF de Polar2Grid NO son reproducibles bit a bit: no compararlos con `cmp` ni
  `md5sum`.** Dos corridas de la misma pasada, con la misma imagen y la misma entrada,
  producen archivos que difieren en más de un millón de bytes y cuya primera diferencia
  aparece en el byte 3231, o sea en el directorio TIFF — pero cuyo `gdalinfo -checksum`, que
  se calcula sobre los píxeles, es **idéntico**. La causa es que el escritor escribe por
  bloques con dask en paralelo y comprimido: el orden en que terminan los hilos cambia los
  offsets y el particionado de los bloques comprimidos, no los datos. Se midió el 2026-08-29
  al validar la imagen parcheada: `cmp` señaló doce archivos, el control de la imagen nueva
  contra sí misma señaló **quince, y no los mismos doce**, y el barrido por checksum dio los
  27 iguales. Un detalle que lo remata: en el control aparece el `EVI`, que no tiene un solo
  píxel válido. Ojo con generalizar al revés: los `.nc` de CSPP sí son reproducibles (ver el
  hallazgo del EVI, donde LSR reprodujo los once `.nc` con tamaño idéntico al byte); esto es
  específico del escritor de Polar2Grid.
- **`config/grid.yaml` define `itrf2008_lcc_375m` dos veces**, la segunda con resolución
  de 1000 m. En YAML gana la última, así que esa rejilla hoy vale 1000 m y no existe
  ninguna llamada `itrf2008_lcc_1000m`. Probablemente sea un error de dedo al agregarla.
- **LSR deduce cuántos gránulos hay contando los `JRR-AOD`**
  (`cspp_viirs_surface_reflectance.py:313`) y luego exige esa misma cantidad de cada
  producto. Con productos duplicados falla culpando a los `NWP_GFS-INTP`, que son los
  únicos que no se duplican.
- **ATMOS con `-l` no descarga ancillary**, y sin CMCSST cada gránulo aborta y la corrida
  entrega "0 products of 132" con código de salida 0.
- **El EVI puede salir vacío de CSPP LSR, pasada por pasada, sin que falle nada.** En
  `j01_d20260813_b45264` el EVI tiene **cero píxeles válidos ya en el `SurfRefl_*.nc`** —no se
  pierde al remallar—, mientras que el NDVI de la misma pasada sale con 9.9 % válido y sus tres
  reflectancias de entrada están sanas, azul incluido (M03 64.6 %, M05 64.6 %, M07 64.6 %). En
  `j01_d20260811_b45236` el mismo EVI sale con 9.25 % válido y media 0.32, casi la misma máscara
  que su NDVI. LSR es reproducible —al reprocesar el 0811 dos días después, los once `.nc`
  salieron con el **tamaño idéntico** al byte—, así que no es el ambiente ni el ancillary: es el
  algoritmo de CSPP rechazando el 100 % de los píxeles de esa variable en esa pasada. Río abajo
  se manifiesta como `RuntimeWarning: All-NaN slice encountered` en `geotiff2view.py:203` y una
  vista en negro que el resumen cuenta como buena.
- **`gdalinfo` sobre un `.nc` y sobre el GeoTIFF no miden lo mismo.** El crudo solo respeta
  `_FillValue`; Satpy además aplica `valid_range`. El NDVI del 0813 da 80 % "válido" en el
  NetCDF con mínimo −199 y máximo 201, y 9.9 % dentro de −1..1 en el GeoTIFF. Los porcentajes
  de los dos no son comparables — pero un 0 % en el NetCDF sí es concluyente, porque ahí no
  hay ni siquiera algo que enmascarar.
- **`--list-products` de Polar2Grid oculta la mitad de lo disponible.** `_print_list_products()`
  (`polar2grid/glue.py:162`) imprime tres listas —productos de P2G, de usuario y de Satpy— y
  **la de Satpy solo aparece con `--list-products-all`**. Los nombres salen con un `*` delante,
  que es marca de "no estándar" y no parte del nombre: a `-p` va el nombre pelón. Son pedibles
  y funcionan; lo único que les falta es estar en el catálogo curado de P2G, que es lo que
  determina la lista por omisión. Esta confusión hizo dar por imposible el remallado de
  `JRR-CloudMask` (pendiente 12).
- **`-p` reemplaza la lista por omisión, no la extiende.** Al pedir un producto que no está en
  el catálogo hay que enumerar también los que ya salían, o se pierden.
- **`gdalinfo` está en el host, no hace falta contenedor**; y si se usa uno, hay que montar
  `/data` con `--bind`, porque `apptainer exec` a secas no lo monta y GDAL contesta
  `not recognized as being in a supported file format`, que parece un archivo corrupto y no
  lo es. **Lo mismo vale para cualquier ruta fuera de los montajes**: una prueba a mano de
  `polar2grid.sh` con `--grid-configs` apuntando al `grid.yaml` del repositorio en `$HOME`
  murió con `FileNotFoundError` y un `ERROR: Unexpected error` que no decía nada. Los
  `run_*.sh` no tropiezan con esto porque montan el YAML explícitamente
  (`--bind "$GRID_CONFIG:/config/grid.yaml:ro"`); es un riesgo de las pruebas ad hoc.
- **`cspp_viirs_tifmerge.sh` no acepta destino.** Ignora `-o` sin protestar, nombra él la
  salida (`…_s<inicio>_e<fin>_c<creación>_merged.tif`) y la deja junto a la entrada. Hay
  que buscar el `*_merged.tif` y renombrarlo. Verificado en tahan el 2026-08-14.
- **`successful_runs` de CSPP Flood no significa que haya productos.** Ahí entra todo
  gránulo cuyo binario terminó en 0, produzca o no: en la pasada nocturna del 2026-08-14
  los cinco aparecieron a la vez en `successful_runs` y en `failed_aoi_runs`, con
  `rc_exe = 0` y cero archivos. El inventario real es la línea
  `VIIRS Flood output files = [...]`, que el driver imprime por gránulo. La firma de la
  pasada nocturna es que `VIIRS_Swath_Projection.exe` termina en 0 sin escribir ningún
  `GITCO_Prj_SVI_*.h5` y entonces el `ls … | xargs -n 1 VIIRS_Flood_Detection.exe` corre
  **sin argumento** —`xargs` sin `-r`— y contesta `Parameter error!` una vez por gránulo.
- **Cada software tiene su propio caché de ancillary y no deben compartirse.** El de CSPP
  SDR usa subdirectorios por día; el de ATMOS guarda ~6 GB diarios sueltos en la raíz y
  los poda `delete_old_anc.sh`, que borraría el de SDR si se le apuntara ahí.
- **`gdal` arrastra 709 MB de rejillas de datum de PROJ de otros países** como dependencia
  débil. De ahí el `--setopt=install_weak_deps=False` en las recetas.
- **Las imágenes de Rocky en Docker Hub están congeladas** (9 en 9.3 de mayo de 2024, 8 en
  8.9). Rocky mantiene las suyas en Quay. Partir de Docker Hub y actualizar con `dnf` hacía
  que el contenido dependiera del día de compilación.
- **Los productos de Level 2 usan cuatro convenciones de sello temporal**, y `sello_de_archivo()`
  de `run_polar2grid_edr.sh` tiene que reconocerlas todas para emparejarlos por ventana:
  `s202608111947330` en los `JRR-*`, `2026223_1947_33` (día juliano) en los `*_VIIRS_750M*`,
  catorce dígitos al inicio en los de ACSPO, y `d20260813_t1911067` —la misma de los SDR— en
  los `AFIMG` de Active Fire. Antes decía dos:: `s202608111947330`
  (fecha y hora) en los `JRR-*`, y `2026223_1947_33` (año y día juliano) en los
  `*_VIIRS_750M*`.
- **El mismo satélite aparece con tres nombres** según el producto: `j01` en los SDR,
  `NOAA20` en los `VIIRS_750M` de ATMOS, `n20` en los de Flood.
- **En un CPT nuevo, `B` va en negro.** Los scripts llaman a `geotiff2view` con `-b`, que
  usa el color `B` (fondo) para los NaN, y los GeoTIFF de Polar2Grid traen
  `NoData Value=nan`. Si `B` es igual al extremo bajo de la rampa —como salieron las tres
  paletas nuevas la primera vez— el relleno fuera del swath se confunde con el valor
  mínimo y no se ve dónde miró el satélite. No se puede resolver quitando `-b` para que
  use `N`: `phase.cpt` tiene `N 255 0 0` y pintaría todo el fondo de rojo.
- **Pero si el fondo sale con el color del extremo bajo *y* el CPT tiene bien su `B`, el
  problema es el `--dtype`.** Le pasó a la SST: `run_polar2grid_edr.sh` llamaba a ACSPO con
  `$P2G_COMUN` en vez de `$P2G_DATOS`, así que Polar2Grid entregaba una **imagen realzada
  de 8 bits con dos bandas** (`Type=Byte` en las dos, sin `NoData Value`) y el sin-dato en
  la banda 2, que es alfa. `geotiff2view` solo abre la banda 1, y para banda entera sin
  `nodata` declarado construye **máscara vacía** (`geotiff2view.py:149-158`), así que
  `img_data[mask] = n_idx` no se ejecuta nunca, la línea `B` no se aplica y todo el relleno
  satura en el índice 0. Se veía como un fondo rosa —el 268 K de `sst.cpt`— y el `.cpt`
  estaba perfecto. La forma de distinguir los dos casos es un `gdalinfo | grep Type=`: si
  dice `Byte`, es el `--dtype`; si dice `Float32`, es el `B` del CPT. Regla: **todo lo que
  sea dato de una banda va con `$P2G_DATOS`**; `$P2G_COMUN` es solo para los RGB, que no se
  pueden guardar en float32.
- **Las franjas negras horizontales de las vistas son interferencia de antena, no un
  problema de procesamiento.** Hay un árbol sin podar en la línea de vista; el efecto varía
  con la pasada y golpeó mucho más a la nocturna del 2026-08-14 que a las diurnas. Desde el
  código se ve idéntico a lo que produciría un gránulo truncado descartado por el filtro de
  tamaño, así que es fácil perseguirlo en los scripts sin razón. Antes de investigar una
  pasada rayada, preguntar por el estado de la antena.
- **Estirar entre el mínimo y el máximo solo sirve si el dato llena su rango.**
  `normalize_band()` de `geotiff2view` lo hacía siempre, y con una cola larga un puñado de
  píxeles extremos se lleva toda la escala: en la nocturna, `dynamic_dnb` tenía mediana 0.30
  con máximo 66.9 y `hncc_dnb` mediana 0.023 con máximo 261, así que sus medianas caían en
  los niveles 1 y 0.1 de 255 y las imágenes salían negras. Parecían algoritmos malos y era
  el renderizado. De ahí `--percentiles LO,HI`. Cuidado al comparar productos: si uno de
  ellos ya entrega una distribución uniforme —`histogram_dnb`, por construcción— el estirado
  lineal lo favorece y la comparación queda amañada.
- **Un CPT nuevo obliga a tocar dos archivos, no uno.** El `.cpt` da los colores, pero el
  nombre que se quema en la imagen sale de `product_map` en `LANOT_tools/metadata.py`. Si
  falta la entrada, `geotiff2view` cae al nombre del sensor y rotula "NOAA-20 VIIRS" a
  secas; `mapdrawer` ni eso, porque no tiene ese respaldo, y deja solo "NOAA-20". Así
  salieron AOD550, CldBaseHght, Total_Cloud_Fraction, NDVI, EVI y los dos falso color de la
  corrida del 2026-08-13. El orden de la lista importa: gana la primera subcadena que
  aparezca, así que lo específico va antes que lo genérico (los cuatro algoritmos de DNB
  antes de `dnb`, o los cuatro salen rotulados igual).
- **`_cspp_dev` es obligatorio, no estorbo.** El patrón de `viirs_sdr` termina en
  `_{source:8s}.h5`. Quitarlo —que es lo que hacíamos— tumbó los cuatro renderizados de
  Level 1 con `No filenames found for reader`.
- **Un RGB no se puede guardar como float32.** Pedir todo el conjunto de LSR con
  `--dtype float32 --no-enhance` aborta en `true_color_surf` con `Image must be in 'L'
  mode`, y se pierden también los productos de una banda que ya se habían remuestreado
  (murió tras escribir 3 de 14). Por eso LSR va en dos llamadas.
- **Cada producto de Level 2 fecha a su manera y no todas coinciden con la pasada.** El
  `.nc` de ACSPO de `j01_d20260811_b45236` se llama `20260811194400…`, 3.5 minutos antes
  del primer gránulo (`t1947330`). De ahí el margen de 10 minutos al emparejar por
  ventana; es seguro porque dos pasadas consecutivas están a ~100 minutos.
- **Polar2Grid renderiza un subconjunto de los `JRR-*`**: de 110 productos de ATMOS en la
  ventana salieron 7 GeoTIFF (`AOD550`, `CldBaseHght`, `CldTopHght`, `CldTopTemp`,
  `CloudLayer`, `CloudPhase`, `Total_Cloud_Fraction`).
- **Los SDR de `run_sdr.sh` vienen agregados**: un archivo por banda para toda la pasada,
  con un solo GMTCO. Por eso el emparejamiento con los productos de Level 2 se hace por
  ventana temporal y no gránulo por gránulo.

---

## Material de referencia

- `referencia/cspp_1_ptog.sh` — el script **en producción hoy** en el servidor viejo, que
  genera los GeoTIFF de Level 1, las vistas DNB y las RGB. Es la referencia de lo que la
  cadena nueva tiene que llegar a cubrir. No se ejecuta desde este repositorio.
- `referencia/old_cspp_no_usar.sh` — la cadena monolítica anterior, solo como referencia.
- `scripts/procesar_cadena_completa.sh` — plantilla para reunificar los eslabones cuando
  todos corran solos. En espera, no en uso.
- `docs/manuals/` — manuales oficiales de CSPP y RT-STPS, sin rastrear en git. Consultar
  con `pdftotext -layout` antes de suponer cómo se comporta un driver: ahí estaba la
  respuesta a lo del `-l` de ATMOS y a las entradas que exige LSR.
