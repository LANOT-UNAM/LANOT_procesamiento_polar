# Plan de orquestación

**Escrito el 2026-08-14. IMPLEMENTADO el 2026-08-15.** Se conserva como registro del
diseño; lo que corre está en `scripts/procesar_pasada.sh`, `scripts/barrer_pendientes.sh` y
`scripts/recibe.sh`. Cuatro cosas salieron distintas de como se planearon, y están anotadas
donde corresponde con el prefijo **AL IMPLEMENTAR**.

Cómo encadenar los once `run_*.sh` en una cadena automática por pasada. Las decisiones de
diseño de este documento ya están acordadas; lo que falta es escribirlo. El estado general de
la migración está en `estado_y_pendientes.md`.

---

## Por qué

Los once eslabones ya corren con datos reales, pero **el encadenamiento hoy es un humano**:
ningún `run_*.sh` invoca a otro, y las dependencias solo existen como mensajes de error
dirigidos al operador (`run_cryo_edr.sh:272`, `run_lsr_edr.sh:283`, `run_omps_edr.sh:70-72`).
Falta la pieza que convierta eso en cadena automática al llegar un RAW de la antena.

Tres hallazgos del análisis del código que definen el diseño:

1. **El disparo ya existe.** El software de la antena llama a `scripts/recibe.sh` con la ruta
   del RAW y este enruta por regex sobre el basename (`recibe.sh:70,87,101`): `chain[26]` a la
   cadena moderna, `chain4`/`chain5` a los legacy por `ssh`. No hay que inventar inotify ni
   cron de disparo — solo cambiar a qué apunta la rama moderna.
2. **Solo 2 de 11 aceptan que se les diga qué procesar.** `run_rt_stps.sh:149-156` y
   `run_sdr.sh:202-208` toman un archivo posicional; los otros nueve siempre agarran el ancla
   más reciente por mtime (`GMTCO*` en siete, `GITCO*` en flood `:139`, `GOTCO*` en omps
   `:138`). Sin poder nombrar la pasada, no hay forma de reprocesar una atrasada.
3. **No hay barrido de pendientes ni exclusión mutua.** Si el ancla más reciente ya tiene
   marcador, el script sale con 0 sin mirar las anteriores (`run_atmos_edr.sh:159-168`), así
   que una pasada que falle se queda sin procesar para siempre. Y no hay un solo `flock`,
   lockfile ni `pgrep` en `scripts/` ni en `referencia/`.

El resultado buscado: al llegar un RAW, la cadena corre sola de punta a punta, una pasada a la
vez, con reintento automático de lo que falle y un resumen legible por corrida.

## Decisiones tomadas

- **Argumento explícito de pasada** en los nueve scripts que no lo tienen. Sin argumento se
  comportan igual que hoy, así que el uso a mano no cambia.
- **Bash secuenciando el grafo**, con `sbatch` opcional más adelante; hoy ejecución directa.
- **Tres etapas simultáneas como máximo.** tahan tiene 64 CPU (2× Xeon Gold 6326, 32 núcleos
  físicos). Los hilos que ya pide cada script suman ~48 de 64 con tres a la vez; las cinco
  independientes a la vez pedirían ~72 y empezarían a pelear.
- **Un fallo no detiene la cadena**: se anota y las demás etapas siguen. LSR va a fallar en
  todas las pasadas nocturnas —no hay reflectancia de superficie sin sol— y eso no puede
  detener nada.
- **Candado global y barrido en cron**, para que la cadena se autorrepare.
- ~~**El orquestador se ejecuta desde el clon de git**, no desde una copia en
  `/home/lanotadm/bin`.~~ **AL IMPLEMENTAR: revertido.** El clon mezcla el árbol de trabajo
  con producción —un `git pull` a media pasada cambia el script en ejecución— así que la
  cadena se instala en `/opt/lanot/polares` con `scripts/instalar.sh`. `~lanotadm/bin`
  tampoco: ata la cadena a una cuenta de usuario.
- **`procesar_cadena_completa.sh` se borra** al entrar el nuevo: su papel declarado era ser la
  plantilla para reunificar la cadena, y eso es justo lo que hace el orquestador.

---

## 1. Argumento de pasada en los nueve `run_*.sh`

> **AL IMPLEMENTAR — esto ya estaba hecho.** Entre que se escribió el plan y que se fue a
> implementar, los nueve ganaron `-p`/`--pasada`, y mejor de como se diseñó aquí: en vez de
> exigir la clave exacta, resuelven el valor contra `claves_disponibles()`, o sea que aceptan
> la clave completa o cualquier trozo que la identifique. Eso resolvió solo el caso de OMPS.

Mismo cambio en los nueve, siempre en el mismo sitio: donde hoy se busca el ancla más
reciente. La clave es la que ya usan internamente, `sat_dfecha_borbita`
(`j01_d20260811_b45236`), y la produce `clave_de_pasada()`, que ya existe en todos.

```bash
if [ -n "$CLAVE_PEDIDA" ]; then
    CLAVE="$CLAVE_PEDIDA"
    IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"
    # Cada script resuelve su propia ancla: GMTCO en siete, GITCO en flood, GOTCO en omps
    ANCLA=$(ls -1 "$HOST_SDR_IN"/GMTCO_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 2>/dev/null | sort | head -1)
    [ -n "$ANCLA" ] || { echo "ERROR: no hay SDR de la pasada $CLAVE en $HOST_SDR_IN" >&2; exit 1; }
else
    …lo de hoy, sin tocar…
fi
```

El ancla se sigue necesitando aunque venga la clave: `run_lsr_edr.sh:96-112`,
`run_cryo_edr.sh:94-110` y `run_polar2grid_edr.sh:191-226` derivan de su nombre la ventana
temporal con la que emparejan los productos de Level 2.

**Clave parcial para OMPS.** El mismo sobrevuelo lleva órbita distinta según el instrumento
—`b45236` en los SDR de VIIRS y `b45237` en los de OMPS (`CLAUDE.md`)—, así que la clave de
VIIRS no sirve para OMPS. Regla uniforme: si la clave trae tres campos el emparejamiento es
exacto; si trae dos (`j01_d20260811`), la órbita se comodinea y gana la más reciente. Con eso
el orquestador le pasa a OMPS `sat_dfecha` y cada quien resuelve su órbita.

En el parseo de argumentos, los nueve rechazan hoy **cualquier** cosa no reconocida, incluido
un posicional. Hay que adoptar la forma que ya usan `run_rt_stps.sh:144-156` y
`run_sdr.sh:197-208`, que distinguen `-*` (opción desconocida, error) de un posicional.

## 2. `scripts/procesar_pasada.sh` — el orquestador

Nuevo. Un archivo RAW como argumento, o `--clave <clave>` para reprocesar una pasada ya
ingerida. `--force` se propaga a todas las etapas. `--dry-run` imprime el grafo y los comandos
sin ejecutar nada, que es lo que permite probarlo fuera de tahan.

**Candado.** `flock -n` sobre `/data/tmp/lanot_polares.lock`. Si está tomado, la pasada queda
pendiente y el barrido la recoge. Es lo que hace que "una pasada a la vez" sea cierto y
elimina de raíz la ambigüedad de la autoselección.

> **AL IMPLEMENTAR — sale con 75, no con 0.** Con salida 0 y sin marcador, "había otra pasada
> en curso" es indistinguible de "falló", y el barrido cuenta intentos: tres choques de
> candado bastarían para marcar `.fallido` un RAW perfectamente bueno. 75 es `EX_TEMPFAIL`.
> El barrido además toma su propio candado, para no solaparse consigo mismo.

**Grafo.** Barreras entre niveles, hasta tres etapas simultáneas dentro de cada uno:

```
RT-STPS(raw)
  └─ nivel 1:  SDR viirs · SDR atms · SDR cris · SDR omps_nm · SDR omps_np
       ├─ nivel 2:  ATMOS · ACSPO · FIRE · FLOOD · P2G_L1        (desde SDR viirs)
       │              └─ nivel 3:  LSR · CRYO                    (desde ATMOS)
       │                   └─ nivel 4:  P2G_EDR                  (ATMOS + LSR + ACSPO)
       └─ OMPS                                                   (desde SDR omps)
```

> **AL IMPLEMENTAR — al nivel 4 le faltaban dos entradas.** `run_polar2grid_edr.sh` también
> consume FIRE y FLOOD (`P2G_FIRE_IN`, `P2G_FLOOD_TIF`). Y OMPS entró al nivel 2, que es
> donde encaja sin cambiar nada.

Camino crítico ≈ RT-STPS + SDR + 13 min. En serie serían ~26 min después del SDR.

La clave de la pasada sale del GMTCO más reciente en `level1/viirs` **después** de que
`run_sdr.sh --sensor viirs` termine; de ahí en adelante se le pasa explícita a todas las
etapas. Los RDR que produjo RT-STPS se descubren en `level0` para saber qué sensores lanzar.

> **AL IMPLEMENTAR — a los RDR hay que NOMBRARLOS, no autoseleccionarlos.** `run_sdr.sh`
> filtra por edad mínima de 1 minuto al autoseleccionar, así que recién salido de RT-STPS no
> vería nada y saldría en 0 sin hacer nada: la cadena se cortaría en silencio. El argumento
> posicional se salta ese filtro. Y hay que saltarse el `RNSCA` suelto, que es el spacecraft
> diary y no un sensor.

**Errores.** Cada etapa se invoca con `|| codigo=$?` —la forma correcta bajo `set -euo
pipefail`, que ya usan los once (`run_acspo_edr.sh:226` y equivalentes)— y ninguna aborta a
las demás. Es lo mismo que hacen internamente `en_contenedor()` de los dos
`run_polar2grid_*.sh` (`run_polar2grid_l1.sh:299`, `run_polar2grid_edr.sh:483`).

**Resumen final.** Tabla por etapa: resultado, duración y cuántos productos. Los conteos **no
requieren tocar los scripts**: ya están dentro del marcador `.done` que cada etapa escribe
(`run_atmos_edr.sh:307-315` y equivalentes). Eso resuelve de paso que los once devuelvan `0`
tanto en éxito como en "no había nada que hacer": el orquestador lo distingue leyendo el
marcador, no el código de salida.

## 3. `scripts/barrer_pendientes.sh` — el barrido

Nuevo, para cron cada 15 minutos. Lista los RAW de `$RTSTPS_INPUT_DIR` con más de
`RTSTPS_MIN_AGE_MIN` de antigüedad y sin marcador en `state/rt-stps`, y los pasa al orquestador
**en orden cronológico**. El candado hace el resto: si hay una pasada corriendo, el barrido
sale y vuelve a intentar en 15 minutos.

**Tope de reintentos**, para que un RAW corrupto no se reintente eternamente: un contador
`<raw>.intentos` junto al marcador; al tercer fallo escribe `<raw>.fallido` y deja de
intentarlo. El `.fallido` es visible y es lo que hay que revisar a mano.

## 4. `scripts/recibe.sh`

- `SCRIPT_MODERNO` apunta a `procesar_pasada.sh` **del clon**, resuelto con `SCRIPT_DIR` a
  partir de la ubicación del propio `recibe.sh`, no con una ruta fija.
- `mkdir -p "$LOG_DIR"`: hoy no existe y el primer `tee -a` de `:54` falla si el directorio no
  está creado.
- `< /dev/null` en los tres `nohup`. El `recibe.sh` de producción sí lo tiene
  (`referencia/recibe.sh:20-26`); el del repositorio lo perdió.
- Comillas en `${FILENAME}` dentro de la ruta de log de la rama `chain4` (`:92`), y capturar
  `$!` ahí como en las otras dos ramas.
- `TIMESTAMP` se congela en `:50` y se reutiliza hasta el mensaje final de `:119`: recalcularlo
  donde se use.

Las ramas `chain4` y `chain5` (NOAA-15/18/19 y METOP) no se tocan: son legacy y salen de esta
cadena.

**Paso manual, una vez**: la antena invoca una ruta fija. Hay que apuntarla al clon o dejar
`/home/lanotadm/bin/recibe.sh` como enlace simbólico. Es lo único que no queda en el repo.

## 5. Limpieza que entra con el cambio  ✅ hecha

- **Borrar `scripts/procesar_cadena_completa.sh`.** Además de estar desactualizado —apunta a
  `cspp_nucaps_v1.0.sif`, que nunca existió, y al árbol `/data/products/*`— tiene siete
  comprobaciones `if [ $? -ne 0 ]` que bajo su propio `set -euo pipefail` (`:27`) son código
  muerto: `:167`, `:223`, `:258`, `:292`, `:324`, `:382`, `:438`.
- **`CLAUDE.md:111` afirma algo falso**: dice que "los `run_*.sh` de EDR no usan `set -e`". Los
  once lo usan; lo que los salva es la forma `… || EXIT_CODE=$?`. Corregirlo, porque es justo
  la trampa que la nota pretende evitar.
- `CLAUDE.md` y `estado_y_pendientes.md`: documentar la cadena nueva, retirar las notas que
  declaran `procesar_cadena_completa.sh` como plantilla a conservar, y actualizar la sección de
  tareas programadas con el barrido.

## Archivos  ✅ todos escritos

**Nuevos**: `scripts/procesar_pasada.sh`, `scripts/barrer_pendientes.sh`.
**Modificados**: `scripts/recibe.sh`; los nueve `run_*.sh` sin posicional (`atmos`, `lsr`,
`cryo`, `acspo`, `active_fire`, `flood`, `omps`, `polar2grid_l1`, `polar2grid_edr`);
`CLAUDE.md`; `docs/estado_y_pendientes.md`.
**Borrado**: `scripts/procesar_cadena_completa.sh`.

## Verificación

> **AL IMPLEMENTAR.** Los pasos 1 a 3 se hicieron en bucéfalo con once eslabones simulados:
> los tres desenlaces del resumen (ok con conteos, "ya estaba", "fallo" siguiendo adelante),
> el paralelismo visible en los tiempos, el candado, el `RNSCA` suelto que no se lanza, la
> clave truncada de OMPS, el barrido en orden cronológico, el `.fallido` al tercer intento,
> la contención que no gasta intento, y `recibe.sh` a través del enlace simbólico. Los pasos
> 4 a 7, los de tahan, siguen pendientes. Ojo con el punto 4: los conteos de Level 1 son
> **59 y 3 en pasada diurna, 43 y 1 en nocturna** — de noche faltan las 14 bandas
> reflectivas y los 2 RGB.


1. `bash -n` sobre todo lo tocado.
2. **En la máquina de desarrollo**: `procesar_pasada.sh --dry-run` sobre un nombre de RAW
   inventado, para revisar el grafo, el orden y los comandos exactos sin ejecutar nada.
3. **En la máquina de desarrollo**: el argumento de pasada de los nueve, con un `apptainer`
   simulado en el `PATH` y los `*_SDR_IN` apuntando a un directorio de prueba con nombres de
   archivo fabricados. Es el mecanismo de override que los scripts ya traen para esto.
4. **En tahan, sin candado de por medio**: `procesar_pasada.sh --clave j01_d20260811_b45236
   --force` sobre la pasada que ya conocemos, y comparar contra los conteos registrados
   (22 GeoTIFF y 9 vistas de Level 2; 59 y 3 de Level 1).
5. **En tahan, la cadena entera**: `procesar_pasada.sh <raw>` sobre un RAW ya procesado, con
   `--force`, y verificar que el resumen final coincide con los marcadores `.done`.
6. **El candado**: lanzar dos orquestadores a la vez y confirmar que el segundo sale con 0 sin
   hacer nada.
7. **El barrido**: borrar el marcador de un RAW viejo, correr `barrer_pendientes.sh` y ver que
   lo recoge; repetir tres veces con una etapa forzada a fallar para ver que aparece el
   `.fallido`.

## Fuera de este plan

- **Slurm**: el orquestador queda escrito para que la función que lanza una etapa pueda emitir
  `sbatch --wait` cuando el clúster exista, sin rehacer el grafo. Hoy ejecuta directo.
- **Normalizar los `run_*.sh` entre sí.** Hay bastante deriva acumulada: seis tienen cabecera
  `#SBATCH` y cinco no, con recursos dispares (8/16/2 CPU) y rutas de log de Slurm relativas en
  cinco y absoluta en omps; `active_fire` y `omps` piden CPU que nunca le pasan al driver;
  `run_polar2grid_edr.sh:497` no fija hilos y `run_polar2grid_l1.sh:310` sí; `clave_de_pasada()`
  está duplicada en nueve archivos. Nada de eso bloquea la cadena, pero conviene una pasada de
  limpieza después.
- **Guarda de edad mínima en los nueve**: solo `rt_stps:122` y `sdr:167` tienen `-mmin +N`, así
  que en teoría una etapa podría tomar una pasada cuyos SDR aún se escriben. Con el candado y
  el encadenamiento deja de ser alcanzable en la práctica, pero sigue siendo cierto si alguien
  los corre a mano.
