# Estado de la migración y pendientes

**Última actualización: 2026-08-14**

**Los once eslabones corren con datos reales.** La cadena nueva ya cubre lo que hace el
servidor viejo, RGB incluido, y desde el 2026-08-13 también **OMPS**, que era lo último
que faltaba. Del ozono queda pendiente solo la vista, que exige Polar2Grid 3.3
(pendiente 8).

Documento vivo. Sustituye en la práctica a `migracion_polares.md` y `README_SCRIPTS.md`,
que describen la primera fase de la migración y ya no reflejan cómo corre la cadena.

---

## Dónde quedó el 2026-08-15

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

## Tareas programadas

Qué debe quedar en el `crontab` de `lanotadm`. **Ninguna está confirmada como activa**:
falta cotejar contra un `crontab -l` en tahan.

| Tarea | Frecuencia | Por qué | Estado |
|---|---|---|---|
| `update_sdr_daily.sh` | diaria | LUTs de calibración y TLE/GFS de CSPP SDR. Sin esto, la calibración se degrada con los días. | Existe desde antes; **verificar si está en cron** |
| `update_atmos_ancillary.sh` | 4× al día (`17 2,8,14,20 * * *`) | CMCSST, GFS y mapa de nieve de ATMOS. El manual pide cuatro por las cuatro corridas del GFS. Incluye el podado a 14 días. | **Pendiente de montar** |
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
17 2,8,14,20 * * * /home/lanotadm/bin/update_atmos_ancillary.sh
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
- **OMPS** ya está cubierto (`run_omps_edr.sh`, 2026-08-13), pero su vista no: el lector
  de ozono llega hasta Polar2Grid 3.3 y tenemos la 3.2. Ver el pendiente 8.

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

### 4. HEAP (rama ATMS/CrIS)
El tarball está en `/opt/contenedores/CSPP_HEAP_V3.0.tar.gz` y el manual en
`docs/manuals/`. Antes hay que validar la rama que nunca se ha ejercitado:

```bash
scripts/run_sdr.sh --sensor atms
scripts/run_sdr.sh --sensor cris
```

HEAP descarga su propio ancillary dinámico (con `lftp`), así que repite el patrón de
ATMOS: caché propio, modo local y descargador en cron.

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

### 8. OMPS — probado el 2026-08-13; falta la vista
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

### 9. Recorte y encuadre de las vistas
En el `true_color` de la pasada de prueba, más de la mitad del cuadro es negro: la rejilla
dinámica cubre el rectángulo que envuelve un swath diagonal y el resto es relleno. Hoy
solo se recorta por abajo, con `--lat-south 11`.

`geotiff2view` acepta `--clip` con cuatro coordenadas o con el **nombre de una región**,
que resuelve contra `/usr/local/share/lanot/docs/recortes_coordenadas.csv` (ya viene en el
contenedor). Falta decidir qué región usar por producto — probablemente una para México y
otra más amplia para los productos oceánicos como la SST.

Pendiente menor del mismo tema: confirmar si el logo se está cortando en el borde
izquierdo o si el diseño es así. Se ve como "LAN" seguido de dos iconos.

### 10. El README está una generación atrás
Es la puerta de entrada del repositorio y describe la primera fase de la migración. Lo
concreto que hay que corregir:

- Dice que el orquestador es `procesar_cadena_completa.sh`, que **no está en uso**.
- El diagrama Mermaid muestra tres contenedores y termina en Polar2Grid **v3.1**; hoy son
  doce recetas, la cadena llega a Level 2 y las vistas salen de
  `polar2grid_v3.2-mapdrawer`.
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
