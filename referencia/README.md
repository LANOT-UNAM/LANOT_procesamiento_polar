# Referencia

Código que **no se ejecuta desde este repositorio**. Está aquí para consultarlo, no para
correrlo. Lo que sí se usa vive en `scripts/`.

| Archivo | Qué es | Por qué se conserva |
|---|---|---|
| `cspp_1_ptog.sh` | Corre **hoy en producción** en el servidor viejo: Level 1 → GeoTIFF, vistas DNB y RGB. | Es la referencia de lo que la cadena nueva tiene que llegar a cubrir. De aquí salieron las rejillas propias (`config/grid.yaml`), y de aquí se ve que a la cadena nueva le falta el RGB (`true_color`/`false_color`). |
| `old_cspp_no_usar.sh` | La cadena monolítica anterior, en bare metal. | Documenta el flujo completo del sistema que se está sustituyendo, con todas sus rutas. |
| `test_render_fires.sh` | Prueba manual de renderizado de incendios con Polar2Grid. | Guarda dos detalles que costaron encontrar: Satpy no reconoce los nombres con `_cspp_dev`, y para Active Fire además hay que pasar `j01` a `J01`. Se retirará cuando `run_polar2grid_edr.sh` cubra los incendios. |

Estos archivos no se mantienen. Si alguno queda obsoleto del todo, se borra: el historial
de git lo conserva.
