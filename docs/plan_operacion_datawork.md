# Plan de operación sobre `/datawork`

**Escrito el 2026-09-14. Diseño acordado; sin implementar.** Se implementa por fases, y cada
una se anota en `estado_y_pendientes.md` cuando se hace. Sigue el formato de
`plan_orquestacion.md`: cuando algo salga distinto al implementar, se marca aquí con el
prefijo **AL IMPLEMENTAR** en vez de reescribir el diseño.

---

## Por qué

Los contenedores se hicieron en parte para poder mover la cadena a otro servidor si tahan
falla o entra a servicio. Con `/datawork` compartido por NFS entre servidores (tren2,
`172.16.1.101`), eso ya se puede hacer en serio. Hoy solo el buzón de crudos
(`/datawork/input/polar/raw`) vive ahí; todo lo demás está en el `/data` local de tahan, así
que otro servidor arrancaría sin salidas, sin marcadores `.done`, sin estáticos (los tarballs
se borran al extraerlos) y sin ancillary.

Hay tres metas, en este orden:

1. **Que la cadena corra sola**, de la antena a las vistas, con el disparo de la recepción.
2. **Que dos pasadas se procesen a la vez.** Hay pasadas separadas por menos de lo que tarda
   una en procesarse (ver 0.6), y con una sola a la vez cerca de la mitad esperaría.
3. **Que otro servidor pueda tomar el trabajo** si uno cae, sin conmutación a mano.

Slurm resolvería 2 y 3, pero el plan institucional del clúster lo pone en 2027 (fase 3b). Esto
es lo que corre mientras tanto, y lo que queda como vuelta atrás durante el piloto de Slurm.

## Decisiones tomadas

**Qué se comparte y qué no:**

| Árbol | Hoy | Destino | Por qué |
|---|---|---|---|
| Salidas + `state/` | `/data/output/jpss` | **`/datawork/output/jpss`** | Cualquier servidor ve lo hecho y retoma lo que falta |
| Estáticos | `/data/opt/{SDR_4_1,CSPP_ATMOS_1_0,RT-STPS,CSPP_HEAP_3_0}` | **`/datawork/opt/…`** | Un solo despliegue; no hay que volver a bajar decenas de GB |
| Ancillary dinámico | `/data/ancillary/*` | **`/datawork/ancillary/*`** | Todos arrancan con LUTs, TLE y GFS frescos |
| Crudos | `/datawork/input/polar/raw` | se queda | Ya estaba ahí |
| Temporales, staging, candados de turno | `/data/tmp` | se queda | Local y rápido |
| `.sif`, tarballs de build, logs, código, colortables | `/opt/…`, `/var/log/…`, `/usr/local/share/lanot` | se quedan | Uno por servidor; los `.sif` se copian con `scp`, no se recompilan |

**Cómo se procesa:**

- **Una cola en `/datawork` con turnos por servidor** (0.7). Cada pasada la toma un turno
  libre de cualquier servidor. Sustituye al candado global de `procesar_pasada.sh` y hace
  innecesaria una IP virtual para procesar.
- **tahan con dos turnos desde la fase 0**; stratus se suma cuando esté reinstalado (3a).
- **Disparo por evento, no por sondeo.** La recepción avisa al copiar; el barrido cada 15
  minutos es solo red de seguridad.
- **polaracq se conecta a la red 172 antes de la fase 0**, como goesacq. Deja de pasar por
  stratus, que hoy es el único conectado a la red de SeaSpace.
- **La cadena vieja no se toca en la fase 0**: la recepción le sigue copiando como hoy.
- **Los crudos llevan nombre único y no se podan** hasta que exista dónde archivarlos.

---

## Hallazgos del 2026-09-14 que sostienen el diseño

### La recepción, tal como corre

En `referencia/recepcion/watchpolar/`, en polaracq, usuario `teradm`:

1. `watchpolar.sh` vigila con `inotifywait` el passdisk de TeraScan (`/nexus/data1/passdisk`);
   `keepruningwatch.sh`, en cron, lo relanza si muere.
2. Con cada `CLOSE_WRITE` llama a `copypolar.sh`, que descarta los vacíos con `-s` —cada
   pasada dispara primero un cierre en cero bytes, el "Invalid file" del log—, hace `scp` a
   stratus (`lanotadm@192.168.124.211:/data/input/polar/raw/`) y después
   `ssh … /home/lanotadm/bin/recibe.sh <nombre>`, con el nombre solo.
3. El `recibe.sh` de stratus (`referencia/recepcion/recibe.sh`) manda `chain2`/`chain6` a `cspp.sh`,
   `chain4` a tsom03 y `chain5` a `metop2.sh`.

`copypolar.sh` no está versionado: se va a modificar (0.4). La copia que corre en polaracq solo
difiere de la de 2022 en el mensaje del log.

**El log de producción** (13 de marzo de 2025 al 15 de septiembre de 2026) respalda el diseño y
muestra dónde es frágil:

- 7 022 envíos, **ninguno doble** para la misma pasada: TeraScan escribe cada pasada en una sola
  apertura y cierre, así que `CLOSE_WRITE` más `-s` basta para no copiar un crudo incompleto.
- 12 s de latencia media entre el cierre del crudo y la señal en stratus (máximo 635 s).
- Dos huecos de más de 12 horas sin eventos en 18 meses. Desde que existe
  `keepruningwatch.sh` (junio de 2021) el monitor no ha estado caído más de 12 horas.
- **Las fallas pasan en silencio.** El 22 de septiembre de 2025, de las 18:49 a las 03:56, el
  `recibe.sh` de stratus tuvo un error de sintaxis (`syntax error near unexpected token
  'elif'`) y siete pasadas —cuatro JPSS: `chain2-3_pass13`, `chain6-8_pass58`,
  `chain2-4_pass14`, `chain6-9_pass59`— no se procesaron. Solo quedó en este log.
- `copypolar.sh` no revisa si el `scp` salió bien y no guarda sus errores.

### Qué satélite es cada `chain`

**El 2026-09-21, entre las 20:34 y las 22:36 UTC, TeraScan reasignó todas las cadenas** al
empezar a recibir NOAA-21. El esquema vigente sale de `referencia/terascan/system.config` (qué
telemetría tiene cada sección `[N]`) y de `lspass` del 2026-09-22 (qué satélite va en cada
telemetría; se conserva en el historial: `git show a503df9:referencia/lspass.txt`):

| Cadena | Pases | Telemetría | Satélite | Antes del 2026-09-21 |
|---|---|---|---|---|
| `chain1` | 1–10 | `jpss2db` | **NOAA-21** | Aqua |
| `chain2` | 11–20 | `jpssdb` | **NOAA-20** | NPP |
| `chain3` | 21–30 | `metopsgdb` | inactiva | NPP, sin uso desde abril de 2025 |
| `chain4` | 31–40 | `nppdb` | **NPP** | NOAA-15/19, sin uso desde agosto de 2025 |
| `chain5` | 41–50 | `aquadb` | Aqua | METOP-B/C |
| `chain6` | 51–60 | `ahrpt` | METOP-B/C (`metop-1`, `metop-3`) | NOAA-20 |

El número de pase del nombre es la columna `#` de `lspass`, en bloques de diez por cadena
(NN = 10·(N−1)+M), y la hora de modificación del crudo en stratus va en UTC. El último crudo del
esquema anterior es `chain6-8_pass58` (NOAA-20, 1.4 GB, 20:34); los de AHRPT pesan ~270 MB. El
crudo de NOAA-21 pesa el doble que uno de NOAA-20 de la misma duración (2.4 GB, 11 884 líneas).

**TeraScan ya movió satélites de cadena tres veces** (NPP de `chain3` a `chain2` y NOAA-20 de
`chain7` a `chain6` en 2025, y todo el 2026-09-21). El mapeo, que estaba repetido como
expresión regular en `recibe.sh` y en `detectar_satelite` (`run_rt_stps.sh`), vive desde el
2026-09-22 en **`config/cadenas.tsv`**, que leen `recibe.sh`, `run_rt_stps.sh` y el barrido a
través de `scripts/cadenas.sh`. Cada fila lleva desde cuándo vale, porque en el buzón conviven
crudos de los dos esquemas con el mismo nombre; al próximo cambio se agregan filas, no se
editan. **La cadena vieja de stratus no se ajustó**: su `recibe.sh` sigue con el esquema
anterior.

### Los nombres se reciclan

El passdisk usa **60 nombres** (`chainN-M_passNM`, M de 1 a 10), y cada uno aparece en 400 a
490 días distintos del log. En stratus cada pasada sobrescribe a la anterior de su ranura, así
que **la cadena vieja pierde crudos todos los días**, y no se archivan en ningún lado. Sin un
nombre único:

- un crudo nuevo sobrescribe en el buzón al anterior de su ranura si no se procesó a tiempo;
- los marcadores por nombre confunden sobrevuelos. `run_rt_stps.sh:227-237` ya lo previó
  (exige marcador más nuevo que el crudo), pero **`barrer_pendientes.sh:125-126` no**: salta
  cualquier crudo cuyo `.done` exista, así que nunca vuelve a recoger una ranura usada, y un
  `.fallido` la bloquea para siempre.

### Tamaño

Medido en el `/data/input/polar/raw` de stratus, con el esquema de cadenas anterior al
2026-09-21 (por eso la tabla va por satélite):

| Satélite | Por crudo | Pasadas al día (`lspass`, 11 al 14 de septiembre) |
|---|---|---|
| NPP | 0.8–1.4 GB | 2 a 4 |
| NOAA-20 | 0.9–1.4 GB | 2 a 3 |
| Aqua | ~1.25 GB | 2 a 4 |
| METOP-B/C | ~0.25 GB | 3 a 5 |

**~8 GB diarios de JPSS (~7 pasadas, ~2.9 TB al año) y ~12 GB con todas las cadenas (~4.4 TB
al año)**, sin contar NOAA-21, que empezó a llegar el 2026-09-21: su primer crudo pesa 2.4 GB,
el doble que uno de NOAA-20, así que el volumen de JPSS puede crecer más de lo que suma una
pasada más. Rehacer la cuenta con una semana de datos. `/datawork` (tren2, 44 TB, compartido
con GOES) aguanta meses, no años.

### Montajes

- tahan y stratus montan `/datawork` como `172.16.1.101:/data … rw,soft`, sin fijar versión de
  NFS (en tahan negocia la 4.2). Con `soft`, un tiempo de espera devuelve error de E/S al
  proceso que escribe.
- **Velocidad, medida en tahan el 2026-10-14** (detalle en `estado_y_pendientes.md`): lee a
  1.2 GB/s, el tope de 10 GbE, pero **escribe a 20 MB/s** asentado en disco (`dd …
  conv=fdatasync`, 4 GB en 211 s; el COMMIT se llevó ~190 s). El `/data` local, en cambio,
  lee a ~220 MB/s. Una sola medida: hay que repetirla sin carga y, si se confirma, revisar el
  RAID6 de `172.16.1.101` (rebuild, caché de la controladora, export en `sync`).
- tsom03 **no monta `/datawork`**: lee los crudos del `/data` de stratus en `/data2` (`hard`), y
  stratus monta a su vez el `/data` de tsom03 en `/data3`.
- stratus es CentOS (volúmenes `centos-root`), casi seguro la 7.

---

## Fase 0 — La cadena corre sola, todavía sobre `/data`

Todo se queda donde está hoy, salvo el buzón de crudos, que ya vive en `/datawork`. El objetivo
es que la cadena corra sola antes de mover nada, para que lo que falle después se pueda atribuir
a la mudanza y no a la automatización. De paso cierra tres pendientes: la pasada con los trece
eslabones, los permisos de HEAP y adoptar `lanotadm`.

**Orden:**

1. El código de 0.5 a 0.7, probado en bucefalo con `bash -n` y un `apptainer` simulado.
2. `lanotadm` e instalación (0.1).
3. El cron de ancillary (0.2).
4. `recibe.sh` a mano en tahan (0.3), incluido un par de pasadas encimadas.
5. polaracq en la 172 y el `copypolar.sh` nuevo (0.4).
6. El barrido en cron (0.5).

**Cambios de código:**

- **En este repo:** `config/cadenas.tsv`; `recibe.sh` con nombre suelto y decisión por la tabla;
  el aislamiento de cada pasada (0.6); la cola con turnos, `trabajar.sh` (0.7); y el barrido, que
  resiste nombres reciclados y filtra por cadena.
- **Fuera del repo:** solo `copypolar.sh`, en polaracq. La cadena vieja no se toca.
- **De red:** polaracq pasa a la 172.

### 0.1 La cadena corre como `lanotadm`, desde `/opt/lanot/polares`

**Código listo el 2026-09-22** (ruta y método confirmados ese día: `/opt/lanot/polares` con
`instalar.sh`, no un clon en `/opt`). `instalar.sh` espera a la pasada en curso tomando su
candado, comprueba que resuelva `config/cadenas.tsv` y ya no sugiere el enlace; los `update_*.sh`
trabajan en un directorio propio bajo `/data/tmp` en vez del `pwd` heredado. Faltan los pasos en
tahan, que siguen:

Un cron y un `ssh` que corren como `lanotadm` no pueden ejecutar desde el clon del `$HOME` de una
persona (decisión del 2026-08-29). En tahan:

1. `git pull` en el clon y `sudo ./scripts/instalar.sh`.
2. `chown -R lanotadm:lanotadm` de barrido sobre `/data/output/jpss`, `/data/tmp`,
   `/data/ancillary` y `/var/log/lanot/polares`.
3. **Sin enlace en `~lanotadm/bin`**: `copypolar.sh` llama directo a
   `/opt/lanot/polares/scripts/recibe.sh`, y `~lanotadm/bin` es el sistema viejo. (`instalar.sh`
   lo sugería; desde el 2026-09-22 ya no.)
4. Comprobar como `lanotadm` que ve imágenes y estáticos:
   `sudo -u lanotadm ./scripts/preparar_servidor.sh --verificar`.
5. **Montar `/datawork` con `hard`** en vez de `soft` (fase 1, apartado 2): el buzón vive ahí
   desde el primer día.

### 0.2 Cron de ancillary

**Instalado en tahan el 2026-09-22**, en el crontab de `lanotadm`, después de correr los tres a
mano como `lanotadm` desde `/opt`: SDR 101 archivos nuevos en 7m 57s, ATMOS 3 en 3m 50s (con su
podado), HEAP en `--dry-run` (borraría dos días, 617 MB). Ninguno tuvo problemas de permisos.

Antes del cron, correr cada uno a mano como `lanotadm` y leer su log.
`update_atmos_ancillary.sh` **no se ha ejecutado nunca**, y sin él `run_atmos_edr.sh` (que corre
con `-l`) falla en cuanto cambia la fecha.

```cron
# Cadena polar: refresco y podado del ancillary. Horas en CST (UTC-6).
PATH=/usr/local/bin:/usr/bin:/bin
MAILTO=""

# SDR: LUTs de calibración, TLE y ancillary. 23:40 CST = 05:40 UTC, antes de
# las pasadas de la mañana (07-09 UTC).
40 23 * * *        flock -n /data/tmp/update_sdr.lock   /opt/lanot/polares/scripts/update_sdr_daily.sh       >> /var/log/lanot/polares/cadena/cron.log 2>&1

# ATMOS: GFS, CMCSST, nieve. Cada 6 h, alineado con las corridas del GFS y justo
# antes de cada tanda de pasadas: 06, 12, 18 y 00 UTC.
17 0,6,12,18 * * * flock -n /data/tmp/update_atmos.lock /opt/lanot/polares/scripts/update_atmos_ancillary.sh >> /var/log/lanot/polares/cadena/cron.log 2>&1

# HEAP: solo poda lo de más de 14 días (HEAP descarga por su cuenta). Semanal.
40 3 * * 0         /opt/lanot/polares/scripts/update_heap_ancillary.sh                                    >> /var/log/lanot/polares/cadena/cron.log 2>&1
```

Acordado el 2026-09-22. Por qué así:

- **Horas en CST**, que es la hora de tahan y la que usa cron. La propuesta anterior (2, 8, 14 y
  20) daba descargas a 08, 14, 20 y 02 UTC; lo que importa es que haya una **justo antes de cada
  tanda de pasadas**, porque `run_atmos_edr.sh` corre con `-l` y solo ve el caché: 06 UTC para
  la de la mañana (07–09) y 18 UTC para la de la tarde (19–21). El GFS de 00Z ya está a las 06 y
  el de 12Z a las 18.
- **`flock -n`**: una descarga colgada no se encima con la siguiente.
- **`cadena/cron.log`** junta el resumen de cada corrida (`✅`/`❌`) y lo que falle antes de que el
  script abra su log (un contenedor que no está). El detalle sigue en `cspp-sdr/` y `cspp-edr/`.
- **`PATH` explícito**: el de cron es mínimo.

Se instala estando como `lanotadm` (`crontab -e`, sin `sudo`: `lanotadm` no está en sudoers).
Antes, cada uno a mano desde `/opt/lanot/polares/scripts/`, con `nohup` los dos que descargan, y
`update_heap_ancillary.sh --dry-run`. Se verifica al día siguiente: logs nuevos en `cspp-sdr/` y
`cspp-edr/`, un directorio del día en el caché de SDR y archivos con ctime de hoy en
`/data/ancillary/atmos`.

**Duda abierta: cuánta antigüedad del CMCSST tolera ATMOS.** Lo que se sabe (2026-09-22): SSEC
publica el análisis de un día en el directorio de ese día **después de las 17 UTC** (el del 22
seguía sin estar a las 17:12 UTC; el del 21 ya estaba a las 15:18 UTC del 22). O sea que a las
06 UTC de un día lo más nuevo suele ser el de **dos días antes**. La pasada del 22 a las 07:55 UTC
salió con el del 21 (un día antes); con uno de 25 días, ATMOS falló. Las pasadas de la mañana del
2026-09-23 lo deciden: si ATMOS sale bien, tolera dos días y el cron se queda así; si cae con
`Unable to find CMCSST`, hay que dejar que baje lo que le falte (`--download`) o buscar su
tolerancia en la configuración de CSPP ATMOS.

**Contestada el 2026-09-24**: tolera el de dos días; todas las pasadas de la mañana salieron
con él. Lo que sí faltó fue **GFS** en las pasadas de después de las 09 y las 21 UTC, que no se
arregla con el cron: `atmos-anc` no baja f012. `run_atmos_edr.sh` reintenta ahora descargando,
y el barrido retoma la pasada si ni así (ver `estado_y_pendientes.md`, 2026-09-24).

### 0.3 `recibe.sh` a mano en tahan

Como `lanotadm`, con un crudo JPSS que no tenga marcador vigente en `state/rt-stps`:

```bash
/opt/lanot/polares/scripts/recibe.sh /datawork/input/polar/raw/chain2-7_pass17_<sello>
```

Tiene que regresar enseguida —encola y lanza un trabajador en segundo plano— y dejar en `cadena/`
el log del día más el de la pasada. Esperado: los trece eslabones, HEAP incluido, con `p2g_l1` =
59 geotiff y 3 vistas. Es la primera corrida completa con HEAP dentro de `procesar_pasada.sh` y la
primera de HEAP con los permisos `go-w,g+w`.

Después, **dos crudos encimados a la vez** (un par NPP / NOAA-20 del mismo sobrevuelo) para ver
los dos turnos trabajando sin mezclar pasadas (0.6).

### 0.4 La recepción: polaracq en la 172, con copia y señal directas

1. **`copypolar.sh` copia todo al buzón compartido y avisa a todos los servidores.** Van todas
   las cadenas, no solo JPSS: en el buzón de entrada va todo junto, y es el procesamiento el que
   decide a qué sistema pertenece cada crudo.
   ```bash
   servidores="tahan"          # con stratus listo (3a): "tahan stratus"
   unico="${file}_$(date -u +%Y%m%dT%H%M%S)"
   for s in $servidores; do    # la copia, al primero que conteste
       scp "$fullfilename" "lanotadm@$s:/datawork/input/polar/tmp/$unico" &&
       ssh "lanotadm@$s" "mv /datawork/input/polar/tmp/$unico /datawork/input/polar/raw/$unico" &&
       break
   done
   for s in $servidores; do    # la señal, a todos: encolar es idempotente
       ssh "lanotadm@$s" "/opt/lanot/polares/scripts/recibe.sh $unico" >> $logfile 2>&1 &
   done
   ```
   - `tmp/` y `raw/` están en el mismo NFS, así que el `mv` es atómico y nadie ve un crudo a
     medio copiar. Un temporal dentro de `raw/` no serviría: el barrido toma todo lo que empiece
     con `chainN-` y la tabla diga que es JPSS.
   - El sufijo lo pone **quien copia**: así el nombre es el mismo para todo lo que venga después.
   - **Endurecido**, por lo que muestra el log:
     - la señal solo sale si la copia llegó entera: código de salida de `scp` revisado y tamaño
       comparado en destino antes del `mv`, con reintentos;
     - los errores de `scp` y `ssh` van al log;
     - un registro de lo enviado, más una conciliación al arrancar el monitor y cada hora,
       porque `inotify` no repite eventos;
     - la salida y el código de `recibe.sh` se registran.
   - La versión nueva se versiona en este repo, fuera de `referencia/`: pasa a ser parte de la
     cadena aunque corra en polaracq.
2. **Lo de hoy sigue igual, en paralelo.** `copypolar.sh` conserva su `scp` al
   `/data/input/polar/raw` de stratus y su `ssh` al `recibe.sh` viejo, ahora por la 172 y con el
   nombre original. Así `cspp.sh` y `metop2.sh` siguen leyendo de donde leen (Aqua ya no lo
   procesa nadie), y tsom03 no necesita montar `/datawork` todavía. El costo es copiar dos veces
   unos 12 GB diarios por la red local.
3. **`scripts/recibe.sh` decide con `config/cadenas.tsv`** (hecho el 2026-09-22, adelantado
   por el cambio de cadenas): cadena, desde cuándo, satélite, telemetría y XML. La leen también
   `run_rt_stps.sh` y el barrido.
   - JPSS (hoy `chain1`, `chain2` y `chain4`) → deja su boleto en la cola y lanza un trabajador (0.7);
   - lo que atiende otro sistema (Aqua, METOP, NOAA) → registra "no es de esta cadena" y sale
     en 0;
   - una cadena que no esté en la tabla → sale en 0 con aviso visible: lo más probable es que
     TeraScan haya reasignado cadenas otra vez. **No se mapean de antemano las cadenas sin
     uso**: si una vuelve con otro satélite, RT-STPS decodificaría con el XML equivocado sin
     avisar;
   - si el argumento no trae `/`, lo resuelve contra
     `${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}`; las rutas completas siguen valiendo para el
     uso a mano.
4. **El barrido queda como red de seguridad** (0.5 y 0.7).

**El buzón no se poda.** Con nombres únicos es la primera copia de los crudos que se conserva.
La poda se escribe solo cuando exista su archivo en el Peta 2; `almacenamiento_polar.txt`, del
repositorio LANOT_cluster, archiva level0, level1 y level2, pero no el crudo.

**Al retirar la cadena vieja**, no en la fase 0:

- `copypolar.sh` deja de copiar a stratus y de avisar a su `recibe.sh`; `cspp.sh` se apaga.
- `metop2.sh` (stratus) y `noaa2` (tsom03) cambian su `INPUT_DIR` a `/datawork/input/polar/raw`,
  y tsom03 monta `/datawork`, en la misma ruta que los demás. Los dos toman `$1`, casan por
  prefijo y comparan la ruta completa con la última procesada, así que el sufijo no les afecta.
  `referencia/noaa` es una versión anterior de `noaa2` que ya no se invoca.
- En `config/cadenas.tsv`, METOP pasa a llamada remota (`ssh stratus metop2.sh`), con el host
  por variable; lo mismo NOAA hacia tsom03 si `chain4` vuelve a llegar.

### 0.5 El barrido: red de seguridad

Pasa a `trabajar.sh --barrer` (0.7), con dos cambios respecto del `barrer_pendientes.sh` del
2026-09-14. **Los dos ya están en `barrer_pendientes.sh`** desde el 2026-09-22; falta llevarlos a
`trabajar.sh`:

- **Filtro por cadena.** Hoy llama a `procesar_pasada.sh` con cualquier archivo sin marcador. Con
  un crudo de Aqua o METOP, RT-STPS lo rechaza, el barrido cuenta el intento y a los 45 minutos lo
  marca `.fallido`, todos los días. Se salta lo que la tabla no asigne a JPSS, como ya hace
  `seleccionar_raw_mas_reciente` en `run_rt_stps.sh:115-125`.
- **Marcadores contra nombres reciclados.** `.done`, `.fallido` e `.intentos` solo cuentan si son
  más nuevos que el crudo (`-nt`), como en `run_rt_stps.sh:237`. Si el crudo es más nuevo, se
  borran los viejos antes de reintentar. Con el sufijo no debería hacer falta, pero hoy es un bug
  latente y cuesta tres líneas.

Antes de encenderlo: `--dry-run`, porque si el buzón guarda crudos que la cadena nueva nunca vio,
el primer barrido se pondría a reprocesar la historia. Luego:
`*/15 * * * * /opt/lanot/polares/scripts/trabajar.sh --barrer`.

### 0.6 Dos pasadas a la vez: aislar cada una

El 14 de septiembre pasaron NPP a las 18:54 (terminó a las 19:05) y NOAA-20 a las 19:12, y otra
vez a las 20:33 y 20:53. La cadena tarda ~30 minutos por pasada.

Hoy lo único que impide que dos pasadas se mezclen es el candado global: el código identifica "lo
suyo" por marcas de tiempo sobre directorios compartidos. Antes de abrir el segundo turno:

**Puntos 1, 2, 3 y 5 hechos el 2026-09-22**, probados en bucefalo con dos pasadas simuladas a la
vez (NOAA-20 y NOAA-21 compartiendo `level0` y `level1`): cada una derivó su propia clave. Quedan
el 6 y el 7, que son pruebas en tahan con datos reales.

1. **`run_rt_stps.sh` escribe en un directorio propio.** Hoy monta el `level0` compartido como
   `/output` y cuenta sus RDR con `find -newer` (`:348`): con otra RT-STPS corriendo, un crudo
   corrupto quedaría `.done` gracias a los RDR ajenos. Cambio: escribir en `$WORK_DIR/salida`,
   contar ahí, entregar a `level0` y dejar **la lista de sus RDR** en un manifiesto junto al
   marcador (`state/rt-stps/<crudo>.rdr`).
2. **`procesar_pasada.sh` lee ese manifiesto** en vez de `find level0 -newer marca` (`:462`), que
   tomaría también los RDR de la otra pasada.
3. **La clave sale del manifiesto del SDR de VIIRS**, no del primer `GMTCO` más nuevo que una
   marca de tiempo, que puede ser de la otra pasada: entonces todo el Level 2 correría con la clave
   ajena y el propio no se haría nunca. **Corrección al plan**: aquí decía "del RDR de VIIRS del
   manifiesto", y no sirve — los RDR llevan la órbita que les pone RT-STPS, que puede ser `b00001`
   (NOAA-21, 2026-09-22), mientras que los SDR llevan la real, calculada con el TLE. Por eso
   `run_sdr.sh` deja también su manifiesto (`state/cspp-sdr/<rdr>.prod`) y de ahí sale el `GMTCO`.
4. **OMPS y HEAP: la clave truncada es ambigua, y esto ya falla en serie.** **Hecho el
   2026-09-22**, como se describe abajo, en `procesar_pasada.sh` (`pasada_por_traslape`); los
   `run_*.sh` no cambiaron. Además, sin traslape la etapa queda `sin datos` y no `fallo`: OMPS no
   trae paquetes en las pasadas nocturnas.
   - `procesar_pasada.sh` les pasa `j01_d20260914` (`clave_truncada`), y `resolver_pasada()`
     **aborta si coincide más de una pasada**: `run_omps_edr.sh:117-128` y `:197`,
     `run_heap_edr.sh:186-197` y `:437`.
   - NOAA-20 tiene 2 o 3 pasadas diarias y NPP de 2 a 4: **desde la segunda del día**, la anterior
     sigue en `level1` y OMPS y HEAP salen con 1. El barrido solo reintenta crudos sin `.done`, así
     que esas pasadas se quedan sin ozono ni sondeos. Las pruebas no lo destaparon: ninguna tuvo
     dos pasadas del mismo satélite el mismo día.
   - Cambio: elegir la pasada de OMPS y de CrIS **por traslape temporal con la ventana de
     VIIRS**, como HEAP ya empareja ATMS (`HEAP_MARGEN_ATMS`).
5. **HEAP, de uno en uno.** Su bundle es escribible (`fort.40`) y compartido: dos HEAP
   simultáneos se pisarían, y también su descarga de GFS. Candado junto al bundle, `flock -w`
   sobre `$HOST_HEAP_HOME/.candado`, que se vuelve compartido solo con mudar el bundle en la fase
   2. HEAP tarda ~2 minutos. La espera se ajusta con `HEAP_ESPERA` (def. 1 h).
6. **Dos satélites en la misma ventana de Level 2.** Con ~20 minutos entre NPP y NOAA-20 y
   `P2G_MARGEN_MIN=10`, sus ventanas se tocan. Los separa `de_otro_satelite()`
   (`run_lsr_edr.sh:212`, `run_cryo_edr.sh:210`, `run_polar2grid_edr.sh:437`), que **nunca se ha
   probado con dos satélites en la misma ventana**. Probarlo con el par del 14 de septiembre antes
   de abrir el segundo turno.
7. **Cachés que escriben dos a la vez:** `active_fire_cache` y `acspo` (wisdom, histogram).
   Verificar que CSPP lo tolere; si no, un candado como el de HEAP.

### 0.7 La cola: cada pasada la toma un turno libre

- **Estructura**, en `/datawork/input/polar/`: `cola/` (un boleto vacío por crudo pendiente, con
  su nombre), `enproceso/<servidor>.<turno>/` y `fallidos/`.
- **Encolar.** `recibe.sh <crudo>`: si la tabla lo asigna a JPSS y no tiene `.done` vigente, crea
  `cola/<crudo>` de forma atómica e idempotente (`set -o noclobber`) y lanza un trabajador en
  segundo plano.
- **`scripts/trabajar.sh`**, nuevo, que absorbe a `barrer_pendientes.sh`:
  1. **Toma un turno libre de este servidor:** `flock -n` sobre
     `/data/tmp/lanot_polares.turno<N>.lock`, con N de 1 a `TURNOS` (2 en tahan). Si no hay, sale
     en 0: quien tenga el turno tomará el boleto al terminar.
  2. **Reclama el boleto más viejo** con `mv cola/X enproceso/<servidor>.<N>/X`. El `rename` es
     atómico en el servidor NFS y solo uno gana. Un `rename` retransmitido puede devolver error
     aunque sí se hizo: ante un fallo, comprobar si el boleto quedó en el propio directorio.
  3. **Corre `procesar_pasada.sh`** sobre el crudo y toca el boleto cada minuto como latido.
  4. **Al terminar:** si salió bien, borra el boleto; si falló, lo regresa a `cola/` con su
     contador, y al tercer intento lo mueve a `fallidos/`.
  5. **Vuelve al paso 2 mientras haya boletos.** La pasada que llegó con los turnos llenos se toma
     en cuanto uno se libera, sin sondeo.
- **Red de seguridad**, cada 15 minutos en cada servidor, `trabajar.sh --barrer`: encola los
  crudos JPSS sin `.done` vigente ni boleto (0.5), **regresa a `cola/` los boletos sin latido
  desde hace más de 10 minutos** —su servidor murió o se reinició— y drena la cola si hay turnos
  libres.
- **Concurrencia por pasada.** Con dos turnos, `MAX_PARALELO` baja de 3 a 2 para no pasar de ~64
  hilos en tahan. Variable por servidor.
- **ATMOS, de una en una.** Corrección del 2026-10-14: el límite de tahan no son los hilos sino la
  RAM. ATMOS corre todos los gránulos en paralelo y con 10 ocupa ~240 de los 251 GB (medido con
  `vmstat`; ver `estado_y_pendientes.md`, sección de esa fecha), así que dos ATMOS de turnos
  distintos no caben y el OOM killer podría matar cualquier proceso de la máquina. Antes de abrir
  el segundo turno, un candado como el de HEAP (punto 5 de §0.6) o un tope de gránulos en
  paralelo. La CPU, en cambio, sobra: una pasada promedia 12 % y no pasa de 65 %.

### Criterio para pasar a la fase 1

Varios días de pasadas procesadas solas: el ancillary se renueva, `recibe.sh` encola, los dos
turnos de tahan trabajan en paralelo sin mezclar pasadas (verificado con al menos un par NPP /
NOAA-20 encimado), la segunda pasada del día de un mismo satélite sale con OMPS y HEAP, y no hay
boletos en `fallidos/`.

---

## Fase 1 — El código para `/datawork`

### 1. Tres raíces en lugar de ~200 rutas literales

Hoy cada script declara sus rutas por omisión completas
(`ATMOS_OUT:-/data/output/jpss/level2/atmosphere`). Se agregan tres variables al principio del
bloque de configuración, y las rutas por etapa se derivan de ellas:

```bash
JPSS_SALIDA="${JPSS_SALIDA:-/datawork/output/jpss}"
JPSS_ESTATICOS="${JPSS_ESTATICOS:-/datawork/opt}"
JPSS_ANCILLARY="${JPSS_ANCILLARY:-/datawork/ancillary}"

HOST_EDR_OUT="${ATMOS_OUT:-$JPSS_SALIDA/level2/atmosphere}"
```

Los overrides por etapa (`ATMOS_*`, `P2G_*`, …) siguen funcionando igual. La decisión de qué se
comparte queda reversible con una variable (`JPSS_ANCILLARY=/data/ancillary`), y probar con un
`apptainer` simulado ya no exige exportar diez variables. Cada script sigue siendo autocontenido,
sin biblioteca común; las variables se heredan a los hijos de `procesar_pasada.sh`.

Mismo patrón en: los doce `scripts/run_*.sh`; `procesar_pasada.sh`, `trabajar.sh`, `recibe.sh`,
`publicar_vistas.sh` (solo `PUB_VISTAS`; `/data/publicacion` se queda local); los tres `update_*`
(`update_sdr_daily.sh` hoy tiene rutas fijas sin override); `scripts/preparar_servidor.sh`
(`DIRS_775`/`DIRS_755` y las fases 4 a 7); `contenedores/tarballs.tsv` (destino y comprobación
`/data/opt` → `/datawork/opt`) y los comentarios de `contenedores/obtener_tarballs.sh`.
`scripts/diagnostico_heap_cimss.sh` no se toca: está en la lista para borrarse.

### 2. `preparar_servidor.sh` separa lo compartido de lo local

- En la fase 1, lo de `/datawork` se crea la primera vez y en un segundo servidor ya existe; lo
  local (`/data/tmp`, `/var/log/lanot/polares`, `/opt/containers`) se crea en cada servidor. Las
  fases 2 a 7 ya son idempotentes (`desplegado()`).
- En `--verificar` y al principio de las fases que escriben: `findmnt -T /datawork` tiene que ser
  `nfs*`, para no poblar por error un `/datawork` local sin montar.
- En `--verificar`, como avisos:
  - uid/gid numérico de `lanotadm` igual al dueño en `/datawork` (NFS compara números, y la
    escritura en el bundle de HEAP depende del grupo);
  - `root_squash`: que el `chown` como root falle con un mensaje claro y no a medias;
  - desfase de reloj: `touch` en `/datawork` contra `date`, aviso si pasa de 2 s. Los `run_*.sh`
    hacen la marca de inicio en `/tmp` local y cuentan con `find -newer` sobre archivos que el
    servidor NFS sella con su propio reloj;
  - symlinks absolutos a `/data/…` dentro de `/datawork/opt` y `/datawork/ancillary`
    (`find -lname '/data/*'`);
  - **montaje `soft`**: con `soft`, un HDF5 o un GeoTIFF puede quedar truncado a media etapa.
    Para los servidores que procesan, `hard`. Cuando exista la NFS-HA de los trenes, el montaje
    apunta a su IP virtual (`172.16.1.102`) y no a tren2 directo.

### 3. Entrega atómica a la salida

`/data/tmp` y la salida estaban en el mismo sistema de archivos, así que `mv` era un `rename`
atómico; ahora es copia más borrado. Si la etapa muere a media copia deja un `.h5` truncado en
`level1/`, y como los nombres llevan campo de creación `_c…`, el reintento no lo sobrescribe y el
siguiente eslabón lo enlaza. Se sustituye por copiar a `$DEST/.nombre.parcial` y renombrar ahí
mismo, con una función local `entregar()` en `run_sdr.sh:410`, `run_omps_edr.sh:358`,
`run_heap_edr.sh:760` y `run_flood_edr.sh:415` (este dentro del `bash -c`, con las comillas
escapadas: verificar con el truco de `$#` = 3 de `CLAUDE.md`). Los que escriben directo en la
salida (ATMOS, Polar2Grid) no cambian.

### 4. Guarda contra `/datawork` desmontado

`run_rt_stps.sh:292/365` y `barrer_pendientes.sh:99` hacen `mkdir -p` de la salida y de `state/`:
sin NFS montado crearían un árbol local. `procesar_pasada.sh`, `trabajar.sh` y `run_rt_stps.sh`
exigen que exista `$JPSS_SALIDA/state`, sin crearlo. Es un `[ -d ]` y no un `findmnt`, para que las
pruebas con rutas en `/tmp` sigan funcionando.

### 5. Documentación

- `CLAUDE.md`: el árbol de salida es `/datawork/output/jpss`; en "Contrato host ↔ contenedor",
  estáticos y ancillary pasan a `/datawork`; una viñeta con qué es compartido y qué local, la cola
  con turnos y las trampas de NFS (reloj, uid/gid, `mv` no atómico, `soft`).
- `estado_y_pendientes.md`: "Tareas programadas" con las rutas nuevas y el mismo crontab en todos
  los servidores; cómo sumar o retirar un servidor.
- `README.md`: las menciones de `/data/opt`.
- Aviso, sin tocar: `almacenamiento_polar.txt` del repositorio LANOT_cluster lee de
  `/data/output/jpss/level0`.

---

## Fase 2 — Migración en tahan

**Prerrequisito: que `/datawork` escriba a una velocidad razonable.** El 2026-10-14 dio 20 MB/s
asentado en disco (ver "Montajes"); la cadena escribe todo el tiempo y a ese ritmo se
arrastraría. Repetir la medida sin carga antes de empezar:

```bash
d=/datawork/input/.prueba_vel; mkdir $d && dd if=/dev/zero of=$d/x bs=4M count=1024 conv=fdatasync; rm -rf $d
```

1. Detener el procesamiento: comentar el cron y quitar a tahan de la lista de `copypolar.sh`. Los
   crudos siguen llegando al buzón y sus boletos se acumulan en `cola/`. Esperar a que
   `enproceso/` quede vacío.
2. `git pull`, `sudo ./scripts/preparar_servidor.sh --verificar`, revisar los avisos de NFS, y
   `--solo 1` para crear el árbol en `/datawork`.
3. Copiar con `rsync -aHAX --numeric-ids`, que conserva los mtime de los que dependen los `.done`:
   - `/data/output/jpss/` → `/datawork/output/jpss/`
   - `/data/opt/{SDR_4_1,CSPP_ATMOS_1_0,RT-STPS,CSPP_HEAP_3_0}` → `/datawork/opt/`
   - `/data/ancillary/` → `/datawork/ancillary/`

   Repetir cada uno con `-n --itemize-changes`: no debe listar nada.
4. `--verificar` otra vez: estáticos poblados y sin symlinks a `/data`.
5. Una pasada con `--force` (ver "Verificación"). Solo entonces reactivar el cron y la lista.
6. Conservar `/data/output/jpss`, `/data/opt` y `/data/ancillary` hasta que la cola haya procesado
   algunas pasadas sola; después borrarlos.

---

## Fase 3 — Reparto entre servidores

### Dónde está Slurm en los planes del laboratorio

- Hoy no hay nada instalado; el `slurm.conf` del repositorio LANOT_cluster es un borrador, con
  tahan como controlador y único nodo.
- La v3 del *Plan de Modernización* (abril de 2026) ya no menciona Slurm, pero el entregable más
  reciente, *Plan Cluster LANOT 2026-2027* (septiembre de 2026), lo conserva en su fase 3,
  "Orquestación y resiliencia", con Slurm y Apptainer operativos en Q4 2027. **Nombra al
  procesamiento polar como piloto**, y mitiga el riesgo de regresión —con el antecedente de
  Pacemaker y GlusterFS caídos en producción— con un "piloto en una partición acotada; conservar
  los guiones actuales como vuelta atrás durante 2027".
- El mismo plan pone `/datawork` en NFS-HA con keepalived entre tren1 y tren2.

Por eso: Slurm llega, en el mejor caso, en más de un año; mientras tanto la cola reparte (3a), y
cuando llegue, entra como capa delgada que se pueda quitar (3b).

### 3a. Sumar stratus: otro trabajador de la misma cola

Va **después de las fases 1 y 2**: sin salidas, `state/`, estáticos y ancillary en `/datawork`, un
segundo servidor no sabría qué quedó hecho.

- stratus corre el mismo `trabajar.sh`, con sus propios `TURNOS` y `MAX_PARALELO`, y el mismo
  crontab. `copypolar.sh` lo agrega a su lista (`servidores="tahan stratus"`).
- **Relevo por caída.** Si un servidor muere con una pasada a medias, su boleto deja de latir y el
  barrido de otro lo regresa a la cola en 10 a 25 minutos. La pasada no escribió `.done` —el
  marcador se escribe solo al terminar bien—, así que se reprocesa, y las etapas que sí terminaron
  salen como "ya estaba".
- **Las tareas de ancillary corren una sola vez**: mismo crontab en todos, cada `update_*` envuelto
  en `flock -n /datawork/ancillary/.cron_<tarea>.lock`. `flock` sobre NFS exige NFSv4 o `lockd`; si
  no se puede, cada tarea corre solo en el primer servidor de una lista, comparando con `hostname`.
- **Antes de cada nivel, `procesar_pasada.sh` comprueba que su boleto sigue en su `enproceso/`.**
  Con montaje `hard`, un servidor que pierde NFS no muere: se congela, su boleto deja de latir y
  otro lo reencola. Al despertar, la comprobación lo detiene antes del siguiente nivel en vez de
  duplicar la pasada.
- **Lo que stratus necesita antes de entrar:** Apptainer y los `.sif`, `/usr/local/share/lanot`,
  `lanotadm` con el mismo uid/gid, `/datawork` montado con `hard`, `instalar.sh` y
  `preparar_servidor.sh --verificar` limpio. **Por ser CentOS, casi seguro la 7** (kernel 3.10,
  fuera de soporte), lo más probable es reinstalarlo antes, con Rocky 9 como pide el plan del
  clúster. Y eso solo se puede hacer después de apagar la cadena vieja que corre en él.
- **La cadena vieja** de stratus y tsom03 se apaga cuando la cadena nueva, **solo con los dos
  turnos de tahan**, lleve un tiempo sin fallos; el relevo se prueba después, con stratus
  reinstalado.

**Criterio de aceptación.** En ventana programada, se apaga un servidor con una pasada a medias:
su boleto vuelve a la cola en menos de 25 minutos, la pasada se completa en el otro sin
intervención, el resumen muestra "ya estaba" para las etapas terminadas, y al volver, el servidor
apagado no duplica nada.

### 3b. Con Slurm (2027)

**La cola se traduce casi uno a uno**, y por eso sirve de vuelta atrás durante el piloto:

| Hoy | Cola (fase 0) | Slurm |
|---|---|---|
| `ssh` → `recibe.sh` → `nohup` | boleto en `cola/` | trabajo (`sbatch procesar_pasada.sh <crudo>`) |
| `flock -n` global, salida 75 | turnos por servidor | CPU reservadas por trabajo |
| `barrer_pendientes.sh` en cron | `trabajar.sh --barrer` | **`scrontab`**, que guarda `slurmctld` y no muere con un host |
| — | latido y reencolado | `--requeue` |
| — | candado de HEAP | `--dependency=singleton` |

**Granularidad, en dos pasos:**

- **Paso A: la pasada entera como un trabajo.** Casi sin código, porque `procesar_pasada.sh` corre
  igual dentro de Slurm.
- **Paso B: una etapa, un trabajo.** `correr_tarea()` emite `sbatch --wait --parsable` con los
  recursos de cada etapa (previsto desde `plan_orquestacion.md`), y `procesar_pasada.sh` queda como
  trabajo ligero que conserva las barreras entre niveles, el resumen leído de los marcadores y "un
  fallo no detiene".
- **Descartado por ahora:** enviar de golpe el grafo con `--dependency=afterany`. Qué RDR produjo
  RT-STPS se sabe en tiempo de ejecución.

**Lo que implica más de un nodo:**

- Los `.sif` pasan a `/datawork/opt/containers`: con etapas en varios nodos, N copias a mano no se
  sostienen.
- Logs de Slurm en árbol compartido (`/datawork/log/polares`), o aceptar la dispersión.
- Por nodo: Apptainer, `/usr/local/share/lanot`, `lanotadm` con el mismo uid/gid, la llave de
  `munge`, la misma versión de Slurm y `/datawork` montado. `preparar_servidor.sh --verificar`
  puede auditarlo.
- `SlurmctldHost` con respaldo y `StateSaveLocation` en `/datawork`, o la caída del controlador se
  lleva la cola y el `scrontab`.
- Los siete `run_*.sh` con `#SBATCH` piden `--partition=normal`, que no existe en ese
  `slurm.conf` (sus particiones son `datawork` y `dataservice`); los otros cinco no traen cabecera.

---

## Fase 4 — METOP en contenedores, y apagar el sistema viejo

**El detalle de METOP vive desde el 2026-09-26 en `plan_metop.md`**, con las preguntas para quien
armó la rama vieja. Lo de abajo es el resumen con que se acordó la fase.

Acordado el 2026-09-22. El destino no es solo repartir JPSS: es que **los tres servidores
—tahan, stratus y tsom03— puedan tomar cualquier pasada**, y para eso el trabajo tiene que estar
dentro de contenedores; si no, habría que instalar AAPP, el metopizer y compañía en los tres. Eso
obliga a incorporar a esta cadena **todo lo que hoy procesa el sistema viejo, menos Aqua**, que ya
no se procesa (IPOPP quedó descontinuado y el satélite se apaga entre finales de 2026 y principios
de 2027). Mientras quede una rama fuera, el sistema viejo no se puede apagar y stratus y tsom03
siguen atados a sus instalaciones.

**Lo que falta es menos de lo que parece**, porque dos de las tres piezas ya están:

- **Sondeos de METOP: ya los cubre `cspp_heap_v3.0.sif`.** HEAP 3.0 soporta `m01` y `m03`
  (manual §1.2), que son METOP-B y METOP-C. Hoy `metop2.sh` se los manda a tsom03 con un HEAP 2.x
  aparte. `run_heap_edr.sh` ya traduce nombres de misión: habría que darle las entradas de IASI,
  AMSU y MHS en vez de CrIS y ATMS.
- **Renderizado: ya lo cubre `polar2grid_v3.2-mapdrawer.sif`.** Satpy trae los lectores
  `avhrr_l1b_aapp`, `mhs_l1c_aapp`, `amsub_l1c_aapp` e `iasi_l2`, y la vista de AVHRR que publica
  hoy la cadena vieja ya sale de Polar2Grid con nuestra rejilla.
- **Lo que hay que construir: un contenedor de Level 0 → Level 1 de METOP**, con AAPP y el
  metopizer, y su `run_metop_l1.sh` con el mismo patrón que los demás (marcador, `--force`,
  autoselección, trabajo en `/data/tmp`). `referencia/metop2.sh` es la receta de lo que hace hoy:
  `cadu_to_ccsds`, luego el metopizer y AAPP por instrumento.

**Orden sugerido**, después de la fase 3a (stratus como segundo trabajador):

1. Contenedor de METOP L1 y `run_metop_l1.sh`, probado con un crudo `chain6` real.
2. Renderizado de AVHRR con `run_polar2grid_l1.sh` (o el suyo propio), comparando con las vistas
   que publica hoy el sistema viejo.
3. Sondeos de METOP por `run_heap_edr.sh`, con las entradas de IASI/AMSU/MHS.
4. `config/cadenas.tsv` pasa a decir "de esta cadena" para METOP, y `recibe.sh` lo encola.
5. **Apagar el sistema viejo**: `cspp.sh`, `metop2.sh` y el `recibe.sh` de stratus; liberar
   `/data3` y las instalaciones de AAPP y el metopizer. Entonces `copypolar.sh` deja de copiar a
   stratus y avisa solo al buzón.
6. tsom03 entra como tercer trabajador: monta `/datawork`, Apptainer, `lanotadm` con el mismo uid
   y su turno en la cola.

**Lo que no entra:** Aqua (nadie lo procesa; sus crudos solo se guardan) y los NOAA heredados
(NOAA-15/19, sin pasadas desde agosto de 2025). METOP-SG queda fuera de esta fase pero no del
repositorio: si empieza a llegar —`chain3` es `metopsgdb`, hoy inactiva—, será otra rama y otro
contenedor, con su propio plan.

---

## Detalles por resolver

**Antes de la fase 0**

- ~~**De dónde lee el crudo el sistema que procesa Aqua**~~: **Aqua ya no se procesa en ningún
  sistema** (lo confirmó el responsable de la cadena vieja, 2026-09-22). Sus crudos siguen
  llegando por `chain5` y la tabla los registra como ajenos.
- **`polaradq` o `polaracq`**: `lspass` se corrió en `teradm@polaradq`, pero los scripts de
  recepción y `/etc/hosts` dicen `polaracq`. Confirmarlo antes de escribir llaves.
- **Dirección de polaracq en la 172**, elegida ya dentro de la tabla de mapeo de VLAN del *Plan
  Clúster Local*, para no moverla dos veces.
- **Llaves `ssh`**: la de `teradm@polaracq` hacia `lanotadm@stratus` existe por 192.168.124 y hay
  que confirmar que valga por la 172; hace falta una nueva hacia `lanotadm@tahan`.
- **Versión de NFS en tahan** (`nfsstat -m`): el `fstab` no la fija, y el candado de HEAP (0.6) y
  los de cron (3a) usan `flock` sobre NFS.
- **Cachés de ACSPO y Active Fire con dos corridas a la vez** (0.6, punto 7).
- **Qué hay hoy en el buzón**, antes de encender el barrido.
- **Cuántos días** de operación sin fallos piden la salida de la fase 0 y el apagado de la cadena
  vieja.

**Más adelante**

- **Montajes cruzados entre stratus y tsom03** (`/data2` y `/data3`): si cae stratus, lo de tsom03
  que toque `/data2` se cuelga. Cuando `noaa2` lea del buzón, averiguar si queda algo más en
  `/data2` y, si no, quitarlo.
- **Cuántas CPU tiene stratus**, para sus `TURNOS` y `MAX_PARALELO`.
- **`root_squash`** en `/datawork` y **uid/gid de `lanotadm`** en todos los servidores.
- **Nombres en `/datawork`**: si `/datawork/opt` y `/datawork/ancillary` están bien, ya que lo usan
  también GOES y otros proyectos, o si llevan un nivel `jpss/` o `polar/`.
- **Archivo de los crudos** en el Peta 2, antes de podar el buzón.

---

## Verificación

**En bucefalo, por cada cambio de código:**

- `bash -n` a los scripts tocados, y el truco de `$#` = 3 en `run_flood_edr.sh`.
- Con `apptainer` simulado: dos `trabajar.sh` a la vez sobre una cola de prueba, para ver que
  cada boleto lo toma uno solo, que el boleto sin latido se reencola y que el que falla tres veces
  acaba en `fallidos/`.
- Dos pasadas simuladas simultáneas: cada `procesar_pasada.sh` lanza SDR solo sobre los RDR de su
  manifiesto y deriva su propia clave.
- Tras la fase 1, nada literal fuera de `referencia/`, docs viejos y el diagnóstico de HEAP:
  `grep -rn '/data/output\|/data/opt\|/data/ancillary' scripts contenedores CLAUDE.md README.md`.
- `procesar_pasada.sh --dry-run` con `JPSS_SALIDA` apuntando a un directorio sin `state/`: tiene
  que negarse.

**En tahan:**

- Pasada completa: las etapas en `ok`, `p2g_l1` = **59 geotiff (M 36, I 14, dnb 7, rgb 2) y 3
  vistas** en pasada diurna, y Level 2 del orden de 31 geotiff y 16 vistas en una diurna de
  NOAA-20. Duración cercana a los ~30 minutos de referencia; si sube mucho con la salida en NFS,
  medir por etapa.
- Par encimado NPP / NOAA-20 en los dos turnos: cada pasada con su clave, sus RDR y sus productos,
  y los de Level 2 sin mezclar satélites.
- Segunda pasada del día de NOAA-20: OMPS y HEAP en `ok`.
- Tras migrar: todo escrito bajo `/datawork/output/jpss` y nada nuevo en `/data/output/jpss`; una
  pasada procesada antes de migrar se reporta como "ya estaba"; HEAP escribe su `fort.40` en
  `/datawork/opt/CSPP_HEAP_3_0` y salen las cinco familias NUCAPS.
