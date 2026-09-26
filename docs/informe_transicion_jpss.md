# Transición de la cadena polar JPSS al sistema nuevo

**LANOT-UNAM · Junta del 28 de septiembre de 2026 · Alejandro Aguilar Sierra**

## Propuesta

Apagar la rama JPSS del sistema viejo (`cspp.sh` en stratus) y dejar como única la cadena
nueva, que corre en tahan con contenedores. METOP sigue en el sistema viejo hasta migrarlo.

**Se pide a la junta:** aprobar la transición en cuanto se cumplan los cinco puntos del final,
decidir qué pasa con AFAI y el idioma de los rótulos de las imágenes (hoy en inglés), y avisar
a los usuarios del cambio de producto de nubes.

## Por qué

**Se puede mantener.** El sistema viejo depende de instalaciones hechas a mano en cada
servidor y de scripts que dan una pasada por procesada *antes* de procesarla: si algo falla a
media pasada, se pierde sin aviso. La cadena nueva empaqueta cada software de CSPP en una
imagen reproducible, con recetas versionadas en git. El mismo software corre igual en
cualquier servidor, que es la base para repartir el trabajo entre tahan, stratus y tsom03.

**Es más robusta.** Da una etapa por buena solo si produjo todo, reintenta lo que falla por
datos auxiliares tardíos y un barrido recoge las pasadas atrasadas. Opera sola desde el 23 de
septiembre: recepción, procesamiento y publicación en kawak.

**Produce más.**

| Producto | Viejo | Nuevo |
|---|---|---|
| NOAA-21 | no | sí, junto con NPP y NOAA-20 |
| RGB, DNB, SST, incendios, inundaciones, vegetación | sí | sí |
| Nubes | CLAVR-x, ya sin actualizaciones | CSPP ATMOS (algoritmo operativo de NOAA) |
| Sondeos NUCAPS y Skew-T en 14 estaciones del SMN | no (carpeta vacía desde 2022) | sí, NOAA-20 y NOAA-21 |
| Ozono total (OMPS) | no | sí |
| Lluvia, agua precipitable e hielo convectivo (ATMS) | no | sí, los tres satélites |
| Índice de algas flotantes (AFAI) | sí | no |
| Quicklooks por canal de ATMS, CrIS y OMPS | sí | no |

**Lo que se deja no se usa.** En los registros del servidor web del 1 de agosto de 2025 al 26
de septiembre de 2026, los quicklooks de ATMS, CrIS y OMPS recibieron unos 8 300 accesos. Casi
todos fueron de rastreadores y de un escáner de vulnerabilidades. Las personas abrieron **5
imágenes en catorce meses**, todas desde la UNAM o el LANOT. Lo útil de ATMS lo cubren ahora
la lluvia y el hielo convectivo.

## Lo que falta antes de apagar

1. **Varios días de operación sin intervención.** En curso desde el 23 de septiembre.
2. **Pasadas encimadas.** El barrido ya las recoge; falta verificarlo con un par real.
3. **AFAI.** Traerlo a la cadena nueva o dejarlo, por decisión explícita.
4. **Publicación completa.** Hoy kawak recibe de la nueva solo lo que la vieja no hace; al
   apagar se publica todo y la página muestra las secciones nuevas (sondeos, ozono, ATMS).
5. **Avisos de falla** cuando una etapa falla varias veces seguidas (monitoreo común con GOES).
