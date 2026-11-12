# Catálogo de productos de la cadena polar

> Generado desde `docs/catalogo_productos.tsv` con `scripts/generar_catalogo.py`. **No editar a mano**: los cambios van en el TSV.

Productos que el LANOT genera a partir de la recepción directa de los satélites polares Suomi-NPP, NOAA-20 y NOAA-21, de Level 1 en adelante. Todas las rutas son relativas a `/data/output/jpss/`.

- **Level 1 (SDR)**: radiancias calibradas y geolocalizadas, en la geometría del instrumento (swath), un archivo por gránulo o por pasada.
- **Level 2**: variables geofísicas calculadas con CSPP, también en swath.
- **GeoTIFF**: una selección de Level 1 y Level 2 remallada a una rejilla latitud-longitud fija (`config/grid.yaml`). Es **dato** (float32, sin realce), salvo donde se indica que es imagen.
- **Vista**: imagen decorada (JPG, o SVG en el Skew-T) para mirar, no para calcular. Solo llevan vista los productos que alguien mira.

Una **pasada** es el conjunto de gránulos de un satélite sin huecos de más de 20 min. En los nombres de GeoTIFF y vistas el satélite va como `npp`, `noaa20` o `noaa21`; en los de CSPP, como `npp`, `j01` o `j02` (o `n20`/`n21` en algunos Level 2).

## Cuánto se conserva

Lo que pasa de esta edad se borra solo: en `/data/output/jpss/` lo hace `scripts/limpiar.sh` una vez al día, con los días de `config/retencion.tsv`; en `/dataservice/jpss/`, que es de donde lo toman los FTP, `scripts/publicar_dataservice.sh`, a los 5 días. En `/dataservice` cada GeoTIFF va junto al dato del que sale, así que ahí la carpeta puede no ser la misma que aquí.

| Carpeta en `/data/output/jpss/` | Se conserva | En `/dataservice/jpss/` (5 días) |
|---|---|---|
| `level0/` | 14 días | no se publica |
| `level1/` | 7 días | `level1/atms`, `level1/cris`, `level1/omps`, `level1/viirs` |
| `level2/` | 14 días | `level2/acspo`, `level2/atmos`, `level2/cryo`, `level2/fires`, `level2/flood`, `level2/lsr`, `level2/mirs`, `level2/omps`, `level2/sounder` |
| `geotiff/` | 14 días | `geotiff/acspo` → `level2/acspo`, `geotiff/atmos` → `level2/atmos`, `geotiff/dnb` → `level1/viirs`, `geotiff/fire` → `level2/fires`, `geotiff/flood` → `level2/flood`, `geotiff/i_bands` → `level1/viirs`, `geotiff/lsr` → `level2/lsr`, `geotiff/m_bands` → `level1/viirs`, `geotiff/mirs` → `level2/mirs`, `geotiff/omps` → `level2/omps`, `geotiff/rgb` → `level1/viirs`, `geotiff/sounder` → `level2/sounder` |
| `vistas/` | 90 días | `vistas/acspo`, `vistas/atmos`, `vistas/dnb`, `vistas/fire`, `vistas/flood`, `vistas/lsr`, `vistas/mirs`, `vistas/omps`, `vistas/rgb`, `vistas/sounder`, `vistas/sounder/skewt` |

## Resumen

### Level 1: SDR

| Producto | Sensor | Satélites | Formato | Vista |
|---|---|---|---|---|
| [VIIRS SDR: radiancias calibradas y geolocalización](#l1-viirs-sdr) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | HDF5 | no |
| [ATMS SDR: microondas](#l1-atms-sdr) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | HDF5 | no |
| [CrIS SDR: infrarrojo hiperespectral](#l1-cris-sdr) | CrIS | NOAA-20, NOAA-21 | HDF5 | no |
| [OMPS Nadir Mapper SDR](#l1-omps-nm-sdr) | OMPS NM | Suomi-NPP, NOAA-20, NOAA-21 | HDF5 | no |
| [OMPS Nadir Profiler SDR](#l1-omps-np-sdr) | OMPS NP | Suomi-NPP, NOAA-20, NOAA-21 | HDF5 | no |

### Level 2: productos geofísicos

| Producto | Sensor | Satélites | Formato | Vista |
|---|---|---|---|---|
| [Atmósfera y nubes (VIIRS Enterprise)](#l2-atmos) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Reflectancia de superficie e índices de vegetación](#l2-lsr) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Criósfera: hielo marino](#l2-cryo) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Temperatura superficial del mar (ACSPO)](#l2-acspo) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4, GHRSST L2P | no |
| [Incendios activos](#l2-fires) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Incendios activos, banda M](#l2-fires-m) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Incendios activos: lista en texto](#l2-fires-txt) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | texto (CSV con comentarios #) | no |
| [Inundaciones](#l2-flood) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Microondas de ATMS (MiRS)](#l2-mirs) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |
| [Sondeos NUCAPS (CrIS + ATMS)](#l2-sounder) | CrIS+ATMS | NOAA-20, NOAA-21 | NetCDF4 | no |
| [Ozono (OMPS)](#l2-omps) | OMPS NM+NP | Suomi-NPP, NOAA-20, NOAA-21 | NetCDF4 | no |

### GeoTIFF en rejilla

| Producto | Sensor | Satélites | Formato | Vista |
|---|---|---|---|---|
| [Bandas M de VIIRS en rejilla](#gt-viirs-mbands) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Bandas I de VIIRS en rejilla](#gt-viirs-ibands) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Day/Night Band (dynamic)](#gt-viirs-dnb) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Color verdadero](#gt-viirs-true-color) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF 8 bits RGB | sí |
| [Falso color (tierra, nube, fuego)](#gt-viirs-false-color) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF 8 bits RGB | sí |
| [Espesor óptico de aerosoles a 550 nm](#gt-atmos-aod550) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura de tope de nube](#gt-atmos-cldtoptemp) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Altura de tope de nube](#gt-atmos-cldtophght) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Altura de base de nube](#gt-atmos-cldbasehght) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Presión de tope de nube](#gt-atmos-cldtoppres) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Fase de nube](#gt-atmos-cloudphase) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Tipo de nube](#gt-atmos-cloudtype) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Fracción total de nubosidad](#gt-atmos-cloudfraction) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Capas de nube](#gt-atmos-cloudlayer) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Reflectancia de superficie por banda](#gt-lsr-surfrefl) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Índice de vegetación NDVI](#gt-lsr-ndvi) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Índice de vegetación EVI](#gt-lsr-evi) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura superficial del mar](#gt-sst) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Incendios: confianza de la detección](#gt-fire-confidence) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Incendios: temperatura y potencia](#gt-fire-t4-power) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Incendios banda M: confianza, temperatura y potencia](#gt-fire-m) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |
| [Inundaciones](#gt-flood) | VIIRS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF 8 bits con paleta | sí |
| [Temperatura en 850 hPa](#gt-sounder-t850) | CrIS+ATMS | NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura en 700 hPa](#gt-sounder-t700) | CrIS+ATMS | NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura en 500 hPa](#gt-sounder-t500) | CrIS+ATMS | NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura de piel (sondeo)](#gt-sounder-skin) | CrIS+ATMS | NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Ozono total](#gt-omps-toz) | OMPS NM | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Tasa de lluvia (microondas)](#gt-mirs-rain) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Agua precipitable total (microondas)](#gt-mirs-tpw) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Temperatura de brillo a 165 GHz](#gt-mirs-btemp165) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | sí |
| [Agua líquida de nube, temperatura de piel y 88 GHz](#gt-mirs-otros) | ATMS | Suomi-NPP, NOAA-20, NOAA-21 | GeoTIFF float32 | no |

### Vistas sin GeoTIFF propio

| Producto | Sensor | Satélites | Formato | Vista |
|---|---|---|---|---|
| [Diagrama Skew-T en estaciones de radiosondeo](#vista-skewt) | CrIS+ATMS | NOAA-20, NOAA-21 | SVG | sí |

## Fichas

### Level 1: SDR

<a id="l1-viirs-sdr"></a>

#### VIIRS SDR: radiancias calibradas y geolocalización

`l1-viirs-sdr` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: SVM01–SVM16 (bandas M), SVI01–SVI05 (bandas I), SVDNB (Day/Night Band); geolocalización con corrección de terreno GMTCO, GITCO, GDNBO y sin ella GMODO, GIMGO; IVCDB (auxiliar del DNB)
- **Formato**: HDF5
- **Resolución**: swath: 750 m (M, DNB), 375 m (I)
- **Notas**: Gránulos de ~85 s. Un gránulo truncado deja sin calibrar a sus vecinos (±1): huecos horizontales normales en pasadas con dropout. Aquí sat va como npp|j01|j02.

<details><summary>Para operación</summary>

- Ruta: `level1/viirs/` · patrón `SV*_{sat}_d*_t*_e*_b*_c*_cspp_dev.h5, G*O_*.h5, IVCDB_*.h5`
- Origen: CSPP SDR 4.1.1 → run_sdr.sh --sensor viirs
- Depende de: RDR de RT-STPS

</details>

<a id="l1-atms-sdr"></a>

#### ATMS SDR: microondas

`l1-atms-sdr` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: SATMS (temperatura de brillo), TATMS (temperatura de antena), GATMO (geolocalización)
- **Formato**: HDF5
- **Resolución**: swath: 16 km en nadir a >50 km en la orilla
- **Notas**: Puede salir agregado por pasada o por gránulo según la corrida: no suponer que un archivo cubre la pasada entera.

<details><summary>Para operación</summary>

- Ruta: `level1/atms/` · patrón `SATMS_*, TATMS_*, GATMO_*.h5`
- Origen: CSPP SDR 4.1.1 → run_sdr.sh --sensor atms
- Depende de: RDR de RT-STPS

</details>

<a id="l1-cris-sdr"></a>

#### CrIS SDR: infrarrojo hiperespectral

`l1-cris-sdr` · CrIS · NOAA-20, NOAA-21

- **Contenido**: SCRIF (radiancias, resolución espectral completa), GCRSO (geolocalización)
- **Formato**: HDF5
- **Resolución**: swath: FOR de ~50 km (9 FOV de 14 km)
- **Notas**: Calibrar un gránulo requiere ±4 vecinos. Mismo aviso que ATMS sobre la agregación.

<details><summary>Para operación</summary>

- Ruta: `level1/cris/` · patrón `SCRIF_*, GCRSO_*.h5`
- Origen: CSPP SDR 4.1.1 → run_sdr.sh --sensor cris
- Depende de: RDR de RT-STPS

</details>

<a id="l1-omps-nm-sdr"></a>

#### OMPS Nadir Mapper SDR

`l1-omps-nm-sdr` · OMPS NM · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: SOMTC (radiancias UV), GOTCO (geolocalización)
- **Formato**: HDF5
- **Resolución**: swath: ~50 km
- **Notas**: Comparte directorio con el Nadir Profiler.

<details><summary>Para operación</summary>

- Ruta: `level1/omps/` · patrón `SOMTC_*, GOTCO_*.h5`
- Origen: CSPP SDR 4.1.1 → run_sdr.sh --sensor omps_nm
- Depende de: RDR de RT-STPS

</details>

<a id="l1-omps-np-sdr"></a>

#### OMPS Nadir Profiler SDR

`l1-omps-np-sdr` · OMPS NP · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: SOMPS (radiancias UV), GONPO (geolocalización)
- **Formato**: HDF5
- **Resolución**: swath: ~250 km
- **Notas**: Se procesa en llamada separada del Nadir Mapper (manual CSPP SDR).

<details><summary>Para operación</summary>

- Ruta: `level1/omps/` · patrón `SOMPS_*, GONPO_*.h5`
- Origen: CSPP SDR 4.1.1 → run_sdr.sh --sensor omps_np
- Depende de: RDR de RT-STPS

</details>

### Level 2: productos geofísicos

<a id="l2-atmos"></a>

#### Atmósfera y nubes (VIIRS Enterprise)

`l2-atmos` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: JRR-CloudMask (CloudMask, CloudProbability, máscaras de humo, polvo y fuego); JRR-CloudHeight (CldTopTemp [K], CldTopPres [hPa], CldTopHght [m], CldTopEmss); JRR-CloudBase (CldBaseHght [m], CldBasePres [hPa]); JRR-CloudPhase (CloudPhase, CloudType, categóricos); JRR-CloudCoverLayers (Total_Cloud_Fraction [1], CloudLayer, Layer_Frac [%]); JRR-CloudDCOMP y JRR-CloudNCOMP, microfísica diurna y nocturna (CloudMicroEffRad [µm], CloudMicroIWP y CloudMicroLWP [g/m²], CloudMicroVisOD); JRR-AOD (AOD550 [1], AOD_channel, AngsExp1/2); JRR-ADP (banderas de humo, polvo y ceniza, SAAI, DSDI); JRR-VolcanicAsh (AshTopHeight [m], AshMassLoading [t/km²], AshConfidence). Más NWP_GFS-INTP y NWP_GFS-GRID: el GFS interpolado a cada gránulo, que es entrada, no producto
- **Formato**: NetCDF4
- **Resolución**: swath 750 m
- **Notas**: Un archivo por gránulo y producto. Reprocesar agrega versiones (campo _c del nombre): usar la más reciente por gránulo. Aquí sat va como npp|j01|n21.

<details><summary>Para operación</summary>

- Ruta: `level2/atmos/` · patrón `JRR-<producto>_v3r2_{sat}_s*_e*_c*.nc (CloudCoverLayers es v2r0); NOAA20_VIIRS_750M_*_NWP_GFS-*.nc`
- Origen: CSPP ATMOS 1.0 → run_atmos_edr.sh
- Depende de: l1-viirs-sdr + GFS

</details>

<a id="l2-lsr"></a>

#### Reflectancia de superficie e índices de vegetación

`l2-lsr` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: reflectancia de superficie I01–I03, M01–M05, M07, M08, M10, M11; NDVI, EVI
- **Formato**: NetCDF4
- **Resolución**: swath 750 m / 375 m
- **Notas**: Solo gránulos diurnos.

<details><summary>Para operación</summary>

- Ruta: `level2/lsr/` · patrón `SurfRefl_*.nc`
- Origen: CSPP LSR 2.0 → run_lsr_edr.sh
- Depende de: l1-viirs-sdr + l2-atmos

</details>

<a id="l2-cryo"></a>

#### Criósfera: hielo marino

`l2-cryo` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: JRR-IceAge (IceAge, categórico 1–8 de hielo nuevo a viejo; IceThickness [m]); JRR-IceConcentration (IceConc [%], IceSrfTemp [K]); con SummaryQC de calidad
- **Formato**: NetCDF4
- **Resolución**: swath 750 m
- **Notas**: Sin GeoTIFF ni vista: Polar2Grid 3.2 no tiene lector.

<details><summary>Para operación</summary>

- Ruta: `level2/cryo/` · patrón `JRR-IceAge_v3r2_{sat}_*.nc, JRR-IceConcentration_v3r3_{sat}_*.nc`
- Origen: CSPP Cryosphere 1.0 → run_cryo_edr.sh
- Depende de: l1-viirs-sdr + l2-atmos (CloudMask, CloudHeight)

</details>

<a id="l2-acspo"></a>

#### Temperatura superficial del mar (ACSPO)

`l2-acspo` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: sea_surface_temperature [K] (sub-skin), sses_bias y sses_standard_deviation [K], quality_level, l2p_flags, dt_analysis [K], wind_speed [m/s], sea_ice_fraction [1]
- **Formato**: NetCDF4, GHRSST L2P
- **Resolución**: swath 750 m
- **Notas**: Formato estándar de GHRSST: filtrar por quality_level (5 es el mejor).

<details><summary>Para operación</summary>

- Ruta: `level2/acspo/` · patrón `<AAAAMMDDhhmmss>-CSPP-L2P_GHRSST-SSTsubskin-VIIRS_<NPP|N20|N21>-ACSPO_V2.80-v02.0-fv01.0.nc`
- Origen: CSPP ACSPO 3.0 → run_acspo_edr.sh
- Depende de: l1-viirs-sdr + GFS/CMCSST

</details>

<a id="l2-fires"></a>

#### Incendios activos

`l2-fires` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: grupo Fire Pixels: una fila por incendio con FP_latitude, FP_longitude, FP_T4 [K], FP_power (FRP) [MW], FP_confidence, ángulos [°]; grupo Fire Mask: fire_mask en la malla de 375 m
- **Formato**: NetCDF4
- **Resolución**: puntos, 375 m
- **Notas**: NetCDF con grupos. Aquí sat va como npp|j01|j02. Desde el 2026-10-23 los logs del driver ya no quedan en este directorio.

<details><summary>Para operación</summary>

- Ruta: `level2/fires/` · patrón `AFIMG_{sat}_d*_t*_e*_b*_c*.nc`
- Origen: CSPP Active Fire 2.1 → run_active_fire_edr.sh
- Depende de: l1-viirs-sdr (bandas I)

</details>

<a id="l2-fires-m"></a>

#### Incendios activos, banda M

`l2-fires-m` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: grupo Fire Pixels: una fila por incendio con FP_latitude, FP_longitude, FP_T13 [K], FP_power (FRP) [MW], FP_confidence [%, 0-100]
- **Formato**: NetCDF4
- **Resolución**: puntos, 750 m
- **Notas**: Desde el 2026-10-23. Misma familia que l2-fires a 750 m; la confianza es porcentaje, no categoría.

<details><summary>Para operación</summary>

- Ruta: `level2/fires/` · patrón `AFMOD_{sat}_d*_t*_e*_b*_c*.nc`
- Origen: CSPP Active Fire 2.1 (-M) → run_active_fire_edr.sh
- Depende de: l1-viirs-sdr (bandas M)

</details>

<a id="l2-fires-txt"></a>

#### Incendios activos: lista en texto

`l2-fires-txt` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: una línea por incendio: latitud y longitud [°], T4 [K], tamaño del pixel a lo largo y ancho del barrido [km], confianza (7 baja, 8 nominal, 9 alta), FRP [MW]
- **Formato**: texto (CSV con comentarios #)
- **Resolución**: puntos, 375 m
- **Notas**: El formato más fácil de usar para quien solo quiere los puntos de calor.

<details><summary>Para operación</summary>

- Ruta: `level2/fires/` · patrón `AFIMG_{sat}_d*_t*_e*_b*_c*_cspp_dev.txt`
- Origen: CSPP Active Fire 2.1 → run_active_fire_edr.sh
- Depende de: l1-viirs-sdr (bandas I)

</details>

<a id="l2-flood"></a>

#### Inundaciones

`l2-flood` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: WaterDetection (clases de agua, nube, nieve, sin dato)
- **Formato**: NetCDF4
- **Resolución**: swath 375 m
- **Notas**: Solo gránulos diurnos: una pasada nocturna termina bien y sin productos. Aquí sat va como npp|n20|n21.

<details><summary>Para operación</summary>

- Ruta: `level2/flood/` · patrón `VIIRS-Flood_v2r0_{sat}_s*_e*_c*.nc`
- Origen: CSPP Flood 2.0 → run_flood_edr.sh
- Depende de: l1-viirs-sdr (bandas I)

</details>

<a id="l2-mirs"></a>

#### Microondas de ATMS (MiRS)

`l2-mirs` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: IMG: RR tasa de lluvia [mm/h], TPW agua precipitable [mm], CLW agua líquida de nube [mm], TSkin temperatura de piel [K], BT 22 canales [K] con corrección de limbo, emisividad, hielo marino, nieve; SND: perfiles de temperatura y humedad
- **Formato**: NetCDF4
- **Resolución**: swath: 16–50 km
- **Notas**: Un par IMG/SND por pasada. Aquí sat va como npp|n20|n21.

<details><summary>Para operación</summary>

- Ruta: `level2/mirs/` · patrón `NPR-MIRS-IMG_v11r9_{sat}_*.nc, NPR-MIRS-SND_v11r9_{sat}_*.nc`
- Origen: CSPP MiRS 4.0 → run_mirs_edr.sh
- Depende de: l1-atms-sdr

</details>

<a id="l2-sounder"></a>

#### Sondeos NUCAPS (CrIS + ATMS)

`l2-sounder` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: NUCAPS-EDR: perfiles de temperatura, humedad, ozono y gases traza en 100 niveles, CAPE, CIN, LI; NUCAPS-CCR y NUCAPS-CCR-AR: radiancias de CrIS limpiadas de nube; NUCAPS-OLR: onda larga saliente
- **Formato**: NetCDF4
- **Resolución**: FOR de CrIS, ~50 km
- **Notas**: Sin NPP: HEAP 3.0 retiró su soporte. NUCAPS-ALL-HR también cae aquí pero es intermedio, no producto.

<details><summary>Para operación</summary>

- Ruta: `level2/sounder/` · patrón `NUCAPS-{EDR,CCR,CCR-AR,OLR}_v3r2_{sat}_*.nc`
- Origen: CSPP HEAP 3.0 → run_heap_edr.sh
- Depende de: l1-cris-sdr + l1-atms-sdr + GFS

</details>

<a id="l2-omps"></a>

#### Ozono (OMPS)

`l2-omps` · OMPS NM+NP · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: V8TOZ-EDR: columna total de ozono [DU]; V8PRO-EDR: perfil de ozono en 21 capas
- **Formato**: NetCDF4
- **Resolución**: swath ~50 km (TOZ), ~250 km (PRO)
- **Notas**: Solo de día. Sin Profiler sale V8TOZ y no V8PRO.

<details><summary>Para operación</summary>

- Ruta: `level2/omps/` · patrón `V8TOZ-EDR_*.nc, V8PRO-EDR_*.nc`
- Origen: CSPP OMPS EDR 1.0 → run_omps_edr.sh
- Depende de: l1-omps-nm-sdr (+ l1-omps-np-sdr para V8PRO)

</details>

### GeoTIFF en rejilla

<a id="gt-viirs-mbands"></a>

#### Bandas M de VIIRS en rejilla

`gt-viirs-mbands` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: M01–M11 reflectancia [%], M12–M16 temperatura de brillo [K]; radiancias (m01_rad…m16_rad); ángulos solar y satelital [°]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Dato, sin vista.

<details><summary>Para operación</summary>

- Ruta: `geotiff/m_bands/` · patrón `{sat}_viirs_m[0-9][0-9]_*_wgs84_geo_750m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_l1.sh
- Depende de: l1-viirs-sdr

</details>

<a id="gt-viirs-ibands"></a>

#### Bandas I de VIIRS en rejilla

`gt-viirs-ibands` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: I01–I03 reflectancia [%], I04–I05 temperatura de brillo [K]; radiancias (i01_rad…i05_rad); ángulos [°]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_375m
- **Notas**: Dato, sin vista.

<details><summary>Para operación</summary>

- Ruta: `geotiff/i_bands/` · patrón `{sat}_viirs_i[0-9][0-9]_*_wgs84_geo_375m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_l1.sh
- Depende de: l1-viirs-sdr

</details>

<a id="gt-viirs-dnb"></a>

#### Day/Night Band (dynamic)

`gt-viirs-dnb` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: dynamic_dnb, adimensional y no acotado a 0–1 (una pasada de NOAA-20 dio 0 a 37 con media 0.34); ángulos solar, satelital y lunar [°]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: La vista estira por percentiles. Los ángulos no llevan vista. Los adaptive/histogram/hncc_dnb de NOAA-20 que hay en tahan son de corridas viejas: ya no se producen.

<details><summary>Para operación</summary>

- Ruta: `geotiff/dnb/` · patrón `{sat}_viirs_dynamic_dnb_*_wgs84_geo_750m.tif`
- Vista: `vistas/dnb/` con `mapdrawer`
- Origen: Polar2Grid 3.2 → run_polar2grid_l1.sh
- Depende de: l1-viirs-sdr
- Polar2Grid `-p`: `dynamic_dnb`

</details>

<a id="gt-viirs-true-color"></a>

#### Color verdadero

`gt-viirs-true-color` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: compuesto M03/M04/M05 con corrección de Rayleigh y afilado con I01
- **Formato**: GeoTIFF 8 bits RGB
- **Resolución**: wgs84_geo_750m
- **Notas**: Solo de día. Es imagen, no dato.

<details><summary>Para operación</summary>

- Ruta: `geotiff/rgb/` · patrón `{sat}_viirs_true_color_*_wgs84_geo_750m.tif`
- Vista: `vistas/rgb/` con `mapdrawer`
- Origen: Polar2Grid 3.2 → run_polar2grid_l1.sh
- Depende de: l1-viirs-sdr
- Polar2Grid `-p`: `true_color`

</details>

<a id="gt-viirs-false-color"></a>

#### Falso color (tierra, nube, fuego)

`gt-viirs-false-color` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: compuesto M11/M07/M05
- **Formato**: GeoTIFF 8 bits RGB
- **Resolución**: wgs84_geo_750m
- **Notas**: Solo de día. Es imagen, no dato.

<details><summary>Para operación</summary>

- Ruta: `geotiff/rgb/` · patrón `{sat}_viirs_false_color_*_wgs84_geo_750m.tif`
- Vista: `vistas/rgb/` con `mapdrawer`
- Origen: Polar2Grid 3.2 → run_polar2grid_l1.sh
- Depende de: l1-viirs-sdr
- Polar2Grid `-p`: `false_color`

</details>

<a id="gt-atmos-aod550"></a>

#### Espesor óptico de aerosoles a 550 nm

`gt-atmos-aod550` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: AOD550 [1]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Solo de día.

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_AOD550_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `aod550.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `AOD550`

</details>

<a id="gt-atmos-cldtoptemp"></a>

#### Temperatura de tope de nube

`gt-atmos-cldtoptemp` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CldTopTemp [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CldTopTemp_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `atmosrainbow.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CldTopTemp`

</details>

<a id="gt-atmos-cldtophght"></a>

#### Altura de tope de nube

`gt-atmos-cldtophght` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CldTopHght [m]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CldTopHght_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `cld_height_acha.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CldTopHght`

</details>

<a id="gt-atmos-cldbasehght"></a>

#### Altura de base de nube

`gt-atmos-cldbasehght` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CldBaseHght [m]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CldBaseHght_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `cld_height_acha.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CldBaseHght`

</details>

<a id="gt-atmos-cldtoppres"></a>

#### Presión de tope de nube

`gt-atmos-cldtoppres` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CldTopPres [hPa]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CldTopPres_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `cld_top_press.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CldTopPres`

</details>

<a id="gt-atmos-cloudphase"></a>

#### Fase de nube

`gt-atmos-cloudphase` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CloudPhase, categórico (ATBD de NOAA, Tabla 31)
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CloudPhase_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `phase.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CloudPhase`

</details>

<a id="gt-atmos-cloudtype"></a>

#### Tipo de nube

`gt-atmos-cloudtype` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CloudType, categórico 0–8 (ATBD de NOAA, Tabla 30)
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CloudType_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `cloud_type_jrr.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CloudType`

</details>

<a id="gt-atmos-cloudfraction"></a>

#### Fracción total de nubosidad

`gt-atmos-cloudfraction` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: Total_Cloud_Fraction [1]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_Total_Cloud_Fraction_*_wgs84_geo_750m.tif`
- Vista: `vistas/atmos/` con `cloud_fraction.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `Total_Cloud_Fraction`

</details>

<a id="gt-atmos-cloudlayer"></a>

#### Capas de nube

`gt-atmos-cloudlayer` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: CloudLayer, máscara de bits (una capa por bit, 0–62)
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Sin vista a propósito: los valores son combinaciones de bits, no una escala.

<details><summary>Para operación</summary>

- Ruta: `geotiff/atmos/` · patrón `{sat}_viirs_CloudLayer_*_wgs84_geo_750m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-atmos
- Polar2Grid `-p`: `CloudLayer`

</details>

<a id="gt-lsr-surfrefl"></a>

#### Reflectancia de superficie por banda

`gt-lsr-surfrefl` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: surf_refl I01–I03, M01–M05, M07, M08, M10, M11 [1] (fracción, como en el NetCDF; Satpy la daría en %, y config/satpy_viirs_edr.yaml lo evita. En % hasta el 2026-11-12)
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Dato, sin vista.

<details><summary>Para operación</summary>

- Ruta: `geotiff/lsr/` · patrón `{sat}_viirs_surf_refl_*_wgs84_geo_750m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-lsr
- Polar2Grid `-p`: `surf_refl_i01 surf_refl_i02 surf_refl_i03 surf_refl_m01 surf_refl_m02 surf_refl_m03 surf_refl_m04 surf_refl_m05 surf_refl_m07 surf_refl_m08 surf_refl_m10 surf_refl_m11`

</details>

<a id="gt-lsr-ndvi"></a>

#### Índice de vegetación NDVI

`gt-lsr-ndvi` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: NDVI [1]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Solo de día.

<details><summary>Para operación</summary>

- Ruta: `geotiff/lsr/` · patrón `{sat}_viirs_NDVI_*_wgs84_geo_750m.tif`
- Vista: `vistas/lsr/` con `ndvi.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-lsr
- Polar2Grid `-p`: `NDVI`

</details>

<a id="gt-lsr-evi"></a>

#### Índice de vegetación EVI

`gt-lsr-evi` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: EVI [1]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Solo de día. Puede salir vacío en una pasada; entonces no hay vista.

<details><summary>Para operación</summary>

- Ruta: `geotiff/lsr/` · patrón `{sat}_viirs_EVI_*_wgs84_geo_750m.tif`
- Vista: `vistas/lsr/` con `evi.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-lsr
- Polar2Grid `-p`: `EVI`

</details>

<a id="gt-sst"></a>

#### Temperatura superficial del mar

`gt-sst` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: sst [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m

<details><summary>Para operación</summary>

- Ruta: `geotiff/acspo/` · patrón `{sat}_viirs_sst_*_wgs84_geo_750m.tif`
- Vista: `vistas/acspo/` con `sst.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-acspo
- Polar2Grid `-p`: `sst`

</details>

<a id="gt-fire-confidence"></a>

#### Incendios: confianza de la detección

`gt-fire-confidence` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: confidence_cat, categórico (baja, nominal, alta)
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_375m
- **Notas**: Remallado por vecino más cercano.

<details><summary>Para operación</summary>

- Ruta: `geotiff/fire/` · patrón `{sat}_viirs_confidence_cat_*_wgs84_geo_375m.tif`
- Vista: `vistas/fire/` con `viirs_confidence_cat.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-fires
- Polar2Grid `-p`: `confidence_cat`

</details>

<a id="gt-fire-t4-power"></a>

#### Incendios: temperatura y potencia

`gt-fire-t4-power` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: T4 [K], power [MW]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_375m
- **Notas**: Dato, sin vista.

<details><summary>Para operación</summary>

- Ruta: `geotiff/fire/` · patrón `{sat}_viirs_{T4,power}_*_wgs84_geo_375m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-fires
- Polar2Grid `-p`: `T4 power`

</details>

<a id="gt-fire-m"></a>

#### Incendios banda M: confianza, temperatura y potencia

`gt-fire-m` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: confidence_pct [%], T13 [K], power [MW]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_750m
- **Notas**: Dato, sin vista. Remallado por vecino más cercano.

<details><summary>Para operación</summary>

- Ruta: `geotiff/fire/` · patrón `{sat}_viirs_{confidence_pct,T13,power}_*_wgs84_geo_750m.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-fires-m
- Polar2Grid `-p`: `confidence_pct T13 power`

</details>

<a id="gt-flood"></a>

#### Inundaciones

`gt-flood` · VIIRS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: WaterDetection, categórico
- **Formato**: GeoTIFF 8 bits con paleta
- **Resolución**: 375 m, EPSG:4326
- **Notas**: No sale de Polar2Grid sino del convertidor del propio CSPP, fusionado por pasada. Es imagen con colormap, no dato.

<details><summary>Para operación</summary>

- Ruta: `geotiff/flood/` · patrón `{sat}_viirs_flood_*.tif`
- Vista: `vistas/flood/` con `mapdrawer`
- Origen: flood2tif de CSPP Flood 2.0 → run_flood_edr.sh
- Depende de: l2-flood

</details>

<a id="gt-sounder-t850"></a>

#### Temperatura en 850 hPa

`gt-sounder-t850` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: Temperature_853mb [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: El nivel del archivo es el del producto (853/707/497 mb); se habla de 850/700/500 hPa. NOAA-20 sale como j01_atms-cris_… y no noaa20_ (nombre por corregir).

<details><summary>Para operación</summary>

- Ruta: `geotiff/sounder/` · patrón `{sat}_atms-cris_Temperature_853mb_*_wgs84_geo_5km.tif`
- Vista: `vistas/sounder/` con `nucaps_temp_850.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-sounder
- Polar2Grid `-p`: `Temperature_853mb`

</details>

<a id="gt-sounder-t700"></a>

#### Temperatura en 700 hPa

`gt-sounder-t700` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: Temperature_707mb [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: El nivel del archivo es el del producto (853/707/497 mb); se habla de 850/700/500 hPa. NOAA-20 sale como j01_atms-cris_… y no noaa20_ (nombre por corregir).

<details><summary>Para operación</summary>

- Ruta: `geotiff/sounder/` · patrón `{sat}_atms-cris_Temperature_707mb_*_wgs84_geo_5km.tif`
- Vista: `vistas/sounder/` con `nucaps_temp_700.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-sounder
- Polar2Grid `-p`: `Temperature_707mb`

</details>

<a id="gt-sounder-t500"></a>

#### Temperatura en 500 hPa

`gt-sounder-t500` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: Temperature_497mb [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: El nivel del archivo es el del producto (853/707/497 mb); se habla de 850/700/500 hPa. NOAA-20 sale como j01_atms-cris_… y no noaa20_ (nombre por corregir).

<details><summary>Para operación</summary>

- Ruta: `geotiff/sounder/` · patrón `{sat}_atms-cris_Temperature_497mb_*_wgs84_geo_5km.tif`
- Vista: `vistas/sounder/` con `nucaps_temp_500.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-sounder
- Polar2Grid `-p`: `Temperature_497mb`

</details>

<a id="gt-sounder-skin"></a>

#### Temperatura de piel (sondeo)

`gt-sounder-skin` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: Skin_Temperature [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**:  NOAA-20 sale como j01_atms-cris_… y no noaa20_ (nombre por corregir).

<details><summary>Para operación</summary>

- Ruta: `geotiff/sounder/` · patrón `{sat}_atms-cris_Skin_Temperature_*_wgs84_geo_5km.tif`
- Vista: `vistas/sounder/` con `nucaps_skin_temp.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-sounder
- Polar2Grid `-p`: `Skin_Temperature`

</details>

<a id="gt-omps-toz"></a>

#### Ozono total

`gt-omps-toz` · OMPS NM · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: ColumnAmountO3 [DU]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: Solo de día. Lo escribe un convertidor propio hasta que Polar2Grid 3.3 traiga lector.

<details><summary>Para operación</summary>

- Ruta: `geotiff/omps/` · patrón `{sat}_omps_ColumnAmountO3_*_wgs84_geo_5km.tif`
- Vista: `vistas/omps/` con `omps_toz.cpt`
- Origen: omps_a_geotiff.py → run_polar2grid_edr.sh
- Depende de: l2-omps

</details>

<a id="gt-mirs-rain"></a>

#### Tasa de lluvia (microondas)

`gt-mirs-rain` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: rain_rate [mm/h]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km

<details><summary>Para operación</summary>

- Ruta: `geotiff/mirs/` · patrón `{sat}_atms_rain_rate_*_wgs84_geo_5km.tif`
- Vista: `vistas/mirs/` con `mirs_rain_rate.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-mirs
- Polar2Grid `-p`: `rain_rate`

</details>

<a id="gt-mirs-tpw"></a>

#### Agua precipitable total (microondas)

`gt-mirs-tpw` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: tpw [mm]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km

<details><summary>Para operación</summary>

- Ruta: `geotiff/mirs/` · patrón `{sat}_atms_tpw_*_wgs84_geo_5km.tif`
- Vista: `vistas/mirs/` con `mirs_tpw.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-mirs
- Polar2Grid `-p`: `tpw`

</details>

<a id="gt-mirs-btemp165"></a>

#### Temperatura de brillo a 165 GHz

`gt-mirs-btemp165` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: btemp_165h [K], corregida de limbo
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: Resalta el hielo de la convección profunda.

<details><summary>Para operación</summary>

- Ruta: `geotiff/mirs/` · patrón `{sat}_atms_btemp_165h_*_wgs84_geo_5km.tif`
- Vista: `vistas/mirs/` con `mirs_btemp_165.cpt`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-mirs
- Polar2Grid `-p`: `btemp_165h`

</details>

<a id="gt-mirs-otros"></a>

#### Agua líquida de nube, temperatura de piel y 88 GHz

`gt-mirs-otros` · ATMS · Suomi-NPP, NOAA-20, NOAA-21

- **Contenido**: clw [mm], tskin [K], btemp_88v [K]
- **Formato**: GeoTIFF float32
- **Resolución**: wgs84_geo_5km
- **Notas**: Dato, sin vista. El 88 GHz sin polarización horizontal no distingue mar despejado de convección.

<details><summary>Para operación</summary>

- Ruta: `geotiff/mirs/` · patrón `{sat}_atms_{clw,tskin,btemp_88v}_*_wgs84_geo_5km.tif`
- Origen: Polar2Grid 3.2 → run_polar2grid_edr.sh
- Depende de: l2-mirs
- Polar2Grid `-p`: `clw tskin btemp_88v`

</details>

### Vistas sin GeoTIFF propio

<a id="vista-skewt"></a>

#### Diagrama Skew-T en estaciones de radiosondeo

`vista-skewt` · CrIS+ATMS · NOAA-20, NOAA-21

- **Contenido**: perfil de temperatura y humedad del sondeo más cercano a cada estación del SMN (config/sitios_skewt.tsv)
- **Formato**: SVG
- **Resolución**: FOR de CrIS, ~50 km
- **Notas**: Que falte el de una estación es normal: fuera de la franja o perfil rechazado por NUCAPS.

<details><summary>Para operación</summary>

- Ruta: `vistas/sounder/skewt/` · patrón `{sat}_atms-cris_skewt_<OMM>_*.svg`
- Vista: `vistas/sounder/skewt/` con `skewt`
- Origen: skewt (LANOT_tools) → run_polar2grid_edr.sh
- Depende de: l2-sounder

</details>

