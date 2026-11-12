# Páginas de texto del resumen (verticales). La 2, la del diagrama, la pone
# ensamblar.py; por eso la numeración salta de 1 a 3.
#   python3 texto.py <salida.pdf>
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image, Table,
                                TableStyle, KeepTogether)

SALIDA = sys.argv[1]
F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-B", F + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-I", F + "DejaVuSans-Oblique.ttf"))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-B", italic="Sans-I", boldItalic="Sans-B")

TINTA = colors.HexColor("#1f2328")
GRIS = colors.HexColor("#57606a")
AZUL = colors.HexColor("#1f4e8c")
LINEA = colors.HexColor("#d0d7de")
FONDO = colors.HexColor("#f6f8fa")

base = ParagraphStyle("base", fontName="Sans", fontSize=9.6, leading=13.6, textColor=TINTA,
                      spaceAfter=6)
titulo = ParagraphStyle("titulo", parent=base, fontName="Sans-B", fontSize=19, leading=23,
                        spaceAfter=4, textColor=AZUL)
sub = ParagraphStyle("sub", parent=base, fontSize=10.5, leading=14, textColor=GRIS, spaceAfter=2)
h2 = ParagraphStyle("h2", parent=base, fontName="Sans-B", fontSize=12.5, leading=16,
                    spaceBefore=10, spaceAfter=5, textColor=AZUL)
pie = ParagraphStyle("pie", parent=base, fontSize=8.4, leading=11, textColor=GRIS,
                     alignment=TA_CENTER)
celda = ParagraphStyle("celda", parent=base, fontSize=8.6, leading=11.4, spaceAfter=0)
celda_b = ParagraphStyle("celda_b", parent=celda, fontName="Sans-B")
vineta = ParagraphStyle("vineta", parent=base, leftIndent=12, bulletIndent=2, spaceAfter=3.5)

def P(t, s=base): return Paragraph(t, s)
def V(t): return Paragraph(t, vineta, bulletText="•")

def tabla(filas, anchos):
    datos = [[P(c, celda_b if i == 0 else celda) for c in f] for i, f in enumerate(filas)]
    t = Table(datos, colWidths=anchos, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), FONDO),
        ("LINEBELOW", (0, 0), (-1, 0), 0.8, AZUL),
        ("LINEBELOW", (0, 1), (-1, -1), 0.4, LINEA),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t

def numerar(c, doc):
    c.saveState()
    c.setFont("Sans", 7.8)
    c.setFillColor(GRIS)
    c.drawString(doc.leftMargin, 1.2 * cm, "Procesamiento de satélites polares · LANOT-UNAM")
    c.drawRightString(letter[0] - doc.rightMargin, 1.2 * cm, f"{doc.page if doc.page == 1 else doc.page + 1}")
    c.restoreState()

doc = SimpleDocTemplate(SALIDA, pagesize=letter, leftMargin=2.1 * cm, rightMargin=2.1 * cm,
                        topMargin=1.9 * cm, bottomMargin=2.0 * cm,
                        title="Procesamiento de satélites polares del LANOT",
                        author="Alejandro Aguilar Sierra",
                        subject="Resumen del proyecto")
ancho = letter[0] - doc.leftMargin - doc.rightMargin
h = []

h.append(P("Procesamiento de satélites polares del LANOT", titulo))
h.append(P("Resumen del proyecto · noviembre de 2026", sub))
h.append(P("Alejandro Aguilar Sierra · Laboratorio Nacional de Observación de la Tierra, UNAM", sub))
h.append(Spacer(1, 8))

h.append(P("Qué es", h2))
h.append(P(
    "Es la cadena operativa con la que el LANOT convierte en productos los datos que su antena "
    "recibe por transmisión directa de los satélites polares de la serie JPSS. Cada vez que "
    "un satélite pasa sobre México, la antena entrega el crudo y la cadena lo lleva, sin "
    "intervención manual, desde los paquetes de telemetría hasta mapas de nubes, temperatura "
    "del mar, incendios, lluvia, ozono o sondeos atmosféricos. Lo publica en el servicio de "
    "datos del laboratorio y en su portal web, por lo general entre 25 y 40 minutos después "
    "de recibirlo."))
h.append(P(
    "Hoy procesa <b>NOAA-20</b> y <b>NOAA-21</b>. Suomi-NPP se procesó hasta su último crudo, "
    "el 2 de noviembre de 2026. Desde el 4 de noviembre esta cadena sustituye a la anterior "
    "en todo lo de JPSS. Los <b>METOP-B y C</b> están planeados para la misma "
    "infraestructura, porque comparten recepción y buena parte del software."))
h.append(P(
    "El diagrama de la página siguiente muestra el recorrido de los datos, desde la antena "
    "hasta la publicación."))
h.append(P(
    "El proyecto no contiene software científico ni datos. Contiene la <i>infraestructura como "
    "código</i> que monta los paquetes oficiales, los encadena y los vigila: recetas de "
    "contenedores, orquestación, configuración y documentación. Los algoritmos son los de "
    "NASA, NOAA y CIMSS/SSEC de la Universidad de Wisconsin-Madison, en sus versiones de "
    "distribución pública."))

h.append(P("Qué produce", h2))
h.append(P(
    "Cada producto sale en dos formas: como <b>dato</b> (HDF5 o NetCDF tal como lo entrega el "
    "algoritmo, y GeoTIFF de punto flotante sobre una rejilla geográfica fija) y, cuando "
    "alguien lo va a mirar, como <b>vista</b> (imagen JPG con paleta, costas, fecha y logo). "
    "Las rejillas son de 375 m y 750 m para VIIRS, y de 5 km para microondas, sondeos y "
    "ozono."))
h.append(tabla([
    ["Instrumento", "Paquete", "Productos"],
    ["VIIRS (visible e infrarrojo)", "CSPP SDR", "Bandas M e I calibradas; banda día/noche; composiciones en color verdadero y falso color"],
    ["", "ATMOS", "Nubes (máscara, tipo, fase, altura del tope, fracción) y aerosoles"],
    ["", "LSR · CRYO", "Reflectancia de superficie, índices de vegetación NDVI y EVI; hielo"],
    ["", "ACSPO", "Temperatura superficial del mar"],
    ["", "Active Fire", "Incendios activos, a 375 m y a 750 m"],
    ["", "Flood", "Extensión de inundaciones"],
    ["ATMS (microondas)", "MiRS", "Tasa de lluvia, agua precipitable total, temperatura de brillo a 165 GHz"],
    ["CrIS + ATMS (sondeo)", "HEAP · NUCAPS", "Perfiles de temperatura y humedad; mapas a 850, 700 y 500 hPa y de piel; diagramas Skew-T en las estaciones de radiosondeo del SMN"],
    ["OMPS (ozono)", "OMPS L2", "Columna total de ozono y perfil vertical"],
], [3.5 * cm, 2.6 * cm, ancho - 6.1 * cm]))

h.append(P("Cómo está construido", h2))
h.append(V(
    "<b>Un contenedor por paquete.</b> Cada software corre en una imagen Apptainer compilada "
    "a partir del paquete oficial, sobre una imagen base común de Rocky Linux. Así se "
    "reproduce el entorno que validan sus autores y se aíslan bibliotecas que no "
    "conviven en un mismo sistema."))
h.append(V(
    "<b>Lo que cambia vive fuera de la imagen.</b> Las imágenes llevan solo binarios. Tablas de "
    "calibración, datos auxiliares (pronóstico GFS, efemérides), paletas y configuración "
    "se montan desde el servidor, así que actualizarlos no obliga a recompilar."))
h.append(V(
    "<b>La pasada es la unidad de trabajo.</b> Los archivos de un mismo sobrevuelo se agrupan "
    "por satélite y tiempo, y cada pasada se procesa aislada de las demás, con hasta tres "
    "etapas en paralelo y respetando sus dependencias: por ejemplo, superficie y hielo "
    "esperan a los productos de atmósfera."))
h.append(V(
    "<b>Éxito significa completo.</b> Una etapa se da por hecha solo si produjo todo lo que "
    "debía, no solo si terminó sin error. Lo incompleto se reintenta automáticamente, y lo que "
    "depende de datos auxiliares que aún no se publican se pospone en vez de fallar."))
h.append(V(
    "<b>Operación desatendida.</b> La recepción dispara el procesamiento. Un barrido periódico "
    "recoge lo que se quedó atrás, una política de retención libera el disco, y dos "
    "publicadores copian los productos al servicio de datos y al portal."))

h.append(P("Software", h2))
h.append(tabla([
    ["Etapa", "Software", "Origen"],
    ["Level 0", "RT-STPS 7.0", "NASA (distribuido con CSPP)"],
    ["Level 1", "CSPP SDR 4.1.1", "CIMSS/SSEC"],
    ["Level 2", "CSPP ATMOS 1.0 · LSR 2.0 · Cryo 1.0 · ACSPO 3.0 · Active Fire 2.1 · Flood 2.0 · MiRS 4.0 · HEAP 3.0 · OMPS L2 1.0", "CIMSS/SSEC, con algoritmos de NOAA/STAR"],
    ["Remuestreo", "Polar2Grid 3.2 (Satpy)", "CIMSS/SSEC · Pytroll"],
    ["Vistas", "LANOT_tools · MetaGráfica", "LANOT"],
    ["Contenedores", "Apptainer sobre Rocky Linux 8 y 9", "—"],
], [2.6 * cm, ancho - 7.6 * cm, 5.0 * cm]))

h.append(P("Estado y siguientes pasos", h2))
h.append(P(
    "La cadena está en operación con los doce eslabones probados sobre datos reales, y cubre "
    "todo lo que hacía la cadena anterior más los sondeos, la microondas y el ozono. "
    "El trabajo de los próximos meses es:"))
h.append(V("integrar <b>METOP-B y C</b>;"))
h.append(V("cerrar la verificación de reproducibilidad de tres algoritmos (ACSPO, Active Fire y MiRS);"))
h.append(V("dar vista a los productos de hielo, que hoy solo se publican como dato;"))
h.append(V("migrar a Polar2Grid 3.3, que trae lectores nuevos y permite retirar los ajustes locales."))
h.append(Spacer(1, 4))
h.append(P(
    "Durante el desarrollo se reportó a SSEC una falla del lector de sondeos de Polar2Grid, que "
    "quedó corregida aguas arriba (pytroll/satpy#3450). Además se propuso a Satpy el cálculo "
    "de CAPE e índice de levantamiento para los sondeos NUCAPS (pytroll/satpy#3480), "
    "pendiente de revisión."))

doc.build(h, onFirstPage=numerar, onLaterPages=numerar)
print("ok", SALIDA)
