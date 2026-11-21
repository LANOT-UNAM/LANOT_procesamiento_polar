# Estado de la migración y pendientes

**Última actualización: 2026-11-21**

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

## 2026-11-21: el archivo en `/depot` pasa a tahan (`archivar.sh`)

**Hasta hoy, de la cadena nueva no se archivaba nada.** Lo que había en `/depot/polar` venía
del cron de `lanotadm` en stratus:

- `almacena_polar_raw.sh` (00:01 UTC): un `.tgz` diario con los crudos de las últimas
  24 h que llegaron a stratus (`/depot/polar/raw/<año>/<semana>/<AAAAJJJ>-polar.tgz`, de
  10 a 13 GB). Sin log, porque el cron no lo redirige. **Faltan 45 días de 2026**:
  - 9 y 10 de mayo;
  - del 1 al 12 de julio;
  - del 18 de julio al 4 de agosto;
  - del 16 al 31 de agosto.

  Además, **depende de que `copypolar.sh` siga mandando crudos a stratus**, cosa que el plan
  de operación quita.
- `almacena_polar.sh` 3.4 (06:00): **mueve** a `/depot/polar/npp_jpss/…` todo lo que produce
  la cadena vieja, en un tar por día, sensor y nivel. Solo NPP y NOAA-20, nunca NOAA-21; desde
  noviembre, solo NOAA-20. El de `noaa_metop` no encuentra nada que archivar.

`/depot` es un Lustre de 910 TB **al 96 %: 43 TB libres**.

**El criterio** salió de medir qué necesita cada etapa para regenerarse. Lo que se pierde
sin remedio es el ancillary que cambia con el tiempo, y es barato:

| Etapa | Ancillary dinámico | GB al día |
|---|---|---|
| Crudo → nivel 0 | ninguno (`leapsec.dat`) | — |
| Nivel 0 → nivel 1 (SDR) | TLE y autocalibración de VIIRS (`/data/ancillary/AAAA_MM_DD_JJJ`), LUTs (`incoming_luts`) | 0.003 (+1.9 GB de LUTs) |
| ATMOS (y LSR, CRYO) | GFS | 6.2 |
| HEAP | GFS propio | 1.0 |
| ACSPO | GFS y SST | 0.2 |
| Incendios, inundaciones, MiRS (`--noSFR`), OMPS, Polar2Grid | ninguno | — |

Con eso, más el software de cada versión, **los crudos regeneran toda la cadena**. Por eso se
archivan:

- crudos, ancillary, logs por corrida, y una instantánea de los `.sif` y de `/data/opt`;
- el nivel 2 chico: los JRR de ATMOS **sin** su GFS interpolado, más ACSPO, CRYO, incendios,
  inundaciones, MiRS, OMPS y sondeos;
- METOP niveles 1 y 2;
- las vistas.

En total, unos 13 TB al año. **No** se archivan:

| Qué | GB al día | Por qué |
|---|---|---|
| Nivel 0 | 6.8 | Se regenera de los crudos |
| Nivel 1 de JPSS | ~70 | Se regenera del nivel 0 con el ancillary guardado |
| LSR | 11.5 | Se regenera |
| GeoTIFF | — | Se regeneran |
| `NWP_GFS-GRID` y `-INTP` de ATMOS | 78 | Son el GFS de 6 GB, interpolado a cada gránulo |

Ese último es aparte un pendiente: **falta ver si algo usa el `GRID`** (1.5 GB por gránulo;
LSR y CRYO usan el `INTP`). Si nada lo usa, sobra también en `/data` y quizá en
`/dataservice`.

**`archivar.sh`**, con su tabla `config/archivo.tsv`:

- Un tar por serie y día UTC de mtime, en `/depot/polar/<destino>/<año>/<semana>/`, con un
  índice `.idx` de miembros al lado.
- Nunca reescribe ni anexa: lo tardío va a partes `.2`, `.3`…
- Verifica la lista de miembros antes de ponerlo en su nombre definitivo, y deja una reserva
  de 2 TB libres en `/depot`.
- No borra originales: eso lo hace `limpiar.sh`.
- Archiva el día D el D+2 y revisa 10 días hacia atrás. La ventana tiene que ser menor que la
  retención más corta de lo archivado (14 días).

Probado en local (filtros, parte tardía, idempotencia, sin montaje, sin espacio) y, el
2026-11-21, con una primera corrida real en tahan desde una copia en `/data/tmp`, idéntica
al commit:

- vistas desde el 29 de agosto;
- ancillary desde mayo;
- nivel 2 y METOP desde noviembre;
- crudos solo en la ventana: el buzón tiene desde el 22 de septiembre, pero eso ya está en
  `/depot` por stratus;
- el software.

**Para cancelar el respaldo de stratus falta:**

1. Instalar y poner `archivar.sh` en el cron de tahan:
   `30 5 * * * flock -n /data/tmp/archivar.lock /opt/lanot/polares/scripts/archivar.sh >> /var/log/lanot/polares/cadena/archivar.log 2>&1`
2. Comentar `almacena_polar_raw.sh` en stratus.
3. `almacena_polar.sh -s npp_jpss` sigue mientras viva la rama JPSS vieja con NOAA-20: es lo
   único que guarda sus productos, y **los borra del NFS al archivarlos**, así que quitarlo
   sin apagar la rama llenaría el disco.
4. La **prueba de restauración**: regenerar una pasada solo desde `/depot`. Es la que
   demuestra que el criterio de arriba alcanza.

**Polo (20 al 29 de septiembre) y Rachel (27 de septiembre al 11 de octubre):**

- Los crudos están completos en `/depot` del 16 de septiembre al 13 de octubre.
- Nuestras vistas de esas fechas sobrevivían en tahan (168 RGB, 396 de MiRS, 523 Skew-T) y
  quedaron archivadas antes de que `limpiar.sh` las borrara a los 90 días.
- **No** queda el ancillary: el SDR guarda 30 días y el GFS de ATMOS, 14. Para regenerar con
  la cadena nueva hay que conseguir el GFS histórico (NOAA lo conserva en AWS,
  `noaa-gfs-bdp-pds`) y ver si CSPP puede bajar los TLE y la autocalibración de esas fechas.
  MiRS no necesita GFS, pero sí SDR de ATMS.

## 2026-11-21: la primera noche de METOP con todo lo instalado el 20

Revisado en tahan lo que se instaló el 2026-11-20 y no se había visto con una pasada real.
Las dos pasadas de la noche —`chain6-4_pass54` (METOP-B, 03:50 UTC) y `chain6-5_pass55`
(METOP-C, 04:10 UTC)— y las tres diurnas de la mañana del 21 salieron solas y completas:
`Level 1 ok · AVHRR ok · sondeos ok · MiRS ok`, en 400–432 s cada una.

- **AAPP en UTC** (`666abd9`): bien. En el log de `aapp/` de la pass54, las marcas `---`
  van de `03:59:55Z` a `04:02:46Z`, y el `AVHR_xxx_1B_M01_…035950Z_…_20261121040015Z` lleva
  una creación 25 s posterior al final de la pasada, no seis horas anterior.
- **Rótulos de AVHRR** (LANOT_tools `d8ccbe3`): bien. "Metop-B Band 4 (10.8 µm)" y
  "Metop-B RGB 1-2-3a", donde la vieja dice "Metop-B BAND4". De noche salen 3b, 4 y 5 y
  el resumen dice `RGB: no (falta 3a)`, como debe; de día, las cinco bandas y el RGB. La
  banda 4 de la misma pasada en las dos cadenas es la misma escena, con la nuestra
  apenas menos contrastada.
- **MiRS** (`310a6ed`): `MiRS ok` en las cinco pasadas; un IMG y un SND por pasada, y las
  dos vistas (lluvia y agua precipitable).
- **Publicación en árboles propios** (`86c63e2`): bien. `kawak:polar/metop/avhrr` (72
  vistas) y `polar/metop/amsu-mhs` (32) al día con la pasada de las 16:40 UTC;
  `/dataservice/metop/{level1/{amsua,avhrr,iasi,mhs},level2/{mirs,sounder},vistas/{avhrr,mirs}}`
  poblado, sin fallos en ninguno de los dos logs. La vieja (`crea_vistas_metop.sh`) sigue
  llenando `noaa-metop/avhrr/vistas` con las mismas pasadas, así que la comparación del 27
  tiene material.
- **HIRS de METOP-B** falla en las 8 pasadas de ese satélite (`hirscl_algoV4 failed`), lo
  esperado (`plan_metop.md`, "El HIRS de METOP-B no calibra"): es opcional y no cuenta para
  el marcador.

Nada que corregir. Lo que sigue de METOP es la revisión del 27 para apagar la vieja.

## 2026-11-18: "retraso en `vistas/lsr`" — otra falsa alarma

Segundo reporte en la semana de que algo no se actualiza, ahora
`/dataservice/jpss/vistas/lsr`. Revisado en tahan a las 12:06 CST: **estaba al día**, con
`/dataservice` idéntico a `/data/output/jpss/vistas/lsr` y 6 vistas por día del 13 al 17
(4 el 14). Lo más nuevo era de la tarde anterior, y así tiene que ser: LSR solo da vista de
día, así que entre la última pasada de la tarde (~15 h CST) y la primera del día siguiente
(~13 h) no aparece nada durante unas 22 h. Quien mire en la mañana lo va a ver "atrasado".

Latencia del 17, de la hora de la pasada a la publicación:

| Pasada (CST) | Satélite | Vista publicada | Tiempo |
|---|---|---|---|
| 13:12 | NOAA-20 | 14:02 | ~50 min |
| 13:55 | NOAA-21 | 14:50 | ~55 min |
| 14:54 | NOAA-20 | 16:55 | ~2 h |

La tercera tardó más **por diseño**: sus gránulos pasan de las 21 UTC y piden el ciclo 18Z
del GFS, que todavía no salía. ATMOS se pospuso (código 75), y LSR no se lanzó porque
depende de ATMOS. El barrido la retomó a las 16:37. Es el mecanismo del 2026-11-03 haciendo
su trabajo: hay pasadas de la tarde que van a tardar unas dos horas, no una.

Se respondió explicando el ciclo diurno. De paso se borraron los seis `.fallido`/`.intentos`
de `state/reintentos/` que quedaban del 26 y el 28 de septiembre (ATMOS, LSR y CRYO, de antes
del arreglo del GFS). Ya no bloqueaban nada porque el barrido solo mira 24 h, pero estorbaban
al revisar. El directorio quedó vacío: no ha habido rendiciones desde entonces.

**Vistas de V8TOS: esperan a Polar2Grid 3.3** (decidido este día). El 3.3 trae lector de
V8TOS (manual §5), así que no se extiende `omps_a_geotiff.py`, que de todos modos se borra al
migrar. La elección del SO₂ y de la máscara se puede hacer antes, con los ejemplos.

### Pendiente: `vigilar.sh`, para que un fallo no se entere por un reporte

Es la condición 5 para jubilar la cadena vieja ("si una pasada falla, alguien se entera"), que
quedó sin cumplir cuando la rama JPSS vieja se apagó el 2026-11-04. Hoy no existe ningún aviso
en `scripts/`: un `.fallido`, una etapa en error o una antena que deja de entregar solo se
descubren revisando a mano o cuando alguien de fuera reporta, como hoy (y esta vez era falsa
alarma; la próxima puede no serlo).

**Propuesta**: `scripts/vigilar.sh`, en cron cada hora como `lanotadm`, que revise:

1. **Rendiciones**: un `.fallido` nuevo, de RAW (`state/<etapa>/`) o de pasada
   (`state/reintentos/`).
2. **Silencio**: más de ~13 h sin ninguna pasada procesada. Las pasadas llegan en dos bloques
   (~01–03 y ~13–15 h CST), así que un hueco mayor ya es anómalo. Es lo único que detecta que
   la antena o la recepción dejaron de entregar.
3. **Etapas en error o "a medias"** en los resúmenes de `cadena/`, sin contar "pospuesto" ni
   "sin datos".
4. **Publicación y disco**: `fallos` distinto de 0 en `publicar_dataservice.sh` o
   `publicar_kawak.sh`, y `/data` sobre ~90 %.

Avisa **solo al cambiar** (guarda lo ya avisado en `state/vigilar/`), y una vez al día manda
un "todo bien" corto, para que el silencio del propio vigilante también se note.

**Por decidir: el canal.** tahan no tiene `mail` (por eso el error del `at` del 2026-11-04
no dejó rastro). Opciones: correo con `msmtp` y una cuenta institucional; bot de Telegram
(`curl`, sin instalar nada); o webhook de Slack o Discord. Falta también a quién le llega.

**Para el portal nuevo**, como lo de kawak del 16: conviene decir junto a las vistas de LSR (y
de cualquier producto diurno) que solo hay de día, para que su ausencia en la mañana no se
lea como retraso.

---

## 2026-11-16: el fin de semana de V8TOS, y la primera pasada de V8Pro con huérfano

Revisión de las pasadas desde la instalación del 2026-11-14 (15:18 CST). Las dos diurnas
de ese día corrieron antes, así que la primera con V8TOS es del 15.

**V8TOS, en operación.** Seis pasadas diurnas `omps_tos ok`, con un V8TOS por V8TOZ en
todas (18, 20, 16, 13, 19 y 19), una de ellas en dos tramos (`j02_d20261115_t185448`). Las
nocturnas, "sin datos". `publicar_dataservice.sh` copió los 105 a `/dataservice/jpss/level2/omps`.

**Un falso fallo: V8TOZ de noche.** `j01_d20261115_t084200` (02:42 CST) salió `omps_tos fallo,
código 1`. OMPS sí dejó SDR y 16 V8TOZ de esa pasada de madrugada, así que el "sin datos" de
`procesar_pasada.sh`, que mira si hay SDR, no la detuvo; y el driver de V8TOS descartó los
16 con `WARN … excluded for SZA>90`, corrió sobre "0 contiguous runsets" y terminó en 0 sin
productos, que `run_omps_tos_edr.sh` toma por error. Arreglado: los gránulos con ese aviso se
descuentan de lo esperado y, si son todos, la etapa sale en 0 con marcador (`v8tos=0`,
`noche=16 (SZA>90)`). Lo mismo evita un "a medias" falso en una pasada que cruce el
terminador. Probado en tahan sobre esa pasada con estado y log en `/data/tmp`: código 0 y
el marcador esperado. **Falta instalarlo** y volver a correr esa pasada como `lanotadm`;
sus temporales (`/data/tmp/omps_tos_{work,staging}_1864195`) son de `lanotadm` y siguen ahí.

**OMPS, tolerancia de V8Pro: verificada.** `j01_d20261115_t084200` y `j02_d20261115_t203547`
tuvieron "1 gránulo(s) del perfilador sin mapeador" y salieron `ok` (16 V8TOz + 16 V8PRO
las dos). No ha habido todavía una pasada con más de un tramo, pero el caso que motivó el
cambio era el del huérfano, y ese pasa.

**Instalado y repasado el mismo día.** Con el arreglo en `/opt`, la pasada de madrugada quedó
con su marcador `noche=16`. La historia se pobló con un bucle sobre las pasadas de
`run_omps_tos_edr.sh --help`: las 23 con GOTCO en tahan (2026-11-09 a 16) tienen marcador,
con un V8TOS por V8TOZ en todas —tres en dos tramos—, y los 382 V8TOS están en dataservice.
Del 2 al 8 hay V8TOZ pero ya no GOTCO, así que el script no resuelve esas pasadas; se dejan
así salvo que alguien los pida.

**Sigue pendiente:** la decisión de las vistas (punto 2 de la sección siguiente).

### Vistas de SO₂: ejemplos para decidir con Víctor

**Para la junta del miércoles 2026-11-18**: https://claude.ai/artifact/2PfAevsXNGp4ZNHyq9Szue
(privada: compartirla antes desde el menú Share).

Hechas en tahan, en `/data/tmp/v8tos_vistas/` (`ejemplos.sh`, una copia de
`omps_a_geotiff.py` con `--bits`/`--bbox` y una CPT provisional `omps_so2.cpt` de 0 a 5
DU), sobre tres pasadas: NOAA-20 y NOAA-21 del 14 y NOAA-20 del 16. Cuatro alturas, tres
máscaras, recorte del centro de México a `wgs84_geo_1000m` y la pasada completa a 5 km. Lo
que mostraron:

- **TRM separa al Popo del ruido**: p99 de la pasada 0.7–2.2 DU, Popo 3.2–4.5. PBL tiene
  p99 de 4–7 DU y sin máscara es ruido de borde a borde.
- **Los bits de `s_QualityFlags_*`** (ATBD V8TOS 1.5a, tabla 2-6) que aparecen son el 0
  ("SO₂ slant column not good", 80–86 % de los píxeles) y el 3 (R331 > 15 %, nube, 30–56 %).
  **El bit 0 es buena máscara**: quita el ruido y conserva el máximo del Popo en las tres.
  **El 3 no**: borra la señal del Popo en NOAA-20 el 14 (TRM de 4.5 a 2.9 DU).
- **La mancha del 16 es la pluma, no un artefacto** (verificado el 2026-11-17 con TROPOMI).
  A las 19:32Z NOAA-20 ve una mancha coherente en las cuatro alturas sobre el norte de Puebla
  y Veracruz (PBL 20–40 DU), sobre nube brillante (R331 72 %, CF 0.87) y con `So2Index`
  alto. TROPOMI, a las 19:19Z, ve lo mismo: una pluma que nace en el Popo y se extiende al
  noreste hacia la costa, saturando la escala de 0 a 13 DU (PBL) de su mapa. MOUNTS
  (mounts-project.com/timeseries/341090, que se abre por `http://`; por `https` rechaza la
  conexión) le da al 16 una masa de 5 748 t de SO₂, de las más altas del año (mediana 2026:
  1 545 t; p90: 3 128 t; 14 nov: 429 t; 15 nov: 3 118 t). El 14, con 429 t, su pluma va al
  sureste y es corta, como la señal de nuestros ejemplos. Consecuencia para la junta: el SO₂
  sobre nube es justo lo que hay que publicar, y es otra razón para no enmascarar con el bit
  3. Para comparaciones futuras, MOUNTS publica un mapa diario de TROPOMI del Popo y la
  serie de masa, sin cuenta.
- Detalles de herramienta: `--clip` de `geotiff2view` corta *después* de decorar (logo y fecha
  a escala de la pasada completa), así que el recorte se hace al rasterizar; y un valor que
  empieza con `-` va con `=` (`--clip=-104,…`, `--sufijo=-b0`).

### kawak: "RGB, OMPS y LSR no están actualizados" — falsa alarma, con dos lecciones

Llegó el reporte de que en "JPSS/VIIRS/VISTAS" esos productos no se actualizaban. En kawak
esa ruta es literalmente `polar/npp-jpss1/viirs/vistas/`, el árbol de la **cadena vieja**:
`rgb` se quedó en el 2026-02-24, `surfreflect` y `vegindex` en el 2025-05-01, y no tiene
ozono (`npp-jpss1/omps` son quicklooks de SDR, `SOMTC_*.png`). Lo nuestro va a
`polar/jpss/` y estaba al día: lo de la pasada de las 14:14 CST, copiado a los minutos.

Pero quien entre a `polar/jpss/` también puede creer que no se actualiza: el listado de
Apache ordena por nombre ascendente y los `npp_` —muertos desde el 2026-11-02— quedan al
final de `viirs/rgb`, `dnb`, `clouds` y `omps`. Lo reciente está, pero a media lista.

**Pendiente para el portal nuevo** (no se tocó kawak):

1. Que los enlaces del menú apunten a `polar/jpss/…`, no a `npp-jpss1/viirs/vistas`.
2. Ordenar los listados por fecha, lo más nuevo arriba: `IndexOrderDefault Descending Date`
   en el `<Directory>` de `polar/jpss` (o enlazar con `?C=M;O=D`). Resuelve también lo de NPP.
3. Sacar las vistas de NPP a una carpeta aparte (`npp/` o histórico): ya no habrá más.
4. Dejar en `npp-jpss1/viirs/vistas` un aviso, o un `README`/`HEADER` de autoindex, que mande
   al árbol nuevo; o retirarlo cuando nada lo enlace.

---

## 2026-11-14: el control de determinismo, y OMPS sin huecos todavía

### ACSPO, Active Fire y MiRS, dos veces en serie

El control (job 3 de `at`, 2026-11-13 a las 10:00 CST, `--un-hilo`) corrió completo, sin
corridas fallidas, sobre `j02_d20261113_t081952` y `j01_d20261113_t091812`, con el mismo GFS
citado en las cuatro corridas. Salida en `/data/tmp/control_determinismo_20261113_100000`.

**El veredicto de su `informe.txt` es falso**: "0 iguales" en las tres etapas y las dos
variantes. El comparador contaba como diferencia la línea final de `h5diff`, *"Some objects
are not comparable"*, que sale con archivos idénticos en cuanto hay una dimensión de NetCDF
sin variable de coordenada (`h5diff -v` las nombra: `</ni> … is an empty dataset`), y los tres
EDR las tienen. Corregido en `control_determinismo.sh` (se ignoran esa línea y los datasets
vacíos; un *not comparable* por forma distinta sigue contando) y probado sobre esos mismos
`.nc` en tahan. Rehecha la comparación a mano, dataset por dataset:

| Etapa | normal (16 núcleos ACSPO, 8 MiRS) | un hilo (`SLURM_CPUS_PER_TASK=1`) |
|---|---|---|
| MiRS (4 `.nc`) | idénticos | idénticos |
| ACSPO N20 | idéntico | idéntico |
| ACSPO N21 | `l2p_flags` 60 105 px, `quality_level` 31 394 px; SST idéntica | `l2p_flags` 23 107, `quality_level` 11 309; SST idéntica |
| Fire (32 `.nc`) | 2 `AFIMG` (+ sus `AFMOD`) con un píxel distinto | idénticos |

- **MiRS es determinista.** En el 2026-10-16 solo habían diferido los de NPP (los de NOAA-20
  no), así que aquello fue de NPP o de encimar, no del algoritmo. NPP ya no se recibe.
- **Active Fire no es determinista, pero la diferencia es mínima y rara.** En el par normal,
  un gránulo de cada satélite (`j01 … t0918120`, `j02 … t0824080`) tiene exactamente un píxel
  que en una corrida es agua (`fire_mask` 3) y en la otra incendio de confianza nominal (8):
  41 contra 42 detecciones, y cambian con eso `mean_frp`, `total_frp` y el conteo. El par "un
  hilo" salió idéntico, pero no prueba nada: `run_active_fire_edr.sh` no tiene control de
  hilos, así que las dos variantes corrieron igual. Es intermitente, sin más. Concuerda con el
  2026-10-16 (6 de 19 `AFIMG`, "alguna detección de 8 de más").
- **ACSPO no es determinista en las banderas, ni a un hilo.** La SST sale idéntica entre
  repeticiones con los mismos núcleos; cambian `l2p_flags` y `quality_level`, y solo en una de
  las dos pasadas. A un hilo cambian menos, pero cambian. Aparte, **la SST depende del número
  de núcleos**: la de 16 contra la de 1 difiere en 885 903 píxeles de 24 M (355 325 por más de
  0.1 %). Es reproducible mientras no cambie `SLURM_CPUS_PER_TASK`.

Consecuencia: los `.nc` de CSPP son reproducibles en datos **salvo** Active Fire (un píxel
ocasional) y las banderas de calidad de ACSPO. Un comparador entre dos corridas tiene que
tolerar esas dos cosas. No vale la pena perseguirlo más con CIMSS: son cambios de un píxel en
el umbral de detección, y de bits de calidad con la SST intacta.

### V8TOS: SO₂ de OMPS, un eslabón nuevo

CIMSS anunció el 2026-11-10 CSPP OMPS V8TOS EDR 1.0 (correo de Kathy Strabala a
cspp_registrants; manual en `docs/manuals/CSPP_OMPS_V8TOS_EDR_Installation_Guide_v1.0.pdf`).
Calcula la **columna de SO₂** con cuatro supuestos de altura (PBL; TRL 0–5 km; TRM 5–10 km;
STL 15–19 km) y el ozono total corregido por SO₂. **No lee SDR**: su entrada son nuestros
`V8TOZ-EDR`, un V8TOS por cada uno. No usa ancillary dinámico. El interés es volcánico: el
Popocatépetl está a la vista de la antena y el servidor viejo no tiene nada parecido.

Probado en tahan el mismo día:

- **El bundle** (`cspp-omps-tos-1.0.tar.gz`, 9.8 MB) trae dos ejecutables estáticos, el
  driver `cspp-omps-tos` (Rust) y `ozv8lfso2.exe` (NOAA). La receta
  `contenedores/cspp_omps_tos_v1.0.def` parte de `lanot_base_rocky9` y no instala nada.
  **Compiló sin `sudo`** (`apptainer build --fakeroot`, Apptainer 1.5.3) y su `%test` pasa;
  la imagen está en `/data/tmp/v8tos_prueba_1329692/cspp_omps_tos_v1.0.sif`, por instalar.
- **El caso del Krakatoa** (`cspp_omps_tos_test_data.tar.gz`, 10 gránulos de NOAA-20 del
  2026-09-05) sale 10 de 10 en 4 s y 140 MB de RAM. Con `compare_omps_tos.bash` contra la
  salida de NOAA, de 1 a 42 píxeles por gránulo pasan la tolerancia de 5 DU en `s_STLO3` y
  `s_ColumnamountSO2_STL`: las "pocas, si acaso" que anuncia el manual. Es de esperar,
  porque NOAA interpola la corrección entre bloques de 5 gránulos y CSPP la promedia sobre
  el tramo (§2.2). Dentro del `.sif` sale idéntico, en datos, a la corrida nativa.
- **Con nuestros V8TOZ**, incluidos los de NOAA-21, que CSPP OMPS nombra `n21` y no `j02`
  como dice el manual: 19 de 19 en las tres pasadas probadas (13 y 14 de noviembre).
- **El driver parte la entrada en tramos continuos** ("contiguous runsets") y promedia en
  cada uno. No hay que separar las pasadas con hueco antes de llamarlo, como se pensó al
  leer el manual. Una de NOAA-20 sin hueco aparente salió en dos tramos (7 + 12) porque dos
  gránulos se traslapan 2.5 s; salieron los 19 igual.
- **La señal del Popocatépetl se ve.** En `j01_d20261114_t201010`, el máximo de SO₂ de toda la
  pasada cae a menos de 50 km del volcán: PBL 12.6 DU, TRM 4.5 DU, cuando el percentil 99 del
  resto es 4.0 y 0.76. En NOAA-21 la señal es más débil frente al ruido: su pixel es más chico
  (12 × 10 km contra 12 × 17) y sus colas son más anchas (TRM p99 2.4 DU, máximo 21 lejos del
  volcán).
- **El geolocalizado trae `LatitudeCorners`/`LongitudeCorners`**, igual que el V8TOZ, así que
  `omps_a_geotiff.py` sirve para rasterizarlo sin cambiar de método.

Lo que quedó en el repositorio:

- `scripts/run_omps_tos_edr.sh`: resuelve la pasada sobre los GOTCO de `level1/omps`, con la
  misma clave que `run_omps_edr.sh`, y enlaza los V8TOZ de su ventana (de `level2/omps`, uno
  por gránulo: el más reciente si hay reprocesos). Los V8TOS van a ese mismo directorio y el
  marcador a `state/cspp-omps-tos`. Para el marcador exige un V8TOS por V8TOZ y `exit:0` en
  cada tramo; lo parcial se entrega sin marcador, como en OMPS. Sin V8TOZ en la ventana sale
  en 0. El driver colorea su log aunque no escriba a una terminal y no respeta `NO_COLOR`:
  los códigos se quitan con `sed`. Probado en tahan con copias en `/data/tmp`: las tres
  pasadas `ok`, la segunda corrida "ya procesada", y sin contenedor, código 1.
- `procesar_pasada.sh`: `omps_tos` en el **nivel 3**, con la clave de OMPS, junto a LSR y CRYO.
  Va ahí porque come Level 2, aunque no necesite ATMOS. Si la pasada no tiene OMPS (de noche),
  sale "sin datos" igual que OMPS. Comprobado con `--dry-run` en tahan.
- La fila `bundle omps_tos_edr` en `tarballs.tsv` (slug confirmado en la portada de CSPP), la
  de `l2-omps-tos` en el catálogo y `state/cspp-omps-tos` en `preparar_servidor.sh`.

**Pendiente:**

1. ~~Instalar~~ **Hecho el 2026-11-14 a las 15:18 CST**: `cspp_omps_tos_v1.0.sif` en
   `/opt/containers` y `instalar.sh` con `02a82b3`. **Por verificar el lunes**: que las
   pasadas diurnas del fin de semana tengan `omps_tos ok` en el resumen de `cadena/` y
   `state/cspp-omps-tos/<clave>.done`, que de noche salga "sin datos", y que
   `publicar_dataservice.sh` copie los `V8TOS-EDR` de `level2/omps`. Después, poblar la
   historia: `run_omps_tos_edr.sh -p <clave>` como `lanotadm` sobre las pasadas que sigan en
   `level1/omps` (sin GOTCO no se resuelve la pasada, aunque el V8TOZ siga ahí).
2. **Vistas.** Extender `omps_a_geotiff.py` a las variables `s_*` y decidir cuáles se
   publican. TRM es el candidato natural para el Popocatépetl (5.4 km de altura); PBL capta
   fuentes industriales, como Tula. Hay que consultarlo con quien vaya a usarlo. Cada una
   necesita su CPT y su entrada en `product_map` de LANOT_tools, y eso significa mover el pin
   y recompilar el `.sif` de Polar2Grid. Falta también ver qué hacer con `ErrorFlag` y las
   `s_QualityFlags_*`, y si la vista enmascara los valores negativos, que son ruido
   (percentil 1 de −0.8 DU en TRM).
3. Al pasar a **Polar2Grid 3.3**, que trae lector de V8TOS (manual §5), revisarlo junto con el
   de V8TOZ.

### OMPS: la tolerancia de V8Pro, sin regresiones

Desde la instalación (2026-11-12, 21:36 UTC) han corrido cinco pasadas de OMPS, todas
`✅ ÉXITO` y todas con "1 tramo(s) …, 0 gránulo(s) del perfilador sin mapeador": ninguna
cambió de veredicto. **Falta todavía una pasada con hueco** para ver que salga `ok`.

---

## 2026-11-12: revisión de lo instalado el 2026-11-03 y el 4

Ocho días de operación, revisados en tahan sobre los logs de `cadena/`, `cspp-edr/` y
`cspp-sdr/`.

- **ATMOS pospuesto: bien.** Las pasadas de las 09 UTC del 5, 6, 8, 9, 10 y 11 salieron
  "pospuesto" y el reintento del barrido, una hora después, las completó (9 GeoTIFF de atmos,
  como cualquier otra). No queda ningún `atmos_work_*` ni `lsr_work_*` en `/data/tmp`.
- **kawak: bien.** Ningún tic con `fallos` distinto de 0 desde el 4. NOAA-20 sale en todas las
  carpetas, sondeos incluidos, y en `geotiff/sounder` y `vistas/sounder` ya no queda ningún
  `j01_`: el renombrado único se hizo.
- **`level2/atmos` y `level2/cryo`: bien.** No reaparecieron los nombres largos ni en `/data`
  ni en `/dataservice`. Desde la pasada de las 19:56 UTC del 4, ATMOS y LSR salen completos y
  CRYO produce. El primer tic de `publicar_dataservice.sh` tras el renombrado (14:55, después de
  50 min sin tics por el candado de `instalar.sh`) copió 0: no recopió nada.
- **El control de determinismo no corrió.** El `at` arrancó el 4 a las 10:00 como `lanotadm` y
  murió en el mismo segundo, sin crear `<base>`. Se había programado desde el clon
  (`/home/aguilars/LANOT_procesamiento_polar`). `at` guarda ese directorio y entra en él antes
  de ejecutar nada, pero `/home/aguilars` tiene 700 y `lanotadm` no puede entrar. El error iba
  al correo, y tahan no tiene `mail` (`atd: Exec failed for mail command`): no quedó rastro.
  Se descartaron las otras salidas tempranas: el script estaba instalado desde el 3 a las 12:32
  y las revisiones previas al `mkdir` pasan. Es la misma trampa del `pwd` escribible de
  `apptainer`. El ejemplo de la cabecera del script lleva ahora `cd /`. **Reprogramado desde
  `/` para el 2026-11-13 a las 10:00 CST (job 3), con `--un-hilo`.**
- **"¿Salió todo?": cinco "a medias", todas pérdidas reales de datos.**
  - **OMPS V8Pro, tres veces**: 13 de 16 (j02, 4 a las 20:40), 10 de 13 (j01, 8 a las 09:11) y
    8 de 12 (j02, 9 a las 20:48). Las tres tienen un hueco de recepción a media pasada, pero
    no siempre en el perfilador, como se anotó primero: en la del 4, los 16 `SOMPS` llegaron
    seguidos y el hueco estaba en el **mapeador** (`SOMTC` de 20:44:45 a 20:46:38). V8Pro
    necesita un gránulo de cada uno, y los del perfilador que caen en el hueco del otro
    terminan en `Does not meet data requirments`; el siguiente, como borde, a veces tampoco
    sale. **Arreglado el mismo día** (sección siguiente).
  - **CrIS SDR, dos veces**, en dos de esas mismas pasadas (8 a las 09:11, 9 a las 20:48):
    `PRO_CROSSGRAN_FAIL`, falta un `CRIS-SCIENCE-RDR`. Con la ventana de ±4 de CrIS, ese hueco
    tumba la pasada entera (`Failed to generate any SDR granules`) y la pasada se queda sin
    sondeos. Es lo esperado del contexto entre gránulos. Quedan dos `sdr_work_cris_*` vacíos en
    `/data/tmp`, que `limpiar.sh` se lleva a los 7 días.

  Que las dos clases de pérdida caigan en las mismas pasadas apunta a recepción. No se ha
  preguntado por la antena.

### OMPS: la tolerancia de V8Pro, por tramo y con los dos instrumentos

La regla de "¿salió todo?" (`79d9b1b`) le pasaba a V8Pro 2 gránulos de menos, uno por
extremo, y eso solo vale para una pasada sin huecos. Ahora `run_omps_edr.sh` calcula con
`tramos_con_pareja` (en `pasadas.sh`), sobre los `SOMPS` y `SOMTC` del staging, dos cosas:

- los gránulos del perfilador que **no tienen mapeador encima**, que no pueden salir nunca;
- en cuántos **tramos continuos** se parten los que sí lo tienen. Hay corte con más de 30 s
  entre uno y el siguiente, o con un huérfano en medio.

La tolerancia queda en 2 por tramo más los huérfanos, con un mínimo de 2, y el log de la
etapa dice los dos números. Se probó contra las 232 corridas de OMPS que hay en tahan, de
agosto a hoy, recalculada desde sus logs: las 222 que pasaban siguen pasando; 8 que salían "a
medias" pasan, todas con un hueco (perdieron 3 o 4 con tolerancia de 6 a 8); y siguen
fallando las dos del 2026-08-13 con 0 de 19, que eran el fallo real del montaje. El mapeador
tuvo hueco en las ocho, y en cinco (3, 11 dos veces y 19 de octubre, 4 de noviembre) el
perfilador venía completo: contar solo los tramos del perfilador no habría bastado.

Instalada en tahan el mismo día a las 21:36 UTC (`c34aaa4`). **Por verificar** con las
pasadas siguientes: la primera con hueco tiene que salir `ok`, y ninguna sin hueco debe
cambiar de veredicto.

### Reflectancia de superficie como fracción, no en %

Las dos notas que quedaban de Víctor (junta del 2026-10-23) quedaron aclaradas con él. La de
`surf_refl_*` cambia los datos: **se publican como fracción (0–1), igual que vienen en el
`SurfRefl_*.nc`**, y no en porcentaje.

El ×100 no es de CSPP ni de Polar2Grid sino de Satpy: su `viirs_edr.yaml` declara
`units: '%'` para los doce `surf_refl_*`, y `get_dataset()` multiplica cuando el archivo dice
`unitless`. En vez de dividir los GeoTIFF después, se le quita la causa:
`config/satpy_viirs_edr.yaml` redeclara esos doce con `units: '1'`.
`run_polar2grid_edr.sh` lo monta en `/config/satpy/readers/viirs_edr.yaml` y se lo pasa
solo a la llamada de LSR con `--extra-config-path /config/satpy`. Satpy combina los dos YAML
campo por campo. Verificado con el Satpy del bundle 3.2: cambian los doce datasets, solo en
`units`, y NDVI y EVI (que ya eran `1`) no se tocan. Sin recompilar el `.sif`.

**Vistas: ninguna cambia.** Los `surf_refl_*` no tienen vista; las de LSR son NDVI y EVI.

**Verificado en tahan el mismo día**, tras instalar `7c49b32`: se volvió a renderizar
`j02_d20261112_t195012` desde el clon con `--force`. El `surf_refl_m05` sale de −0.010 a 1.600,
contra −1.0 a 159.38 del de la víspera: el mismo dato entre 100. NDVI sigue en −1 a 1. Lo
anterior sigue en % hasta que lo pode la retención (14 días en `geotiff/`, 5 en `/dataservice`).
Al pasar a Polar2Grid 3.3, revisar si el YAML sigue haciendo falta.

**Volver a renderizar desde el clon solo funciona a medias.** Estar en el grupo de `lanotadm`
alcanza para crear y borrar en los directorios de salida, que son `775`, pero no para
sobrescribir los archivos que ya existen, que son `644`. GDAL borra el GeoTIFF y lo crea de
nuevo, así que los 41 se reemplazaron, aunque quedaron como de `aguilars`. Las vistas, el
marcador y el ozono se abren para sobrescribirlos, así que fallaron con `Permission denied` y
quedaron los de la corrida de operación (el ozono, además, porque `geotiff/omps` es `755`).
Para una prueba que reemplace productos de operación: correrla como `lanotadm`, o devolverle
los archivos después con `chown`.

---

## 2026-11-04: la rama JPSS de la cadena vieja, apagada; kawak lo publicamos todo

La rama JPSS de la cadena vieja (`cspp.sh` en stratus) ya no corre. METOP sigue aparte, en la
vieja, y en kawak vive en otro árbol: `polar/jpss` es solo nuestro. En `/dataservice` no cambia
nada, porque `publicar_dataservice.sh` ya publicaba todo.

- **`publicar_kawak.sh` deja de ser provisional**: copia las vistas de todos los satélites, no
  solo de NOAA-21. Como solo mira los últimos 2 días (`PUB_KAWAK_DIAS`), en el primer tic sube
  la NOAA-20 de ayer y hoy, y reemplaza los archivos de la vieja que se llamen igual.
- **Sondeos de NOAA-20: `noaa20_atms-cris_…`, no `j01_atms-cris_…`.** Polar2Grid nombra el
  archivo con el `platform_name` del NetCDF pasado por su tabla de alias (`polar2grid/glue.py`).
  HEAP marca NOAA-21 como `n21`, que está en la tabla, pero NOAA-20 como `j01`, que no está.
  `run_polar2grid_edr.sh` los renombra justo después de Polar2Grid y antes de vestir, así que la
  vista ya nace con el nombre bueno. Se prefirió eso a parchear la tabla dentro del `.sif`, que
  obligaba a recompilar y a cargar un segundo parche hasta Polar2Grid 3.3. La etiqueta de la
  imagen ya salía bien: `metadata.py` reconoce `j01`. Lo que ya existía en tahan se renombra a
  mano, una sola vez (abajo). `publicar_dataservice.sh` sigue aceptando `j01_` hasta que se poden
  las copias viejas de `/dataservice`, a los 5 días.

Renombrado único, en tahan, como `lanotadm` (`mv` conserva el mtime, así que ni el publicador
ni `limpiar.sh` los ven como nuevos):

```bash
for d in /data/output/jpss/geotiff/sounder /data/output/jpss/vistas/sounder; do
    for f in "$d"/j01_atms-cris_*; do [ -e "$f" ] && mv -n "$f" "$d/noaa20_${f##*/j01_}"; done
done
```

**Por verificar** en `cadena/publicar_kawak.log`: el primer tic con `noaa20_*` en todas las
carpetas de `viirs/` y en `sounder/`, y `fallos: 0`.

**Pendiente fuera del repositorio**: que la página de kawak muestre los sondeos de NOAA-20;
anunciar el cambio de las nubes (JRR en vez de CLAVR-x); retirar los symlinks
`polar/npp-jpss1/{atms,cris,omps}` de los quicklooks. **AFAI no es de esta cadena**: se encarga
Uriel, que ya lo tiene resuelto por su lado.

El crontab de `lanotadm` no cambia: la línea de `publicar_kawak.sh` es la misma. Solo su
comentario seguía diciendo "provisional, solo NOAA-21"; se corrige a mano en tahan.

### `level2/atmosphere` → `level2/atmos`, `level2/cryosphere` → `level2/cryo`

Eran las dos únicas carpetas de `level2/` con nombre largo, el del paquete de CSPP ("VIIRS
Atmosphere EDR"), mientras que `geotiff/` y `vistas/` siempre dijeron `atmos`: el mismo producto
con dos nombres según el árbol. Nunca hubo una razón; venía del primer commit de ATMOS
(2026-05-08). Se unifica ahora porque la cadena nueva no se ha anunciado y nadie de fuera
depende todavía de `/dataservice/jpss/level2/atmosphere`.

`publicar_dataservice.sh` compara por nombre, tamaño y mtime dentro de cada carpeta, y `mv` los
conserva, así que renombrando en `/data` y en `/dataservice` a la vez no se recopia nada. Los
marcadores (`state/cspp-atmos`, `state/cspp-cryo`) no dependen de la ruta. El AFAI de Uriel
(`/opt/lanot_shared`) usa copias viejas de `run_atmos_edr.sh` y `run_polar2grid_edr.sh`, pero
les pasa sus rutas por `ATMOS_OUT` y `P2G_EDR_IN`: no le afecta.

En tahan, desde el clon ya actualizado. Primero los `mv`, con el candado del publicador tomado
para que no vea una carpeta a medio renombrar; luego `instalar.sh`, que toma por su cuenta el de
la cadena y espera a la pasada en curso:

```bash
sudo flock -w 600 /data/tmp/publicar_dataservice.lock bash -c '
  set -e
  sudo -u lanotadm mv /data/output/jpss/level2/atmosphere  /data/output/jpss/level2/atmos
  sudo -u lanotadm mv /data/output/jpss/level2/cryosphere  /data/output/jpss/level2/cryo
  sudo -u lanotadm mv /dataservice/jpss/level2/atmosphere  /dataservice/jpss/level2/atmos
  sudo -u lanotadm mv /dataservice/jpss/level2/cryosphere  /dataservice/jpss/level2/cryo'
sudo ./scripts/instalar.sh
```

**No envolver `instalar.sh` en `flock /data/tmp/lanot_polares.lock`**: él mismo toma ese candado,
así que se queda esperándose a sí mismo los 45 min de `INSTALAR_ESPERA` y sale sin instalar. Así
se propuso primero, y así pasó el 2026-11-04. Los `mv` alcanzaron a hacerse; la instalación se
corrió aparte.

`/dataservice` es NFS: el `mv` va como `lanotadm`, dueño de esas carpetas, por si el servidor
aplica `root_squash`. Si alguna carpeta destino ya existe, `set -e` se detiene ahí.

---

## 2026-11-03: revisión de lo instalado el 2026-10-23

**S-NPP quedó fuera el 2026-11-02.** Su último crudo es `chain4-8_pass38_20261102T091627`
(09:16 UTC, pasada `npp_d20261102_t090426`); desde el racimo de esa tarde no llega nada por la
cadena 4. En `config/cadenas.tsv`, una fila nueva para la 4 desde las 12:00 UTC del 2 con `xml`
= `-`: los crudos de antes se siguen procesando y uno nuevo por la 4, no. Si la 4 vuelve a
entregar, es otro satélite y hay que confirmarlo con `lspass`. Lo de NPP que queda en
`/data/output/jpss` se va con la retención.

Diez días después de instalar, en tahan:

- **AFMOD**: bien. Las diez últimas pasadas dicen "N AFIMG, N AFMOD" con N igual, y hay 84
  `*_confidence_pct_*_750m.tif`.
- **EVI**: bien. Las pasadas diurnas de los tres satélites tienen vista en `vistas/lsr/`.
- **`limpiar.sh`**: corre en cron; la del 2026-11-02 borró 5037 entradas (320 GB).
- **Duración de `run_polar2grid_edr.sh`**: resuelto. Las pasadas de 21 vistas tardan
  3m11s–3m46s (2026-11-02), contra 6–8 min antes del filtro por fecha y ~5 min a fines de
  septiembre. Ojo al medir: `p2g_*.log` atrapa también los `p2g_l1_*.log`; los de Level 2 son
  `p2g_2*.log`.
- **`publicar_dataservice.sh`**: la carga terminó, `fallos: 0` en todos los tics y las
  carpetas de `level2/` y `vistas/` pobladas. Pero cada tic decía **"GeoTIFF esperando su
  marcador: ~400"**, sin bajar nunca. Eran los GeoTIFF de **sondeos, MiRS y ozono**, que no se
  publicaban: `geotiff_listo()` exigía `_viirs_` en el nombre (los suyos son `_atms-cris_`,
  `_atms_` y `_omps_`) y, aunque lo hubiera aceptado, la hora del nombre es la del primer
  gránulo de su sensor y no la clave de la pasada, que sale de VIIRS. Arreglado el 2026-11-03:
  si no hay marcador con la hora exacta, cuenta el del mismo satélite a menos de 30 min
  (`PUB_DS_MARGEN_S`). Probado en seco con un árbol simulado. Instalado el mismo día: el
  primer tic copió 316 archivos y el contador bajó de 384 a 68. Parte de esos 68 eran los de
  **flood**, que tampoco se publicaron nunca: su nombre (`noaa20_viirs_flood_<fecha>_<hora>.tif`)
  acaba en `.tif` justo después de la hora, y el patrón exigía un `_`. El resto eran los
  sondeos de **NOAA-20**, que salen como `j01_atms-cris_…` y no `noaa20_` (anotado en el
  catálogo como "nombre por corregir"): el publicador acepta ahora los dos prefijos. Arreglados
  los dos e instalados: el tic de las 11:40 copió los 68 y dejó **0 esperando su marcador**.
- **Fallos de ATMOS y LSR**: los seis `atmos_edr_*` fallidos de la última semana son de la
  primera corrida de pasadas que empiezan entre las 09:03 y las 09:24 UTC (más una de las
  20:54), lanzada a los pocos minutos: es el hueco del GFS 06Z (y 18Z) que ya se conocía. Cada
  uno deja su `atmos_work_*` y el `lsr_work_*` de detrás (20 en `/data/tmp`). No hay
  `.fallido` nuevo desde el 2026-09-28, y **el reintento termina bien**: en los logs de
  Polar2Grid, `j01_d20261103_t090400` sale dos veces, con 17 GeoTIFF en la primera (sin
  ATMOS) y 28 en la que fuerza el reintento; `j01_d20261102_t092421`, 10 y luego 21. El
  siguiente paso es que el primer intento ni se lance antes de que el ciclo esté publicado, en vez de
  fallar y conservar el trabajo.

  **Hecho el 2026-11-03.** `run_atmos_edr.sh` revisa, antes de armar el staging, qué ciclos del
  GFS necesita la pasada: las horas sinópticas que la encierran, cada una cubierta por el ciclo
  de 6 h antes (f006) o por los de 3 y 9 h antes (f003, f009), que es lo que baja `atmos-anc`.
  Un ciclo sirve si está en el caché o si ya pasaron `ATMOS_GFS_LATENCIA_MIN` (225 min) desde
  que arrancó. Si alguna hora se queda sin ciclo, sale en **75** sin tocar nada. En
  `procesar_pasada.sh`, un 75 de una etapa es "pospuesto" (no fallo), y sin marcador de ATMOS
  no se lanzan LSR ni CRYO, que solo fallaban y conservaban su directorio. El barrido retoma la
  pasada como antes, a los 60 min, y el primer intento no le cuenta. Si aun así falta
  ancillary con el ciclo ya dado por publicado, el fallo sigue siendo 1, pero ya no conserva
  el `atmos_work_*`: eran solo enlaces y la causa está en el log. Probado con reloj simulado
  (pasada de 09:04 a las 09:27 → pospone; a las 09:50, o con el f006 del 06Z en el caché → corre)
  y con `run_atmos_edr.sh` sobre un árbol falso; falta verlo en tahan una mañana.

### "Más de 0 productos" ya no es éxito en ningún EDR

Pendiente desde el 2026-09-24. Lo que cada driver escribe al terminar, leído en tahan sobre
los dos últimos logs buenos de cada uno, y lo que ahora se exige:

| EDR | remate del driver | se exige | si falta |
|---|---|---|---|
| CRYO | `completed M products of N` | M = N | se descarta; el barrido la retoma |
| LSR | `Number of Granules: N` | N `SurfRefl` | se descarta; el barrido la retoma |
| OMPS | `completed M products of N`, uno por algoritmo | M = N en V8TOZ; en V8Pro, hasta dos de menos (un gránulo por borde) | se entrega sin marcador |
| MiRS | `mirs X out of Y granules processed` | X = Y | se entrega sin marcador |
| Fire | `granule_id …: afire_rc = R, problem_rc = P` por gránulo, en cada corrida | todos en 0 y un `.nc` por gránulo | se entrega sin marcador |
| Flood | `VIIRS Flood output files = [...]` por gránulo | un `.nc` por inventario no vacío | se entrega sin marcador |
| HEAP | solo `EXECUTION COMPLETED SUCCESSFULLY` | las cinco familias con la misma cuenta | se entrega sin marcador |
| ACSPO | nada; un archivo por pasada | sigue "más de 0" | — |

Descartar solo tiene sentido donde hay reintento: el barrido retoma ATMOS, LSR y CRYO, nada
más. A los otros, borrarles lo parcial sería perderlo; sin marcador, el resumen de la pasada
los cuenta como fallo, que es lo que faltaba. Si el remate no aparece en el log (el driver
cambió), se avisa y no se tumba la etapa. Lo que **no** se atrapa: un gránulo diurno de Flood
que falle callado deja `[]` igual que uno nocturno, y HEAP no dice cuántos gránulos esperaba
—el caso de 14 de 15 del 2026-08-15 tendría las cinco familias parejas—.

**Antes de instalar**: `probar_remates.sh` aplica las mismas reglas a las 30 últimas corridas
buenas de cada EDR en tahan (solo lectura, desde el clon). Tiene que dar cero "fuera de ok",
o, si da alguno, que sea una pasada que de verdad salió a medias.

Primera corrida (2026-11-03): CRYO, MiRS, LSR, HEAP y Fire, 30 de 30 en ok; Flood, 29 de 29.
**OMPS, 11 de 30 fuera**, todas en V8Pro y ninguna en V8TOZ: diez por un producto y una
(`j01_d20261101_t205506`, la más corta, 11 de 13) por dos. Es el gránulo de cada extremo del
perfilador, que no tiene vecino, no una pasada rota: V8Pro quedó con tolerancia de dos, una
por borde. Con eso, segunda corrida: 0 fuera de ok en los siete.

## 2026-10-23: el arranque de P2G crecía con la historia, y el `.sif` de `fa99373` verificado

### La duración de `run_polar2grid_edr.sh` subía sola

Pasadas de 20 vistas, típico por semana: ~5m10s (27 sep–3 oct), ~5m15s (4–10 oct), ~5m50s
(11–16 oct), ~6m45s (17–23 oct), con 7m34s y 8m0s al final. Ningún script de render cambió en
esas fechas. Por la hora de modificación de las salidas de dos pasadas j02, la del 4 (4m51s) y
la del 23 (8m0s):

| tramo | 4 oct | 23 oct |
|---|---|---|
| arranque → primer GeoTIFF de ATMOS | 1m44s | **5m00s** |
| resto de GeoTIFF | 1m26s | 2m06s |
| vistas + Skew-T | 1m25s (2 Skew-T) | 0m54s (10 Skew-T) |

Todo el crecimiento estaba **antes** de Polar2Grid: en `enlazar_en_ventana()`, que recorre
todos los `.nc` del directorio de Level 2 y abría varios `echo | grep | sed` por **cada**
archivo antes de descartarlo por fecha. Como `/data/output/jpss` no tiene retención, el costo
crecía con la historia. La misma función, copiada, está en `run_lsr_edr.sh` (que además recorre
`level2/atmos/*.nc` entero, sin patrón) y en `run_cryo_edr.sh`, así que también se alargaban.

Arreglo: `preparar_filtro_fechas` / `en_fechas_de_ventana` en `pasadas.sh`, un descarte sin
procesos de los nombres que no llevan ninguna fecha de la ventana (calendario o juliana). Es
solo filtro previo: `sello_de_archivo()` sigue decidiendo sobre lo que pasa. Además, en la
primera pasada que corra con el cambio, los encabezados `--- sección ---` del log ya traen la
hora y hay un `--- fin ---`.

Pendiente: tras instalar, comparar la duración de las pasadas de 20 vistas contra la tabla de
arriba (se espera volver a ~5 min o menos) y el tramo hasta `--- Productos atmosféricos`.
Y sigue en pie lo de fondo: **sin retención en `/data/output/jpss`**, todo lo que liste esos
directorios se irá frenando (ver "La limpieza del pendiente 5", sección del 2026-09-27).

### Retención: `/data` se llenaba en un mes

Medido el 2026-10-23 en tahan: `/data` 37 TB, 26 usados, **11 libres**. Desde la semana 39
(NOAA-21 y la automatización) la cadena escribe **~2.4 TB por semana**, sin borrar nada:

| | por semana | acumulado |
|---|---|---|
| level0 | ~68 GB | 336 GB |
| level1 | ~800 GB | 3.7 TB |
| level2 | ~1130 GB (de ellos `atmosphere` ~1015, `lsr` ~127) | 5.2 TB |
| geotiff | ~410 GB | 1.9 TB |
| vistas | ~1 GB | 5 GB |
| `/data/tmp` | — | 1.4 TB |

El ancillary está en orden: ATMOS (91 GB) y HEAP (14 GB) se podan a 14 días por cron. En la
raíz de `/data/ancillary` quedan **~19 GB del 6–8 de mayo** (36 `gfs.*.pgrb2.0p25.*`, dos CMC y
tres `snow_map`), de antes de que ATMOS tuviera caché propio: se borran **a mano**, una vez;
`limpiar.sh` no toca nada suelto de esa raíz a propósito.

`scripts/limpiar.sh` + `config/retencion.tsv`, con los días acordados ese día: `/data/tmp` 7,
level0 14, level1 7, level2 14, geotiff 14, vistas 90, marcadores 30, directorios por día del
ancillary de SDR 30. Régimen esperado ~4 TB en vez de 12.6. Los marcadores de RT-STPS **no se
borran por edad** sino cuando su RAW ya no está en el buzón (los RAW duran ~un mes, y el
barrido revisa el buzón entero); si el buzón no se ve o está vacío, no se tocan.

**Hecho el 2026-10-23, 22:34 UTC**, como `lanotadm`, por tandas (`--margen` 28, 21, 14, 7 y
0): **8.1 TB** en menos de un minuto (borrar archivos grandes es barato); `/data` pasó de 26 TB
usados y 11 libres a 19 y 18. El cron quedó puesto enseguida.

Antes de soltarla, el `--verificar` mostró que en `/data/tmp` se habría llevado
`viirs_afai_historico` (294 GB, de sargazo, mismo usuario `lanotadm`): de ahí la columna de
patrón en `retencion.tsv`, que en `/data/tmp` deja borrar solo `<etapa>_work_*` y
`<etapa>_staging_*`. Lo demás de `/data/tmp` que es de esta cadena y ya no sirve se revisa a
mano: `CLAVRx_3_0` (30 GB), `polar2grid_l2` (28), `data` (16, datos de prueba de ATMOS),
`heap_host` (5, lo usa `diagnostico_heap_cimss.sh`), `CSPP_ATMOS_1_0` y una veintena de
`prueba_*`/`nucaps_*`/`heap_*` del diagnóstico de HEAP de agosto.


Después se borraron a mano, con confirmación, las 31 entradas viejas de `/data/tmp` que no son
temporales de etapa (234 GB: `prueba_dos_turnos_20261014_173000` sola eran 144). `/data` quedó en
19 TB usados y 19 libres (51 %); `/data/tmp`, en 295 GB, casi todo `viirs_afai_historico`.

Pendiente: **¿por qué hay tantos directorios de trabajo de ATMOS y LSR?** El 2026-10-23 quedaban
en `/data/tmp` nueve `atmos_work_*` y nueve `lsr_work_*` de la última semana, y como el
directorio solo se conserva cuando la etapa falla, eso es casi un fallo diario de cada una, sobre
todo de madrugada (los `atmos_work_*` son de las 03:xx CST, las pasadas de las 09 UTC). Lo más
probable es el caso conocido —ATMOS sin el ciclo del GFS, que el barrido reintenta a la hora, y
LSR cayendo detrás—, pero hay que confirmarlo en `/var/log/lanot/polares/cspp-edr/` y ver si
el reintento termina bien. Si es eso, los directorios se acumulan solo hasta que `limpiar.sh`
los quita a los 7 días.

Pendiente aparte: **por qué ATMOS escribe ~145 GB al día**. Puede ser lo normal de diez
familias `JRR-*` por gránulo, o duplicados de las pasadas que `barrer_pendientes.sh` retoma
(los `JRR-*` llevan `_c<sello>`, pendiente 5). Con la retención deja de ser urgente.

### Revisión de Level 2 de Víctor (junta del 2026-10-23)

Sus notas, una por una:

1. **ACSPO, "publicar el dato, no solo la vista"** y **6. los NWP de ATMOS**: los `.nc` se
   generaban y se quedaban en `level2/`; no salían porque `publicar_dataservice.sh` solo
   publicaba Level 1. El nombre que citó (`ACSPO-VIIRS_v2-80_…`) es el de la cadena vieja:
   ACSPO 3.0 nombra al estilo GHRSST. **Hecho el 2026-10-23**: las nueve familias de Level 2,
   NWP incluidos, y las vistas se publican en `/dataservice/jpss`, cada GeoTIFF junto a su
   `.nc`. Primera carga en curso esa tarde.
2. **Faltaba el AFMOD (fuegos a 750 m)**. El driver solo lo hace con `-M`, en una corrida
   aparte, y nunca se le pidió. **Hecho el 2026-10-23**: `run_active_fire_edr.sh` corre las
   dos y `run_polar2grid_edr.sh` remalla `confidence_pct`, `T13` y `power` a 750 m (sin vista).
   Por verificar con la primera pasada en operación.
3. **`confidence_cat` con valores 43–74**: el GeoTIFF que citó
   (`noaa20_viirs_confidence_cat_20261023_091135`) tiene un solo valor, 8, que es válido.
   Falta preguntarle con qué lo leyó; probablemente la vista, donde los números son colores.
   **Aclarado con él (2026-11-12).**
4. **Unidades de `surf_refl_*`**: Satpy las entrega en **porcentaje** (`viirs_edr.py:139`
   multiplica por 100). El i01 de NPP del 22: mínimo -1, máximo 159.99, media 20.8; los extremos
   son el rango válido del producto ×100. **Decidido el 2026-11-12: el dato se publica como
   fracción, sin multiplicar.** Ver la sección "2026-11-12".
5. **EVI sin GeoTIFF**: el GeoTIFF existía pero **vacío, en todas las pasadas desde mayo**, y
   por eso nunca hubo vista (código 3). La culpa no era de Polar2Grid: en los `SurfRefl_*.nc`
   el EVI valía 9.97e36 (el relleno por omisión de NetCDF) en cada píxel, con el NDVI del
   mismo archivo bien. `cspp_viirs_lsr_ndvi_evi.py` abre cada archivo en `r+`, escribe NDVI y
   EVI y **no lo cierra**; el driver lo pasa enseguida a `-o` con `shutil.move`, y como
   `/output_data` era otro montaje, `move` copió el archivo con el EVI aún en el caché de
   HDF5. El mismo cálculo, cerrando el archivo, da EVI completo. **Arreglado el 2026-10-23**
   en `run_lsr_edr.sh`: `-o /work/salida` (mismo montaje que el trabajo del driver, así que
   `move` renombra) y el script mueve a `level2/lsr` en el host. Probado en tahan sobre
   `j01_d20261023_t202135`: los 10 gránulos con ~7.7 M píxeles de EVI, como el NDVI; mediana
   ~0 en mar y ~0.1 en tierra. Lo anterior no se recupera sin reprocesar LSR.
7. **"Borrar cache cada 5 días"**: resuelto con la retención (`config/retencion.tsv`,
   `limpiar.sh`) y los 5 días de `/dataservice`. La tabla de vigencia está en el catálogo,
   sección "Cuánto se conserva".

`gdalinfo -stats` escribe un `.aux.xml` junto al GeoTIFF: en directorios de producción,
`gdalinfo -mm`.

### `.sif` con LANOT_tools `fa99373`: verificado

`apptainer inspect` confirma `fa99373` instalado. Sin `Traceback` ni errores desde el 4. La
ganancia esperada en las vistas sí se ve, aunque la tapaba el problema de arriba: las 8 vistas
de ATMOS, 31 s → 17 s; el tramo completo de vistas, 85 s → 54 s con cinco veces más Skew-T.

### `publicar_dataservice.sh`: en régimen

La carga inicial terminó. El 2026-10-23 cada tic copia solo lo nuevo, poda lo de más de 5 días
(`PUB_DS_DIAS`) y lleva **0 fallos**.

**Cambio de destinos (2026-10-23, a pedido tras la revisión de Víctor):** en `/dataservice`
cada GeoTIFF va junto a su dato. Los de Level 1 (`geotiff/{m_bands,i_bands,dnb,rgb}`) se
publican en `level1/viirs`, al lado de los SDR; en `/data/output/jpss` nada cambia. El reparto
vive en `DESTINOS` del script, y Level 2 entrará igual (`level2/acspo ← level2/acspo +
geotiff/acspo`), con el marcador de `polar2grid` en vez del de `polar2grid_l1`. Las carpetas
`geotiff/*` viejas de `/dataservice` quedan en `RETIRADAS`: solo se podan, y hacia el
**2026-10-29** estarán vacías y se pueden borrar. **Avisar a quien consuma del FTP** que las
rutas de los GeoTIFF cambian.

**Level 2 y vistas, también (2026-10-23).** Con `/dataservice/jpss` aparte de lo que publica
la cadena vieja (`npp-jpss1`), que sigue corriendo hasta que Víctor revise, se agregaron las
nueve familias de `level2/` —cada una con sus GeoTIFF de `geotiff/`— y las once carpetas de
`vistas/`, Skew-T incluidos. Dos reglas nuevas: lo que no es GeoTIFF se publica solo tras
`PUB_DS_QUIETO_MIN` (2) minutos sin cambios, porque varios drivers escriben sus `.nc` directo
en `level2/`; y nunca `*.log` ni `*.aux.xml`. Primera carga ~865 GB (`level2/atmosphere` casi
todo; `/dataservice` tenía 39 TB libres), unos 75 min a la velocidad de lectura de `/data`.

---

## 2026-10-16: la prueba de dos turnos, y el publicador en cron

### `prueba_dos_turnos.sh` (corrida del 2026-10-14, 17:30–19:04)

Dos pasadas reales, `npp_d20261014_t081833` (A) y `j01_d20261014_t083828` (B, 19 min
después), primero en serie y luego encimadas, con los scripts de `/opt` en `d76d277`. Árbol en
`/data/tmp/prueba_dos_turnos_20261014_173000` (144 GB; se puede borrar).

- **Las cuatro corridas terminaron en 0, sin etapas fallidas, y nada se escribió en
  producción** (ni productos ni logs).
- **Encimar no frena nada.** Razón simultáneo ÷ serie por etapa: mediana 0.99. El único 1.99 es
  `sdr_atms` de j01 (0.9 → 1.8 min). De reloj, 51m16s en serie y 42m53s encimadas.
- **Las dos ATMOS no coincidieron, que era lo buscado**: la de A acabó hacia las 18:40:19 y B
  arrancó RT-STPS a las 18:40:16; la de B empezó a las 18:50. Lo encimado fue la cola de A
  (ACSPO, Fire, P2G) con el arranque de B (RT-STPS, SDR). La prueba **no** dice cuánto pedirían
  dos ATMOS juntas, y no hay que provocarlo para saberlo (sección "ATMOS llena la RAM").
- **Una sola ATMOS de NPP ya llevó tahan al swap, más que el 14 a mediodía**: en serie, de
  17:42:50 a 17:44:42, el swap subió de 3 a **27 GB**, la caché cayó de ~200 GB a 3 y
  `vmstat` dejó un hueco de 46 s sin muestras (la máquina se trabó). Encimada, a las 18:35,
  19 GB. La ATMOS de NOAA-20 no tocó el swap en ninguna de las dos. Refuerza el candado o tope
  para ATMOS como condición del segundo turno.

**El informe salió con dos errores del comparador, corregidos en `prueba_dos_turnos.sh`:**

1. **Falso "❌ productos distintos: 41 y 41".** 20 eran `.PDS` de RT-STPS, que llevan la hora
   de creación tras la `S` (`S26287233000000` ÷ `S26288002117000`) y el comparador solo
   normalizaba el campo `_c`; los otros 21, los `NOAA_AFIMG_*.log` y
   `cspp_active_fire_noaa.*.log` que CSPP Active Fire deja junto a sus `.nc`, con la hora en el
   nombre. Ahora se normaliza el sello del PDS y se ignoran los `.log`: las listas coinciden.
2. **Falso "GeoTIFF con el mismo checksum: 132".** En tahan hay dos `gdalinfo`:
   `/usr/bin` (GDAL 3.10.3), que **no abre** los GeoTIFF de Polar2Grid (`not recognized as
   being in a supported file format`), y `/usr/local/bin` (3.11.5), que sí. Bajo `sudo`/`at`
   el PATH tomó el primero, todos los checksums salieron vacíos y `None == None` contó como
   igual. Ahora usa el de `/usr/local/bin` y cuenta aparte los "sin checksum" como problema.
   Cuidado con lo mismo en cualquier script que corra como `lanotadm` y llame a `gdalinfo`.

**Con el comparador corregido salen 9 GeoTIFF de 132 con píxeles distintos**: los tres de
fuego de cada satélite (`T4`, `confidence_cat`, `power`), la SST de NPP y `tpw`/`tskin` de MiRS
de NPP. Lo que se sabe:

- **La entrada es la misma**: los 243 SDR tienen datos idénticos en las dos fases (`h5diff`;
  solo cambian atributos de fecha), y ACSPO, Fire y MiRS citan los mismos
  `gfs.t00z.pgrb2.1p00.f006/f009.20261014` en sus logs.
- **Las diferencias son de algoritmo, y chicas**: MiRS, ±1 en el entero escalado del TPW en
  algunos píxeles (más `Emis`, `ChiSqr`, `CLW`); Active Fire, alguna detección de baja
  confianza (`8`) de más y el FRP en el tercer decimal (64 → 65 incendios en un gránulo).
- **No parece efecto de encimar**: la Active Fire de j01 en la fase encimada corrió a las 18:50,
  cuando A ya había terminado (18:46), y difiere igual. Lo más probable es que esos tres no sean
  deterministas —hilos, orden de suma en punto flotante—, lo que contradice la idea de que "los
  `.nc` de CSPP son reproducibles" (CLAUDE.md, de la comparación del 2026-08-29, que pudo no
  incluir estos productos).

Pendiente:

1. ~~Saber qué familias de Level 2 difieren en datos~~ (`h5diff` de los `.nc`, 2026-10-16):
   **solo las tres de arriba.** ATMOS (las diez familias `JRR-*` y los `NWP_GFS-INTP`), LSR,
   CRYO, OMPS y las cinco de NUCAPS son idénticos en datos en las dos fases; los 376 "distintos
   byte a byte" del informe eran atributos de fecha. Difieren 6 de 19 `AFIMG`, la SST de NPP
   (la de NOAA-20 no) y los dos MiRS de NPP, `IMG` y `SND` (los de NOAA-20 no).
2. ~~Confirmar el no determinismo con un control limpio~~ (**hecho el 2026-11-13**, ver
   "2026-11-14": MiRS determinista, Fire un píxel ocasional, ACSPO las banderas): la misma pasada dos veces en serie,
   solo ACSPO, Fire y MiRS. **Escrito el 2026-11-03: `scripts/control_determinismo.sh`**, que
   toma el candado de producción, corre los tres EDR dos veces sobre la última pasada de NOAA-20
   y la de NOAA-21 (NPP, donde difirieron la SST y MiRS, ya no se recibe) (salida en `/data/tmp/control_determinismo_<sello>`), compara los `.nc` dataset
   por dataset con `h5diff` sin contar atributos y deja `informe.txt` con un veredicto.
   `--un-hilo` agrega un par a un solo hilo para ver si la causa es el paralelismo. Probado con
   EDR y `h5diff` simulados; falta la corrida real (la del 2026-11-04 no corrió; reprogramada para el 13, ver "2026-11-12"). Si difieren igual, la diferencia no es de la prueba y el
   comparador debería tolerarla en esos productos; si no, sí es de encimar y hay que
   entender por qué.
3. ~~Los `.log` de Active Fire se acumulan en `level2/fires`~~. **Arreglado el 2026-10-23**:
   el driver corre en un directorio de trabajo bajo `/data/tmp` y solo los `.nc` pasan a la
   salida. Los viejos (2766) se borraron a mano el mismo día.

### `publicar_dataservice.sh`

El cron de `lanotadm` (`*/5 * * * *`) quedó puesto el 2026-10-16 hacia las 12:30. La carga
inicial interrumpida el 14 había dejado 444 GB (994 archivos, todo `level1/viirs`, de 5936 y
2.6 TB) y un temporal huérfano (`.SVDNB_npp_…h5.tmp.2687769`), que la poda del propio script
quita a los 60 min. El tic de las 12:35 arrancó y a las 12:39 iba en 495 GB. Quedan ~2.3 TB,
a ~200 MB/s (el ritmo de `/data`, sección siguiente) unas 3 h; los tics siguientes ven el
candado y salen. El log solo se escribe al terminar cada tic: `publicar_dataservice.log` no
existe hasta que acabe la carga inicial.

Pendiente: confirmar en el log que la carga inicial terminó sin fallos y que los tics
siguientes copian solo lo nuevo.

---

## 2026-10-14: discos y NFS — `/data` lee lento, `/datawork` escribe lento

Medido en tahan con `dd` y los contadores del cliente NFS (`nfsiostat`, `/proc/self/mountstats`)
mientras corría la primera publicación a `/dataservice`:

| | `/data` (4 discos giratorios de 9 TB en un LVM, local) | `/datawork` (RAID6, `172.16.1.101`, NFS 4.2) | `/dataservice` (`172.16.1.100`, NFS 4.0) |
|---|---|---|---|
| leer un archivo frío | 224 MB/s | 1.2 GB/s | — |
| leer 4 a la vez | 98 MB/s (los cabezales saltan) | 1.17 GB/s | — |
| escribir | — | **20 MB/s** con `conv=fdatasync` (4 GB en 211 s) | 1 GB/s; 180 MB/s sostenidos al publicar |

- **El NFS no es el cuello de botella en ningún caso.** 0 retransmisiones y 0 timeouts en los
  dos montajes; una escritura de 1 MB tarda 3.5–5 ms de ida y vuelta. El "cuelgue" que motivó
  revisarlo fue un `du`/`find` sobre 4.4 TB del lado remoto: 73 mil `READDIR` de ~5 ms.
- **La carga inicial de `publicar_dataservice.sh` va al ritmo de `/data`**: ~200 MB/s, unos
  65 min para los ~790 GB de 5 días (no los 15 que se estimaron con datos en caché). En
  operación no pesa: una pasada recién escrita sigue en la caché de página y sale a la
  velocidad de la red. Paralelizar el publicador empeoraría, no mejoraría.
- **`/datawork` lee al tope de 10 GbE pero escribe a 20 MB/s.** Los 4 GB cruzaron la red en
  ~20 s; el resto fue el COMMIT, el servidor asentando en disco (~190 s). Es una sola medida
  —pudo coincidir con otra carga en ese servidor—, pero tan baja que no parece ruido. Causas
  típicas en un RAID6: un rebuild o verificación en curso, la caché de escritura de la
  controladora apagada (batería/BBU agotada o en aprendizaje), o el export en `sync` sobre
  discos sin caché. Se revisa en `172.16.1.101` con la herramienta de la controladora y
  `/etc/exports`.

Pendiente:

1. **Repetir la medida de escritura en `/datawork` en un rato sin carga** (la cadena escribe
   todo el tiempo: RDR, SDR, ATMOS, GeoTIFF). Si se confirma, revisar el RAID con quien
   administra `172.16.1.101`. **Es prerrequisito de la fase 2 del plan de `/datawork`**: a
   20 MB/s la cadena se arrastraría.
2. Opcional: `/dataservice` a `vers=4.2`, como ya está `/datawork` (sesiones de 4.1: mejor
   recuperación con `soft`). Es por robustez, no por velocidad; se coordina con quien
   administra el montaje, que comparten GOES y GeoNetCast.
3. Opcional: `ens106f1` acumula ~2 millones de paquetes de recepción descartados, sin efecto
   visible en NFS. Un `ethtool -S` algún día.

---

## 2026-10-14: ATMOS llena la RAM de tahan, y por eso no caben dos a la vez

Medido con `vmstat` cada 10 s durante la pasada `npp_d20261014_t192957` (13:44–14:20 en
tahan), cruzando cada muestra con la etapa que corría. **El recurso que se agota no es la
CPU sino la memoria, y lo agota ATMOS:**

| tramo | CPU media / máx | lo que pesa |
|---|---|---|
| SDR de VIIRS | 3 % / 5 % | un `ProSdrViirsCalController` de un hilo por gránulo, 1–4 GB cada uno |
| ATMOS + ACSPO + Active Fire | 24 % / 39 % | disco: hasta 20 % de espera de E/S |
| **ATMOS sola** | 15 % / 32 % | **250 de 251 GB usados**, caché a cero, 9 GB a swap, 32 % de espera de E/S |
| MiRS + P2G de L1 | 43 % / 65 % | el tramo más cargado de CPU |
| LSR, CRYO, P2G de L2 | 5–19 % | nada |

En toda la pasada la CPU promedió 12 %. ATMOS corre todos los gránulos en paralelo (`-p 20`
con 10 gránulos) y cada uno ronda los 24 GB: a las 13:58:22 quedaban 0.9 GB libres, el
kernel tiró los 94 GB de caché y aun así mandó memoria a swap (de 3 a 12 GB). No mató nada
—el journal no tiene ningún OOM— y ATMOS completó 120 de 120 productos en 9m 48s, dentro de
lo normal para 10 gránulos (mediana 8.6 min, máximo 14.5, del 27 de septiembre al 14 de
octubre). **O sea que esto ocurre en cada pasada larga**, no fue una excepción.

Lo que implica:

- **Dos ATMOS a la vez no caben en tahan.** Pedirían el doble de la RAM, y el OOM killer
  puede matar cualquier proceso de la máquina, no solo los de la cadena. Por eso el plan de
  dos turnos (`plan_operacion_datawork.md` §0.7) necesita, antes de abrir el segundo, que
  **ATMOS corra de una en una** —un candado como el de HEAP— o un tope de gránulos en
  paralelo. Bajar `MAX_PARALELO` de 3 a 2, que es lo que decía el plan pensando en hilos, no
  protege de esto.
- Hoy no chocan por poco. Con dos turnos, la pareja más apretada es NPP → NOAA-20 (18 min
  mínimo entre recepciones): la ATMOS de NPP acaba hacia el minuto 20–25 de su corrida
  (mediana–p90) y la de NOAA-20 empezaría hacia el 29.
- **Sin NPP, que podría dejar de recibirse a fines de octubre, NOAA-20 y NOAA-21 no se enciman
  nunca** (42 min de separación mínima en 275 recepciones desde el 27 de septiembre). El
  segundo turno vuelve a hacer falta con METOP-B/C, que pasan con 22 min de diferencia.
- `scripts/prueba_dos_turnos.sh` arranca la segunda pasada 19 min después de la primera por
  esto mismo, y no acepta un desfase menor de 10 min sin `--permitir-choque`.

Pendiente: medir cuánto pide ATMOS por gránulo con `/usr/bin/time -v` o el cgroup, en vez
de deducirlo de `vmstat`, y decidir entre candado y tope.

---

## 2026-10-04: `.sif` con LANOT_tools `fa99373` — verificado el 2026-10-23

**Verificado el 2026-10-23** (ver esa sección: vistas de ATMOS 31 s → 17 s, sin errores). El 2026-10-04 a las 18:18 se instaló en tahan
`/opt/containers/polar2grid_v3.2-mapdrawer.sif` con el pin de LANOT_tools en `fa99373`
(commit `17ebd0a` de este repo). La anterior (`094db73`) quedó en
`/opt/contenedores/polar2grid_v3.2-mapdrawer.sif.094db73`. Hasta esa hora no había corrido
ninguna pasada con la imagen nueva; la última fue a las 15:58.

Qué trae: `mapdrawer`/`geotiff2view` más rápidos sin cambiar un píxel (PNG con zlib nivel
1, capas vectoriales proyectadas en arrays y leídas del gpkg solo dentro del recuadro,
`--clip` lee solo la ventana del GeoTIFF), los recursos de `/usr/local/share/lanot` desde
el repo con manifiesto (`install.sh --verifica`), y en `%files` solo los dos gpkg que
piden los `run_*.sh`. Además `mexico_estados.gpkg` ahora es la versión simplificada a
0.001° (las líneas de estados se mueven a lo sumo 1 px; el original de INEGI está en tahan
como `mexico_estados2023.gpkg`).

Ya probado antes de instalar, en tahan: `apptainer test` pasa; una M13 de NOAA-21 con la
`DECORACION` de `run_polar2grid_edr.sh` tarda **2.5 s contra 4.8 s**, y con el gpkg
original montado encima el JPEG sale **idéntico byte a byte** al de la imagen vieja.

### Qué revisar tras la primera pasada (EDR y L1)

```bash
cd /var/log/lanot/polares/polar2grid
ls -t | head -6                                   # logs posteriores a 2026-10-04 18:18
f=$(ls -t p2g_2026*.log | grep -v _l1_ | head -1)
grep -E "ÉXITO|ERROR" "$f" | tail -1              # resumen: vistas, Skew-T y duración
grep -h "⚠" "$f"                                   # comparar con los avisos de siempre (abajo)
grep -iE "Traceback|unrecognized|Error leyendo|SyntaxError" "$f"   # debe salir vacío
apptainer inspect /opt/containers/polar2grid_v3.2-mapdrawer.sif | grep LANOT_tools_commit
```

**Avisos que ya salían antes** y no son de esto: `Ozono (OMPS) falló (código 3)`,
`Sin sondeos para esta pasada`, `Vistas de inundaciones/ozono/sondeos: nada que vestir`.

**Línea base de duración** (2026-10-04, imagen `094db73`; incluye todo Polar2Grid, no solo
la decoración):

| pasada | vistas | duración |
|---|---|---|
| EDR j02 13:20 / j01 14:41 / j02 15:27 | 20 | 4m 51s / 5m 43s / 5m 29s |
| EDR npp 13:57 / 15:56 | 16 / 15 | 4m 38s / 2m 20s |
| L1 (las mismas pasadas) | 3 | 2m 24s – 3m 21s |

Esperado: unos 2 s menos por vista, o sea **~30–40 s menos en una EDR de 20 vistas** y
unos segundos en L1. Comparar contra una pasada del mismo satélite con un número de vistas
parecido; el tiempo de Polar2Grid varía con el tamaño del granulo.

Revisar también a ojo una vista con estados (`--layer MEXSTATES`) y un Skew-T en
`/data/output/jpss/vistas/`: deben verse iguales a los de antes.

**Si algo sale mal**, regresar a la imagen anterior (sudo):

```bash
sudo cp -p /opt/contenedores/polar2grid_v3.2-mapdrawer.sif.094db73 /opt/containers/polar2grid_v3.2-mapdrawer.sif.new
sudo mv /opt/containers/polar2grid_v3.2-mapdrawer.sif.new /opt/containers/polar2grid_v3.2-mapdrawer.sif
```

Al confirmarlo, cambiar el título de esta sección a "verificado" con la fecha y las
duraciones observadas, y quitar el aviso de `CLAUDE.md`.
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
   no produce en operación. Hay que traerlo o decidir explícitamente que se deja. **Decidido el
   2026-11-04: AFAI queda a cargo de Uriel**, fuera de esta cadena. Las nubes
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
4. ~~**Publica sola en kawak**~~ **Hecho el 2026-11-04, ya con la vieja apagada** (sección de
   ese día): `publicar_kawak.sh` publica todo y los sondeos de NOAA-20 ya se llaman `noaa20_…`.
   Lo de abajo queda como registro. Con las categorías de la página, sin pisar nada y a tiempo — hoy la
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
- **Qué satélite es cada `chain`**, cruzando con `lspass` (copia del 2026-09-15 en el historial: `git show a503df9:referencia/lspass.txt`):
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

El `crontab` de `lanotadm` en tahan, cotejado con `crontab -l` el 2026-10-23. Las rutas son
las de la instalación, `/opt/lanot/polares/scripts/`, no las del clon.

| Tarea | Frecuencia | Por qué | Estado |
|---|---|---|---|
| `update_sdr_daily.sh` | diaria (`40 23 * * *` CST = 05:40 UTC) | LUTs de calibración y TLE/GFS de CSPP SDR. Sin esto, la calibración se degrada con los días. | **Activa** |
| `update_atmos_ancillary.sh` | 4× al día (`17 0,6,12,18 * * *`) | CMCSST, GFS y mapa de nieve de ATMOS. El manual pide cuatro por las cuatro corridas del GFS. Incluye el podado a 14 días. | **Activa** |
| `update_heap_ancillary.sh` | semanal (`40 3 * * 0`) | **Solo poda** (14 días). HEAP baja su GFS por su cuenta al correr, pero el manual (§1.6.3) avisa que no lo borra nunca. | **Activa** |
| `barrer_pendientes.sh` | cada 15 min (`7-59/15`) | Recoge los RAW que se quedaron atrás y retoma ATMOS/LSR/CRYO de las últimas 24 h. | **Activa** |
| `publicar_kawak.sh` | cada 15 min (`12-59/15`, con `flock`) | Publica en kawak todas las vistas de JPSS: VIIRS, sondeos, Skew-T, ozono y MiRS, de todos los satélites. Hasta el 2026-11-04 solo publicaba lo que la cadena vieja no producía. | **Activa** |
| `publicar_dataservice.sh` | cada 5 min (toma su propio candado) | Copia Level 1 —SDR y GeoTIFF— a `/dataservice/jpss` para los FTP, y poda a 5 días. | **Activa** desde el 2026-10-16 |
| `obtener_tarballs.sh --novedades` | mensual | CSPP no tiene lista de correo ni RSS: de una versión nueva uno se entera si entra a la página. | **No está en cron** |
| Rotación de logs | diaria | `/var/log/lanot/polares/*/*.log` crece sin límite. Hay una configuración de `logrotate` propuesta en `README_SCRIPTS.md`. | **Pendiente de aplicar** |
| `limpiar.sh` | diaria (`30 11 * * *` CST = 17:30 UTC) | Retención de `config/retencion.tsv`: productos, temporales de etapas en `/data/tmp`, marcadores y ancillary por día de SDR (sección del 2026-10-23). | **Activa** desde el 2026-10-23 |

Ajeno a esta cadena pero en el mismo crontab y la misma máquina: desde el 2026-10-18,
**ceniza CONUS** (`/opt/lanot/ceniza`), `procesa_ceniza.sh` dos veces cada 5 min y
`vigila_ceniza.sh` cada 15. Cuenta como carga al medir duraciones.

Los `run_*.sh` **no van en cron**: los encadena `procesar_pasada.sh`, que a su vez lo dispara
`recibe.sh` cuando llega un RAW. Lo único periódico de la cadena es el barrido.

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
