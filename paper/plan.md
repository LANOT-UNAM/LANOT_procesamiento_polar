# Plan del artículo para *Investigaciones Geográficas* (2026)

Documento de trabajo, no borrador. El manuscrito vive en Dropbox
(`~/Dropbox/cca/lanot/Publicaciones/`, carpeta por crear); aquí va lo que depende del
repositorio: el plan, las normas (`normas.md`), las fuentes de las figuras y los scripts
que saquen las métricas. Los autores redactan; Claude revisa.

Abierto el 2026-11-21.

## Decidido

- **Autores:** los mismos que en 2025 (Alejandro Aguilar Sierra y Víctor Manuel Jiménez
  Escudero). Posible invitación a Uriel por el AFAI del proyecto de sargazo (abajo); se
  habla con él el lunes 2026-11-23.
- **Autor de correspondencia:** Alejandro Aguilar Sierra, responsable de esta cadena.
- **Ventana de evaluación:** diciembre de 2026, del 1 al 31. Se revisa al ver los datos.
- **Alcance:** solo satélites polares. GOES queda fuera: ya se cubrió en 2025.
- **Con resultados cuantitativos.**
- **Figuras obligadas:** el mapa de cobertura de la antena y los diagramas de la cadena.
- **Objetivo no declarado:** dar a conocer los productos polares y promover su potencial.
  En el texto aparece como algo para los usuarios ("qué pueden obtener y para qué sirve"),
  no como promoción.

## El antecedente y el riesgo de repetirlo

Aguilar Sierra, A. y Jiménez Escudero, V. M. (2025). Implementación de una infraestructura
de procesamiento satelital con software libre en el Laboratorio Nacional de Observación de
la Tierra, México. *Investigaciones Geográficas*. https://doi.org/10.14350/rig.61007
(copias en `~/Dropbox/cca/lanot/Publicaciones/investigaciones2025/`).

Lo que **ya contó** de la parte polar:

- TeraScan para la recepción;
- RT-STPS a RDR, e IPOPP 4.0 para SDR y EDR (VIIRS y MODIS);
- Flood 1.1 de CSPP;
- AAPP 8.12 para NOAA-18/19;
- Polar2Grid 2.3;
- la Figura 2, el diagrama de IPOPP;
- las tablas 3 a 5, de bandas y productos.

Su estructura fue Introducción, Metodología, Resultados y Recomendaciones: **sin objetivos,
sin preguntas de investigación, sin discusión y sin una sola cifra de operación**.

Este artículo no puede ser "la versión 2 del sistema". Para que no lo parezca:

- se cita en una frase, para lo que ya está contado, en tercera persona por el doble ciego;
- no se repiten sus tablas de bandas;
- el contraste con 2025 se usa como **línea base**: qué cambió y por qué.

## El aporte, en tres capas

1. **Cambio de arquitectura y por qué.** De IPOPP —el DRL está congelado— a CSPP, con cada
   etapa en un contenedor reproducible compilado de los paquetes oficiales. El software
   sigue siendo el de NOAA, NASA y CIMSS, pero ahora la instalación es una receta
   versionada: un servidor nuevo se levanta en horas, no en meses. Es el aporte central, y
   continúa el argumento de "autonomía tecnológica" de 2025 sin repetirlo.
2. **Evidencia de operación.** Las cifras que le faltaron a 2025: latencia, completitud,
   fiabilidad y reproducibilidad (sección "Métricas"). Sostienen la capa 1.
3. **Cobertura y productos nuevos**, como consecuencia de las dos primeras:
   - NOAA-21;
   - METOP-B/C dentro de la misma cadena;
   - sondeos NUCAPS (CrIS+ATMS e IASI+AMSU+MHS) con Skew-T en las estaciones del SMN;
   - lluvia y agua precipitable de MiRS;
   - ozono total de OMPS;
   - nubes y aerosoles de CSPP ATMOS, que sustituye a CLAVR-x.

   El catálogo (`docs/catalogo_productos.tsv`) tiene hoy 61 productos de nivel 1 en
   adelante.

## Preguntas de investigación (borrador para discutir)

1. ¿Puede una cadena construida solo con software libre de agencias y universidades,
   empaquetada en contenedores, sustituir a la anterior con productos equivalentes?
2. ¿Con qué latencia y con qué fiabilidad entrega los productos a los usuarios?
3. ¿Qué productos y aplicaciones nuevas aporta para el territorio y los mares de México?

Las tres se contestan con datos de la ventana de evaluación. La 3 es la que hace el artículo
geográfico.

## Estructura (subtítulos sin numerar, según las normas)

Extensión objetivo: unas 7 000 palabras, dentro del intervalo de 6 000 a 8 000.

| Sección | Contenido | Palabras |
|---|---|---|
| Introducción | Por qué importan los polares para México (complementan a GOES: resolución, sondeos, microondas, días nublados); el estado de 2025 como antecedente; el problema (IPOPP congelado, instalaciones artesanales, sistema viejo frágil); las preguntas. | ~900 |
| Objetivos | General y específicos, uno por pregunta. | ~200 |
| Metodología | Área de estudio (cobertura de la antena, Figura 1); satélites e instrumentos (tabla); criterio de selección de software (el de 2025, reafirmado); arquitectura por niveles (Figura 2) y contenedores (Figura 3); ventana de evaluación y cómo se midió. | ~2 000 |
| Resultados y discusión | Comparación con la cadena anterior; métricas; productos por aplicación con casos concretos (Figuras 4 en adelante); AFAI/sargazo si entra; limitaciones. | ~3 000 |
| Conclusiones | Respuesta a cada pregunta; trabajo futuro (Polar2Grid 3.3, SO₂ de OMPS, STAC, apagado del sistema viejo). | ~500 |
| Glosario | Como el de 2025: aquí van los términos técnicos que el texto evita. | fuera del conteo, a confirmar |

**Lenguaje.** Lo leen geógrafos:

- conceptos en el texto y detalle en el glosario;
- nada de nombres internos (servidores, scripts, rutas);
- "nivel 1/2", no "Level 1/2".

## Figuras (propuesta)

1. **Mapa de cobertura de la antena.** No existe: hay que hacerlo (sección "El mapa de
   cobertura").
2. **La cadena por niveles,** de la antena a la publicación, en español. Se puede comparar
   con la Figura 2 de 2025. Base: `docs/resumen/cadena.mmd`, simplificado y con la rama
   METOP.
3. **Qué va dentro del contenedor y qué vive en el servidor:** binarios dentro; datos
   estáticos, ancillary y datos fuera. Es la figura del aporte 1.
4. **En adelante, productos por aplicación,** pocas y elegidas por caso, no por cantidad:
   - un RGB de VIIRS con incendios superpuestos;
   - la lluvia de MiRS en un ciclón;
   - un Skew-T de NUCAPS junto al radiosondeo del SMN;
   - el ozono total;
   - el AFAI, si entra;
   - quizá una misma escena en la cadena vieja y en la nueva, AVHRR o VIIRS.

**Tablas candidatas:**

- satélites e instrumentos, con lo que se obtiene de cada uno;
- productos por aplicación: una selección del catálogo, no el catálogo entero;
- métricas de la ventana de evaluación.

## El mapa de cobertura

Propuesta: un solo mapa con **dos capas**, la teórica y la medida. La diferencia entre las dos
es en sí un resultado: obstáculos, pasadas perdidas y la franja de cada sensor.

**Capa 1, el círculo de adquisición (teórico).** Es la región sobre la que el satélite está
por encima de la elevación mínima de la antena. El ángulo central terrestre es

  λ = arccos( R·cos ε / (R + h) ) − ε

donde R es el radio terrestre, h la altura de la órbita y ε la elevación mínima. Va como
ecuación numerada y editable en la metodología. Con R = 6 371 km, ε = 5° y h = 824 km
(JPSS) sale λ = 23.1°, es decir **2 570 km**; con h = 817 km (METOP), 2 557 km. Es el mismo
cálculo y el mismo resultado de `~/proyectos/vsg` (`GUIA_MAESTRO.md`, lección G), que dibuja
ese círculo en el visor. A eso se le suma la mitad de la franja del sensor (VIIRS, unos
1 500 km), y así sale el área donde **hay datos**, más amplia que la del horizonte.

**Capa 2, la cobertura medida.** Cuántas pasadas por día ven cada punto en diciembre, por
satélite o en total, calculado con las huellas reales de las pasadas.

**Insumos:**

- [x] **Coordenadas de la antena: 19.328425° N, 99.176328° O**, es decir, 19°19′42.3″ N y
      99°10′34.8″ O. Es el alfiler de `~/proyectos/vsg` (`misiones/jpss.json`, campo
      `antena`), puesto sobre el edificio de las antenas en Google Maps
      (<https://maps.app.goo.gl/PH55B6Dpa36hjug49>). La precisión, de unos metros, sobra a
      esta escala. Falta la **altitud**: la del terreno se toma de un modelo de elevación
      (INEGI) más la altura del edificio. Para el círculo da igual; para el horizonte, no.
- [ ] **Elevación mínima configurada** en TeraScan (`system.config` de polaracq). Se revisa
      esta semana. vsg supone 5°.
- [ ] **El horizonte real** (sección siguiente).
- [ ] **TLE de cada día de la ventana**, para las alturas de órbita y para predecir los
      pasos. AAPP ya baja TLE en cada pasada de METOP (`get_tle`, en `/data/ancillary/aapp`);
      falta confirmar que conserva los de JPSS y que la retención (30 días) no se los lleve
      antes de enero. Si no, se archivan de CelesTrak, que además es la fuente citable.
- [ ] **Huellas de las pasadas de diciembre.** Los GeoTIFF se borran a los 14 días
      (`config/retencion.tsv`), así que hay que **guardarlas sobre la marcha**: un polígono
      por pasada, sacado de la geolocalización del SDR (VIIRS) o del Level 1 de AVHRR. Pesan
      poco. El mismo script anota la **hora del primer y del último dato** de cada pasada,
      que es lo que necesita el horizonte medido. Se escribe y se pone en cron antes del 1
      de diciembre.
- [ ] **Límites políticos y costas:** INEGI (marco geoestadístico) para México y Natural
      Earth para el resto, citados como fuente en el pie.

### El horizonte: vale la pena averiguarlo

Los 5° son una convención. El horizonte real del edificio decide cuánto se acerca el
círculo verdadero al teórico, y por qué lado se recorta. Además es un resultado geográfico
en sí: el relieve de la cuenca de México recortando lo que una antena alcanza a ver.

Una estimación a ojo dice que importa. El Ajusco (unos 3 900 m) está a unos 15–17 km al
sur-suroeste de CU (unos 2 300 m): unos 1 600 m de desnivel a esa distancia son **del orden
de 5° a 6° de elevación**, tanto como la máscara supuesta o más. Hay que calcularlo bien,
pero sugiere que el círculo se recorta hacia el sur, justo del lado de Centroamérica y el
Pacífico.

Tres formas de medirlo, que se complementan:

1. **Con nuestros datos, la que más vale.** Para cada pasada de la ventana, la hora del
   primer y del último dato recibido, junto con el TLE del día, da el **azimut y la
   elevación** a los que la antena enganchó y soltó al satélite. Con todas las pasadas de un
   mes se dibuja el **horizonte efectivo** de la antena, obstáculos incluidos: terreno,
   edificios y el árbol. Es la medida que importa para el artículo, y nadie más la tiene.
   Se calcula con Skyfield o con la propagación de `orbitas` de vsg. Si TeraScan guarda en
   su log la hora de inicio y fin de cada adquisición (AOS/LOS), sirve igual o mejor.
2. **Con un modelo digital de elevación.** El horizonte topográfico calculado desde la
   antena (CEM 3.0 de INEGI, o SRTM) con un trazo de rayos por azimut. Separa lo que es
   relieve de lo que son obstáculos cercanos, y es una fuente citable.
3. **En campo.** Un panorama o mediciones con inclinómetro desde la azotea, en los azimuts
   donde 1 y 2 no coincidan. Es el único que ve el árbol de
   `docs/Solicitud_Poda_LANOT_IGG.docx` y los edificios vecinos.

Con la 1 y la 2 alcanza para el artículo; la 3 solo si hay discrepancias que explicar. Como
figura, un diagrama polar (azimut contra elevación) con el horizonte del modelo de elevación
y los puntos de enganche y suelte de las pasadas, o bien el contorno recortado dibujado
sobre el mapa de cobertura.

**Producto secundario: pasadas perdidas.** Con los TLE se predicen todos los pasos sobre la
elevación mínima; contrastados con los recibidos, salen las pasadas que no llegaron. Esa
métrica falta en la lista de abajo, y explica la diferencia entre las dos capas del mapa.
vsg ya lo hace (`build/orbitas --pasos --fecha <día>`).

**Cartografía, según las normas:**

- Proyección **azimutal equidistante centrada en la antena**: el círculo de adquisición sale
  como círculo y la escala gráfica vale en todas direcciones desde el centro. En una rejilla
  geográfica (lat/lon) la escala gráfica sería engañosa a 2 600 km.
- Retícula con etiquetas en **grados, minutos y segundos**.
- **Escala gráfica** y **leyenda** explícita: círculos por satélite y escala de colores de
  pasadas por día.
- Título y fuente **fuera** del mapa; sin rosa de los vientos ni nombres.
- Herramienta: Python (cartopy/matplotlib) desde un script en `paper/figuras/`, para que se
  pueda regenerar con los datos de la ventana. QGIS si se prefiere acabado a mano, pero
  entonces sin la reproducibilidad.

## Métricas (ventana de evaluación)

**Diciembre de 2026**, del 1 al 31, con la cadena ya estable, METOP incluido y la rama METOP
vieja apagada (revisión del 27 de noviembre). Se pueden sacar de los logs de `cadena/` y de
los marcadores de `state/` en tahan.

**Retención:** en tahan no hay logrotate para `/var/log/lanot/polares/` (los de `cadena/` se
conservan desde agosto), pero los marcadores de `state/` se borran a los 30 días y los
GeoTIFF a los 14. Las cifras se sacan de los logs, y aun así conviene **extraerlas en la
primera semana de enero** y guardar el resultado en `paper/`, por si cambia la retención o
alguien configura logrotate.

Lo que se mide:

- pasos predichos con los TLE contra pasadas recibidas, por satélite (sección del
  horizonte);
- pasadas recibidas por satélite, y cuántas quedaron completas, parciales o fallidas;
- latencia del fin de la pasada a la publicación, por producto (mediana y percentil 90); la
  espera del GFS explica la cola de ATMOS y LSR (estado, 2026-11-03 y 2026-11-18);
- tiempo de proceso por eslabón;
- volumen producido por día (GB, número de archivos);
- reproducibilidad: dos corridas de la misma pasada dan los mismos datos (control del
  2026-11-14; con las excepciones medidas de Active Fire y ACSPO);
- equivalencia con la cadena vieja en los productos que comparten (comparación de
  convivencia de METOP; JPSS ya está apagado en la vieja, ver si quedan datos de comparación
  de antes del 2026-11-04).

Las saca Claude con un script en `paper/`. Se escribe y se prueba con noviembre, para que
el 1 de enero solo haya que correrlo.

## AFAI y sargazo (propuesta, por confirmar con Uriel)

Le da al artículo la aplicación geográfica más fuerte: el sargazo en el Caribe mexicano.
Además es la prueba de que los contenedores sirven a un tercero: Uriel reconstruyó el AFAI
histórico corriendo nuestros contenedores con copias de nuestros scripts.

Por acordar:

- **Qué sección escribe Uriel.** Método del AFAI y resultados; tiene que ser un aporte
  propio para que la carta de autoría lo sostenga.
- **Si choca con un artículo propio de su proyecto** sobre sargazo.
- **Si el índice se calcula dentro de la cadena** o lo calcula "el otro equipo": hoy los
  scripts de Uriel entregan GeoTIFF y el índice lo hacen otros.

## Casos de estudio (criterios, no eventos todavía)

Las figuras de productos se eligen por aplicación, no por cantidad. Un buen caso:

- **ocurre en la ventana o cerca**, para que sus datos sigan en tahan (14 días de GeoTIFF,
  90 de vistas) o se puedan reprocesar de los crudos;
- **lo ve más de un producto de la misma pasada**, por ejemplo incendios sobre el RGB y la
  pluma en el AOD de ATMOS, o lluvia de MiRS con los sondeos alrededor de un frente;
- **tiene una referencia independiente para comparar:**
  - radiosondeo del SMN para un Skew-T;
  - reporte de CONAFOR para incendios;
  - boletín del SMN para un frente frío o un norte;
  - el monitoreo de sargazo para el AFAI;
- **le dice algo a un usuario nombrado en 2025**, como CENAPRED, SEMAR o el SMN.

Diciembre trae frentes fríos y nortes en el Golfo, y temporada de incendios temprana en
algunas zonas; no trae ciclones. Los ciclones salen de la temporada 2026:

- **Polo** (20 al 29 de septiembre; tocó tierra en Baja California Sur y Sonora el 28 y 29).
- **Rachel** (27 de septiembre al 11 de octubre; huracán desde el 30 de septiembre).

Hay que citar como fuente el archivo histórico del SMN.

Qué hay de esas fechas (estado, "2026-11-21: el archivo en `/depot`"):

- **Nuestras vistas:** RGB, incendios, DNB, ATMOS, sondeos con Skew-T y MiRS (desde el 26 de
  septiembre). Archivadas en `/depot/polar/jpss/vistas`. Alcanzan para las figuras.
- **Crudos completos** en `/depot`, del 16 de septiembre al 13 de octubre.
- **Niveles 1 y 2 de la cadena vieja**, solo NPP y NOAA-20, en `/depot/polar/npp_jpss`.
- **Falta el ancillary de esas fechas.** Si hace falta un dato y no solo una vista (por
  ejemplo, la lluvia de MiRS para cuantificar, o un perfil de NUCAPS para compararlo con el
  radiosondeo), hay que regenerar desde los crudos con el GFS histórico de NOAA, y con TLE
  y autocalibración de SDR de esas fechas si CSPP los puede bajar.

  Es justo la prueba de restauración del archivo: hacerla con una pasada de Polo sirve a
  las dos cosas.

Conviene llevar una **bitácora de candidatos** durante diciembre, una línea por evento con
la fecha, la pasada y los productos. Así, en enero se elige entre eventos ya ubicados y no
se buscan de memoria.

## Glosario

Como el de 2025, y por la misma razón: el texto habla de conceptos y el glosario carga los
términos técnicos. Candidatos:

- niveles de procesamiento 0, 1 y 2;
- RDR, SDR y EDR;
- contenedor;
- ancillary;
- GFS;
- sondeo;
- Skew-T;
- franja de barrido;
- TLE;
- elevación mínima;
- pasada o paso.

Reusar las definiciones de 2025 donde existan, para que los dos artículos hablen igual.

## Por decidir

- [ ] Título (máximo 20 palabras) y las cinco palabras clave, que no estén en el título.
- [ ] Insumos del mapa de cobertura (lista en su sección); TeraScan, esta semana.
- [ ] Uriel y el AFAI (lunes 2026-11-23).
- [ ] Casos de estudio: qué eventos, de qué fechas.
- [ ] Fecha de corte del "estado actual": Polar2Grid 3.3 y el SO₂ de OMPS siguen pendientes;
      NPP salió el 2026-11-02.
- [ ] Fecha de envío objetivo. Con la ventana en diciembre, las cifras están en la primera
      semana de enero; antes de eso se puede escribir todo menos los resultados.

## Plazos (por discutir)

Propuesta de Claude, todavía sin acordar:

- **Antes del 1 de diciembre:**
  - el script que guarda la huella y la hora de inicio y fin de cada pasada, en cron en
    tahan; va como prueba (desde el clon) o como operación (`/opt`, `instalar.sh`): decidir;
  - el archivo diario de TLE.
- **Noviembre:**
  - el script de métricas, probado con los datos de noviembre;
  - el horizonte topográfico con el modelo de elevación, que no depende de la ventana.
- **Durante diciembre:** la bitácora de casos de estudio.
- **Primera semana de enero:**
  - las métricas de diciembre, guardadas en `paper/`;
  - el horizonte medido;
  - el mapa de cobertura.

## Para el envío (de `normas.md`)

- [ ] Manuscrito en `.odt` o `.docx`, con números de página y de línea continuos, sin datos
      de autoría.
- [ ] Hoja aparte con el título en español e inglés, los nombres completos, la adscripción,
      los correos, los ORCID y el autor de correspondencia.
- [ ] Carta al Editor en Jefe con la originalidad y la participación de cada autor,
      **firmada por todos**.
- [ ] Resúmenes de 250 palabras como máximo, en español y en inglés.
- [ ] Referencias en APA 7 con DOI; la autocita en tercera persona.
- [ ] Figuras insertadas como imágenes, con pie y fuente fuera, sin nombres; los mapas, con
      los requisitos de mapas.
