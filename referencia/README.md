# Referencia

Código que **no se ejecuta desde este repositorio**. Está aquí para consultarlo, no para
correrlo. Lo que sí se usa vive en `scripts/`.

| Archivo | Qué es | Por qué se conserva |
|---|---|---|
| `cspp.sh` | Corre **hoy en producción**: el orquestador RAW → Level 1 de los cuatro sensores, que dispara el resto por `ssh` al otro servidor. | Es el inventario de lo que la cadena nueva debe cubrir; hoy le falta **OMPS**. Su manejo de estado no se copia: escribe el marcador *antes* de procesar (línea 79), así que un fallo a media pasada la da por hecha para siempre. |
| `cspp_7_clavrx.sh` | Corre **hoy en producción** en tsom03: Level 1 → CLAVR-x, de donde sale la vista de tipo de nube que la cadena nueva quiere sustituir con `JRR-CloudType`. | Igual que flood, **las vistas no salen de Polar2Grid**: las hace `ql_clavrx.sh`, el quicklook del propio bundle de CLAVR-x. Polar2Grid solo produce los GeoTIFF `float32` (misma rejilla que nosotros, `wgs84_geo_750m`, con `--grid-configs`). Su manejo de estado es el mismo antipatrón de `cspp.sh` —el marcador se escribe antes de procesar— y además **borra los `.h5` de entrada** al terminar. |
| `cspp_1_ptog.sh` | Corre **hoy en producción** en el servidor viejo: Level 1 → GeoTIFF, vistas DNB y RGB. | De aquí salieron las rejillas propias (`config/grid.yaml`). Ya está cubierto por `scripts/run_polar2grid_l1.sh`, que hace lo mismo con cuatro llamadas a Polar2Grid en vez de cinco: el DNB no necesita remuestrearse dos veces. Se retirará cuando el script nuevo corra con datos reales. |
| `recibe.sh` | El despachador del servidor viejo: recibe un RAW de la antena y lo enruta según la cadena. | Es la entrada de todo el sistema en producción. `chain2`/`chain6` van a `cspp.sh` (JPSS); `chain4`/`chain5`, a `noaa2` (en tsom03) y `metop2.sh`. |
| `noaa` | Procesamiento AAPP de los NOAA heredados: AMSU-A/B, HIRS, AVHRR y DCS. | Satélites que **no** pasan por esta cadena. Se conserva para saber qué más depende del mismo RAW. Es una versión anterior: la que `recibe.sh` invoca en tsom03 es `noaa2`, que sí toma el crudo como argumento. |
| `lspass.txt` | Lista de pasadas del passdisk de TeraScan (`lspass` en polaracq, 2026-09-15). | Es la evidencia de qué satélite es cada `chainN`: el número de pase del nombre del crudo es la columna `#`. Ver `docs/plan_operacion_datawork.md`. |
| `recepcion/watchpolar/watchpolar.sh` | Corre **hoy en producción** en polaracq: vigila el passdisk con `inotifywait` y, en cada `CLOSE_WRITE`, llama a `copypolar.sh`. | Es el arranque de toda la cadena, y el plan de operación lo conserva tal cual. Lo que cambia es `copypolar.sh`, que por eso no se versiona aquí. |
| `recepcion/watchpolar/keepruningwatch.sh` | Cron en polaracq que relanza `watchpolar.sh` si muere. | Desde que existe (junio de 2021), el monitor no ha estado caído más de 12 horas seguidas. |
| `metop2.sh` | Procesamiento AAPP + metopizer de METOP: AMSU, MHS, HIRS, AVHRR e IASI. | Igual que el anterior; además es el punto de partida si algún día se migra la rama METOP, cuyo IASI sí alimentaría a HEAP. |
| `old_cspp_no_usar.sh` | La cadena monolítica anterior, en bare metal. | Documenta el flujo completo del sistema que se está sustituyendo, con todas sus rutas. |
| `test_render_fires.sh` | Prueba manual de renderizado de incendios con Polar2Grid. | Guarda dos detalles que costaron encontrar: Satpy no reconoce los nombres con `_cspp_dev`, y para Active Fire además hay que pasar `j01` a `J01`. Se retirará cuando `run_polar2grid_edr.sh` cubra los incendios. |

Estos archivos no se mantienen. Si alguno queda obsoleto del todo, se borra: el historial
de git lo conserva.
