# Plan de monitoreo de las cadenas de procesamiento

**Escrito el 2026-09-24. Propuesta desde la cadena polar (JPSS); sin implementar.** Pensado para
servir también a la cadena de GOES y, quizá, a las de GeoNetCast. Cada cadena formula su plan y
después se cotejan. Este documento propone el **contrato común**, que es lo que tiene que salir
de ese cotejo, y lo que haría la cadena polar para cumplirlo. Mismo formato que
`plan_orquestacion.md` y `plan_operacion_datawork.md`: cuando algo salga distinto al
implementar, se marca aquí con **AL IMPLEMENTAR** en vez de reescribir el diseño.

---

## Por qué

Entre el 2026-09-23 y el 24, los dos primeros días de la cadena polar en automático, LSR falló
en **las quince pasadas**, y ATMOS dejó dos sin productos y una a medias marcada como buena. El
resumen de cada pasada lo decía (`lsr  fallo  código 1`), pero nadie lo leyó hasta que se revisó
a mano. No faltaba información. Faltaba **un lugar donde los hechos se acumulen y se puedan
consultar**, y una regla que avise cuando un patrón se repite.

Hoy el monitoreo de todas las cadenas es manual:

- **Logs de texto** por etapa, rotados (en la polar, `/var/log/lanot/polares/<etapa>/`, 30 días).
- **Correo local de cron** al buzón de `lanotadm`, archivado cada mes (ver abajo). La cadena
  polar ni siquiera usa este canal: su crontab en tahan lleva `MAILTO=""`.
- **Marcadores de estado** (`.done`), que dicen si algo está hecho pero no guardan historia: se
  sobrescriben al reprocesar, y una etapa que falla no deja ninguno.

### El correo de cron en kawak, medido el 2026-09-24

En kawak corre el cron de `lanotadm` de GOES (ABI, GLM, SUVI), de las vistas polares viejas
(`polar2jpeg.sh`, `crea_vistas_viirs.sh`, `crea_vistas_metop.sh`) y de SEMAR. **Cada ejecución
manda un correo, haya salido bien o mal**, porque ninguna tarea redirige su salida. El día
primero de cada mes, `~/bin/archivamail.sh` mueve el buzón entero (`movemail`) a
`~/archcron/<año>/<AAAAMM>`.

- **Volumen**: 128 628 mensajes en los primeros 24 días de septiembre, unos **5 400 al día**, y
  el buzón ya ocupa 700 MB. Los archivos mensuales pasaron de unos 340 MB a principios de 2026 a
  **970 MB** en agosto. Hay archivo desde 2024.
- **Quién lo llena**: `procesa_glm.sh`, que corre cada minuto, manda 34 350 correos en el mes. Le
  siguen una decena de tareas que corren cada 5 o 10 minutos, con 3 000 a 7 000 cada una.
- **Qué hay adentro**: varias tareas traen texto con forma de error (`Traceback`, `Error`,
  `No such file`, `Permission denied`) **en todas sus ejecuciones**: el convertidor de GLM
  (6 870 de 6 870), `abi_FT.py`, `GLM2png_a1.sh` y `crea_png_vientos_a1.sh` (3 435 de 3 435
  cada una). Esto no se revisó a fondo: pueden ser fallos reales crónicos o avisos inofensivos
  que contienen la palabra. En cualquier caso, un error nuevo **no se distingue** de los miles
  que ya estaban.
- **El correo no trae el código de salida**, solo la salida de la tarea. Por eso no se puede saber
  si una ejecución falló sin interpretar el texto.
- De paso: `archivamail.sh` pregunta por `$$DESTDIR` (el PID del proceso seguido de `DESTDIR`)
  en vez de `$DESTDIR`. La prueba nunca se cumple y siempre ejecuta `mkdir -p`, que no hace daño.
  Y el mensaje de enero sale con el año nuevo, porque imprime `$YEAR` en vez de `$YEARPREV`.

**Conclusión: el buzón de cron no sirve como canal de alertas tal como está.** Una alerta
escrita ahí queda enterrada entre 5 400 mensajes diarios. Y el archivo, 1 GB mensual en formato
mbox, es historia que en la práctica no se puede consultar. Sirve como punto de partida para el
plan de GOES (qué tareas fallan de forma crónica), no como sistema de monitoreo.

## Qué se monitorea: tres capas distintas

| Capa | Qué es | Ejemplo | Para qué |
|---|---|---|---|
| **Logs** | Texto libre de cada programa | la traza de CSPP con `LookForFiles` | depurar un caso ya detectado |
| **Eventos** | Un hecho con campos fijos por suceso | "LSR de la pasada X falló, código 1, 16 s" | historia, alertas, estadísticas |
| **Métricas** | Números muestreados en el tiempo | disco libre, duración de ATMOS, cola | tendencias, capacidad, tableros |

Los logs ya existen y se quedan como están. **Este plan trata sobre todo de los eventos**, que
hoy no existen y son la capa sobre la que se escriben las alertas. Las métricas quedan para el
módulo del clúster (ver "Hacia el clúster").

## Decisión central: fijar el formato, no el sistema de almacenamiento

El sistema de monitoreo del clúster todavía no se elige. Lo que no va a cambiar son los **hechos**
que produce cada cadena. Si las cadenas los escriben desde ya con un esquema común, el sistema
que venga después solo tiene que leerlos, sin tocar los scripts de producción. Y mientras tanto
se pueden consultar con `jq`, que ya está en tahan.

### El contrato: eventos en JSON Lines

Un archivo por **cadena, servidor y día**, con un objeto JSON por línea:

```
<EVENTOS_DIR>/<cadena>/<host>/AAAA-MM-DD.jsonl
```

- **Un archivo por servidor**, porque escribir al final de un mismo archivo desde varios nodos
  sobre un sistema de archivos de red no es atómico. Cada nodo escribe solo en el suyo.
- **Un archivo por día (UTC)**, para poder rotar, comprimir y archivar sin partir un día a la mitad.
- **Todo en UTC**, con la zona explícita (`Z`). Los logs de hoy mezclan CST (nombre del archivo) y
  UTC (contenido), y eso ya costó confusiones al leer los horarios del cron.
- **`EVENTOS_DIR`** tiene que ser visible desde todos los servidores de todas las cadenas.
  Candidato: `/datawork/eventos` (ver preguntas abiertas).

### Campos

**Obligatorios, comunes a todas las cadenas:**

| Campo | Tipo | Significado | Ejemplo |
|---|---|---|---|
| `ts` | texto ISO-8601 UTC | cuándo ocurrió el suceso (al terminar, si es una etapa) | `2026-09-24T21:38:21Z` |
| `cadena` | texto | qué cadena lo emite | `jpss`, `goes`, `geonetcast` |
| `host` | texto | servidor que lo emite | `tahan` |
| `origen` | texto | script que escribe el evento | `procesar_pasada` |
| `unidad` | texto | la unidad de trabajo, en el idioma de cada cadena | `j02_d20260924_t071727` |
| `etapa` | texto | el paso dentro de la cadena | `lsr` |
| `resultado` | vocabulario cerrado | ver abajo | `fallo` |

**Recomendados:**

| Campo | Tipo | Significado |
|---|---|---|
| `codigo` | entero | código de salida del proceso |
| `duracion_s` | entero | segundos que tardó |
| `productos` | entero | archivos producidos |
| `esperados` | entero | archivos que debió producir, si se sabe (para detectar `parcial`) |
| `intento` | entero | 1 la primera vez; más en los reintentos |
| `version` | texto | commit del código que corrió (`VERSION` de la instalación) |
| `log` | texto | ruta del log con el detalle |
| `mensaje` | texto | una línea legible por humanos |
| `detalle` | objeto | lo propio de cada cadena y etapa, sin esquema fijo |

La regla es que **todo lo que se quiera filtrar o agregar va en un campo de primer nivel**, y lo
demás en `detalle`. Un campo nuevo se puede agregar en cualquier momento; lo que no se hace es
cambiar el significado de uno existente.

**Vocabulario de `resultado`**, cerrado para que las consultas sean iguales en todas las cadenas:

| Valor | Significado |
|---|---|
| `recibido` | entró un insumo (un crudo de la antena, un archivo de GeoNetCast) |
| `ok` | la etapa terminó y produjo todo lo esperado |
| `parcial` | terminó, pero produjo menos de lo esperado |
| `fallo` | terminó con error |
| `sin_datos` | no había nada que procesar, y es normal (OMPS de noche, HEAP con NPP) |
| `ya_estaba` | ya estaba hecho y no se repitió |
| `reintento` | se va a volver a intentar algo que falló |
| `rendido` | se dejó de intentar |
| `publicado` | el producto quedó visible para los usuarios |

Con `recibido` y `publicado` se puede medir la **latencia de punta a punta**, desde que llega el
insumo hasta que el producto es visible. Es probablemente la cifra que más le importa al LANOT, y
hoy nadie la mide.

### Reglas para quien emite

1. **Emitir nunca rompe la cadena.** Si no se puede escribir el evento (disco lleno, montaje
   caído), se avisa en el log y se sigue. Un fallo del monitoreo no puede tirar la producción.
2. **Una línea por escritura, completa.** Se arma el JSON entero y se escribe de una vez; nunca
   por partes.
3. **JSON válido siempre.** Se genera con `jq -nc` (o con Python), no concatenando cadenas: las
   rutas y los mensajes traen comillas y acentos.
4. **El evento lo escribe quien conoce el resultado**, no cada `run_*.sh`. En la polar es
   `procesar_pasada.sh` al cosechar, que ya tiene el código, el marcador y la duración. Así un
   cambio de esquema se hace en un solo lugar.
5. **Los eventos no se borran.** Se comprimen por mes y se conservan. En la polar son unas 250
   líneas diarias (unas 15 pasadas por unas 15 etapas), unas 100 mil al año.

## Lo que haría la cadena polar

**Fase 1. Emitir.** Una biblioteca `scripts/eventos.sh` con `emitir_evento`, que cargan:

| Script | Eventos |
|---|---|
| `recibe.sh` | `recibido` por crudo; `sin_datos` si es de otra cadena (Aqua, METOP) |
| `procesar_pasada.sh` | uno por etapa al cosechar, con el resultado de la tabla del resumen |
| `barrer_pendientes.sh` | `reintento` y `rendido`, de crudos y de pasadas |
| `publicar_kawak.sh` | `publicado` por lote, con la cantidad de archivos |
| `update_*.sh` (cron) | `ok` o `fallo` del refresco de ancillary |

Para que exista `parcial`, cada etapa tiene que saber cuánto esperaba. ATMOS ya lo sabe (lee
`completed M products of N`); los demás EDR no (ver `estado_y_pendientes.md`, 2026-09-24).
Mientras no lo sepan, reportan `ok` con `productos` y sin `esperados`.

**Fase 2. Consultar y alertar.** Un script `scripts/vigilar.sh`, en cron cada hora, que lee los
eventos de las últimas 48 h y avisa si:

- una etapa tiene `fallo` o `parcial` en **tres unidades seguidas** (el caso de LSR);
- **no hubo ningún `recibido`** en más de N horas en una franja donde debería haber pasadas
  (la antena, stratus o la recepción caídos);
- hay un `rendido` nuevo;
- la latencia de `recibido` a `publicado` de una pasada pasa de un umbral.

El aviso **no puede ir al buzón de cron de `lanotadm`**: ahí se ahogaría (ver "El correo de
cron en kawak"). Opciones, de la más simple a la más completa:

- un **buzón aparte**, solo para alertas: otro usuario local o un `MAILTO` a una dirección que
  alguien sí lea;
- un **archivo de estado publicado en kawak**, una página que muestre qué está en alerta;
- un **mensaje a un canal de chat** del equipo, si existe uno.

En todos los casos el aviso se escribe también como evento (`origen: vigilar`), para que quede
constancia de qué se avisó y cuándo. Cuando llegue el
módulo del clúster, las reglas pasan a su motor de alertas y `vigilar.sh` se retira.

**Consultas de ejemplo**, para mostrar que el formato alcanza sin más infraestructura:

```bash
# ¿Qué falló hoy?
jq -c 'select(.resultado=="fallo") | {ts,unidad,etapa,codigo,log}' eventos/jpss/tahan/2026-09-24.jsonl

# Duración media de ATMOS en septiembre
cat eventos/jpss/*/2026-09-*.jsonl | jq -s '[.[]|select(.etapa=="atmos" and .resultado=="ok")|.duracion_s] | add/length'

# Latencia antena → publicación por pasada
cat eventos/jpss/*/2026-09-24.jsonl | jq -s 'group_by(.unidad) | map({unidad: .[0].unidad,
  recibido: (map(select(.resultado=="recibido"))|.[0].ts),
  publicado: (map(select(.resultado=="publicado"))|last.ts)})'
```

**Aquí no hay que resolver ni la correlación entre crudo y pasada ni la de publicación y
pasada.** Hoy `recibe.sh` conoce el crudo (`chain1-10_pass10_…`) y `procesar_pasada.sh` conoce
la clave de la pasada (`j02_d20260924_t200952`). Para la latencia, los eventos de
`procesar_pasada.sh` deben llevar **los dos** en `detalle` (`crudo` y `pasada`), y
`publicar_kawak.sh` debe decir qué pasadas publicó. Esto se precisa al implementar.

## Hacia el clúster

Lo que se escriba con este contrato se conserva cuando llegue el módulo del clúster; solo cambia
quién lo lee. Opciones, sin decidir:

| Pieza | Para qué | A favor | En contra |
|---|---|---|---|
| **Loki + Grafana** (Promtail o Vector leen los `.jsonl`) | eventos y logs | se come el JSONL tal cual, con tableros y alertas; sirve también para los logs de texto | otro servicio que operar |
| **PostgreSQL / TimescaleDB** (un recolector inserta) | eventos | SQL completo para preguntas del tipo "pasadas de NOAA-21 sin ATMOS en septiembre" | hay que administrar la base |
| **Prometheus + Alertmanager** | métricas | el estándar para disco, CPU, colas y Slurm | no es para eventos individuales: complementa, no sustituye |
| **`sacct` de Slurm** | contabilidad de trabajos | viene con Slurm | solo ve trabajos, no el sentido de la cadena |
| **SQLite** | — | cero infraestructura | **no sirve en el clúster**: varios escritores sobre un sistema de archivos de red la corrompen o la traban |

La configuración que se ve venir es **Prometheus para métricas, Loki o Postgres para eventos, y
Grafana encima de todo**, más `sacct`. Pero eso lo decide el plan del clúster, no este.

## Qué debería traer el plan de cada cadena, para cotejarlos

Para que el plan de GOES y el de GeoNetCast se puedan cazar con este, conviene que cada uno
conteste lo mismo:

1. **¿Cuál es su unidad de trabajo?** En la polar, la pasada; en GOES, probablemente la escena
   ABI por sector y hora; en GeoNetCast, quizá el archivo recibido. Eso llena `unidad`.
2. **¿Cuáles son sus etapas?** La lista de valores de `etapa`.
3. **¿Qué script conoce el resultado de cada etapa?** Ahí va la emisión.
4. **¿Cómo sabe cuánto esperaba?** Para poder distinguir `parcial` de `ok`.
5. **¿Qué patrones le habrían avisado a tiempo de sus fallos pasados?** Esas son sus primeras
   reglas de alerta.
6. **¿En qué servidores corre, y qué ve cada uno?** Para decidir `EVENTOS_DIR`.
7. **¿Qué necesita en `detalle`** que no quepa en los campos comunes?

Si alguna cadena necesita un valor de `resultado` que no está en la lista, se agrega a la lista
común. No se inventa por separado.

## Preguntas abiertas

- **`EVENTOS_DIR`**: ¿`/datawork/eventos`, visible por NFS desde todos los servidores? ¿Lo ven
  también los de GOES y GeoNetCast?
- **Canal de alertas**: el buzón de cron de `lanotadm` está descartado (ver arriba). ¿Buzón
  aparte, página en kawak o chat?
- **El ruido de cron en kawak** es tarea del plan de GOES, pero afecta a todos: mientras cada
  ejecución mande correo, ese canal no sirve para nada. Lo habitual es que cada tarea mande su
  salida a un log y que cron solo envíe correo cuando algo falla.
- **¿Quién consulta?** Si son solo los desarrolladores, `jq` alcanza por un buen rato. Si son
  operadores u otras áreas, el tablero se justifica antes.
- **¿Hay ya algo en el LANOT** (Grafana, Zabbix, Nagios, ELK) monitoreando servidores? Si lo
  hay, el contrato debería ajustarse a lo que ese sistema ingiera mejor.
- **Retención de los logs de texto**: hoy 30 días. Con los eventos guardando la historia, 30 días
  de detalle puede bastar; si no, hay que decidir cuánto.
