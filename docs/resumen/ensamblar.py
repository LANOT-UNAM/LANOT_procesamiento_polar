# Arma el resumen: la página 1 del texto, el diagrama en una página horizontal
# (vectorial, escalado a la caja) y el resto del texto.
#   python3 ensamblar.py <cadena.pdf> <texto.pdf> <salida.pdf>
import sys, io
from pypdf import PdfReader, PdfWriter, Transformation
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

DIAGRAMA, TEXTO, SALIDA = sys.argv[1:4]
F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-B", F + "DejaVuSans-Bold.ttf"))
AZUL = colors.HexColor("#1f4e8c"); GRIS = colors.HexColor("#57606a")

W, H = landscape(letter)
ml, mr, mt, mb = 2.1 * cm, 2.1 * cm, 1.6 * cm, 2.0 * cm
buf = io.BytesIO()
c = canvas.Canvas(buf, pagesize=(W, H))
c.setFont("Sans-B", 12.5); c.setFillColor(AZUL)
c.drawString(ml, H - mt - 10, "La cadena")
c.setFont("Sans", 8.4); c.setFillColor(GRIS)
c.drawCentredString(W / 2, mb + 4, "Del crudo de la antena a los productos publicados. Cada recuadro es un paquete oficial "
                    "que corre en su propio contenedor; las flechas que salen de")
c.drawCentredString(W / 2, mb - 7, "Level 1 indican de qué instrumento se alimenta cada rama de Level 2.")
c.setFont("Sans", 7.8)
c.drawString(ml, 0.9 * cm, "Procesamiento de satélites polares · LANOT-UNAM")
c.drawRightString(W - mr, 0.9 * cm, "2")
c.save()
w = PdfWriter()
texto = PdfReader(TEXTO)
w.add_page(texto.pages[0])
pagina = w.add_page(PdfReader(io.BytesIO(buf.getvalue())).pages[0])

dib = PdfReader(DIAGRAMA).pages[0]
dw, dh = float(dib.mediabox.width), float(dib.mediabox.height)
caja_x0, caja_y0 = ml, mb + 22
caja_w, caja_h = W - ml - mr, H - mt - 24 - caja_y0
e = min(caja_w / dw, caja_h / dh)
x = caja_x0 + (caja_w - dw * e) / 2 - float(dib.mediabox.left) * e
y = caja_y0 + (caja_h - dh * e) / 2 - float(dib.mediabox.bottom) * e
pagina.merge_transformed_page(dib, Transformation().scale(e).translate(x, y))
print(f"escala del diagrama: {e:.2f}")

for p in texto.pages[1:]: w.add_page(p)
w.add_metadata({"/Title": "Procesamiento de satélites polares del LANOT",
                "/Author": "Alejandro Aguilar Sierra", "/Subject": "Resumen del proyecto"})
with open(SALIDA, "wb") as f: w.write(f)
print("ok", len(w.pages), "páginas")
