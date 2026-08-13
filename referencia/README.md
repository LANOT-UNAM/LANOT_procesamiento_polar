# Referencia

Código que **no se ejecuta desde este repositorio**. Está aquí para consultarlo, no para
correrlo. Lo que sí se usa vive en `scripts/`.

| Archivo | Qué es | Por qué se conserva |
|---|---|---|
| `cspp.sh` | Corre **hoy en producción**: el orquestador RAW → Level 1 de los cuatro sensores, que dispara el resto por `ssh` al otro servidor. | Es el inventario de lo que la cadena nueva debe cubrir; hoy le falta **OMPS**. Su manejo de estado no se copia: escribe el marcador *antes* de procesar (línea 79), así que un fallo a media pasada la da por hecha para siempre. |
| `cspp_1_ptog.sh` | Corre **hoy en producción** en el servidor viejo: Level 1 → GeoTIFF, vistas DNB y RGB. | De aquí salieron las rejillas propias (`config/grid.yaml`). Ya está cubierto por `scripts/run_polar2grid_l1.sh`, que hace lo mismo con cuatro llamadas a Polar2Grid en vez de cinco: el DNB no necesita remuestrearse dos veces. Se retirará cuando el script nuevo corra con datos reales. |
| `recibe.sh` | El despachador del servidor viejo: recibe un RAW de la antena y lo enruta según la cadena. | Es la entrada de todo el sistema en producción. `chain2`/`chain6` van a `cspp.sh` (JPSS); `chain4`/`chain5`, a `noaa` y `metop2.sh`. |
| `noaa` | Procesamiento AAPP de los NOAA heredados: AMSU-A/B, HIRS, AVHRR y DCS. | Satélites que **no** pasan por esta cadena. Se conserva para saber qué más depende del mismo RAW. |
| `metop2.sh` | Procesamiento AAPP + metopizer de METOP: AMSU, MHS, HIRS, AVHRR e IASI. | Igual que el anterior; además es el punto de partida si algún día se migra la rama METOP, cuyo IASI sí alimentaría a HEAP. |
| `old_cspp_no_usar.sh` | La cadena monolítica anterior, en bare metal. | Documenta el flujo completo del sistema que se está sustituyendo, con todas sus rutas. |
| `test_render_fires.sh` | Prueba manual de renderizado de incendios con Polar2Grid. | Guarda dos detalles que costaron encontrar: Satpy no reconoce los nombres con `_cspp_dev`, y para Active Fire además hay que pasar `j01` a `J01`. Se retirará cuando `run_polar2grid_edr.sh` cubra los incendios. |

Estos archivos no se mantienen. Si alguno queda obsoleto del todo, se borra: el historial
de git lo conserva.
