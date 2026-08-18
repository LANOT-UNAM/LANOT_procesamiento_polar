#!/usr/bin/env python3
# ==============================================================================
# publicar_vistas.py — arma una galería web autocontenida a partir de vistas/
#
# Corre DENTRO de polar2grid_v3.2-mapdrawer.sif, invocado por publicar_vistas.sh
# con el intérprete del venv de LANOT_tools:
#
#   /opt/lanot-tools/venv/bin/python /publicador/publicar_vistas.py …
#
# De ahí salen las tres dependencias, y ninguna hay que instalarla en el host:
# Pillow para las miniaturas, `metadata` para fichar cada imagen por su nombre y
# `colorpalettetable` para leer el rango de la paleta con la que se coloreó.
#
# POR QUÉ ESAS Y NO UNA TABLA PROPIA: `metadata.product_map` es la MISMA lista
# con la que geotiff2view rotula la imagen, y el CPT es el MISMO archivo con el
# que la coloreó. Mientras el pie de foto salga de ahí, el HTML y el JPG no se
# pueden contradecir. Un producto sin entrada en product_map sale sin nombre en
# los dos lados a la vez, que es justo la señal que se quiere.
#
# El resultado tiene que ser PORTÁTIL: la carpeta se copia a mano a un servidor
# web. De ahí tres reglas que no se pueden relajar:
#   · copias reales de los JPG, nunca enlaces simbólicos, que no sobreviven al
#     copiado;
#   · rutas relativas en todo el HTML;
#   · cero recursos externos — la hoja de estilo va en la propia carpeta.
# Así un `scp -r` a cualquier docroot deja la galería funcionando, y `file://`
# sirve para revisarla antes de copiar.
# ==============================================================================

import argparse
import html
import os
import re
import shutil
import sys
from datetime import datetime, timedelta, timezone

from PIL import Image

from colorpalettetable import ColorPaletteTable
from metadata import Metadata

# Las categorías son las carpetas que crean run_polar2grid_l1.sh (dnb, rgb) y
# run_polar2grid_edr.sh (el resto). El orden es el de la galería: primero lo que
# se mira, no el alfabético. Una categoría sin imágenes seleccionadas no se
# publica, así que `sounder` no aparecerá mientras HEAP siga desactivado.
CATEGORIAS = [
    ("dnb",     "Day/Night Band"),
    ("rgb",     "Compuestos RGB"),
    ("atmos",   "Atmósfera y nubes"),
    ("acspo",   "Temperatura superficial del mar"),
    ("fire",    "Incendios activos"),
    ("flood",   "Inundaciones"),
    ("lsr",     "Reflectancia de superficie"),
    ("sounder", "Sondeos hiperespectrales"),
]

# El sello que Polar2Grid pone en el nombre: {producto}_{AAAAMMDD}_{HHMMSS}_{rejilla}
#
# El separador final se mira con lookahead y acepta punto además de guion bajo,
# porque INUNDACIONES NO SIGUE EL PATRÓN: su GeoTIFF no lo hace Polar2Grid sino
# flood2tif.sh del bundle de CSPP, así que el nombre termina en el sello y no
# lleva rejilla — noaa20_viirs_flood_20260817_193624.jpg. Exigiendo guion bajo
# final, las vistas de flood se caían de la galería como "sin sello".
SELLO = re.compile(r"_(\d{8})_(\d{6})(?=[_.])")

# La rejilla es el último campo antes de la extensión: wgs84_geo_750m → 750 m.
REJILLA = re.compile(r"_([a-z0-9]+(?:_[a-z0-9]+)*?_(\d+)(m|km))\.jpg$", re.IGNORECASE)

# Los tokens de satélite que metadata.py reconoce. Aquí solo hacen falta para
# cortar grupos: dos pasadas de satélites distintos no son la misma pasada
# aunque sus sellos caigan cerca.
SATELITE = re.compile(r"^(npp|noaa20|noaa21|noaa22|j01|j02|j03)", re.IGNORECASE)


# ==============================================================================
# DESCUBRIMIENTO Y AGRUPAMIENTO
# ==============================================================================

class Vista:
    """Un JPG de vistas/, con lo que se puede saber de él por su nombre."""

    def __init__(self, ruta, categoria):
        self.ruta = ruta
        self.categoria = categoria
        self.nombre = os.path.basename(ruta)

        m = SELLO.search(self.nombre)
        self.fecha = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")

        m = SATELITE.match(self.nombre)
        self.satelite_token = m.group(1).lower() if m else "?"

    def __repr__(self):
        return f"<Vista {self.categoria}/{self.nombre}>"


def descubrir(raiz):
    """Todos los JPG de vistas/<categoria>/, con sello temporal legible.

    Los que no traen sello se ignoran y se cuentan aparte: sin fecha no se
    pueden agrupar por pasada, que es de lo que depende toda la selección.
    """
    vistas, sin_sello = [], []

    for categoria, _ in CATEGORIAS:
        directorio = os.path.join(raiz, categoria)
        if not os.path.isdir(directorio):
            continue
        for nombre in sorted(os.listdir(directorio)):
            if not nombre.lower().endswith(".jpg"):
                continue
            ruta = os.path.join(directorio, nombre)
            if SELLO.search(nombre):
                vistas.append(Vista(ruta, categoria))
            else:
                sin_sello.append(ruta)

    return vistas, sin_sello


def agrupar(vistas, hueco_min):
    """Parte la lista en pasadas.

    Corta un grupo nuevo cuando hay un hueco mayor a `hueco_min` o cambia el
    satélite. El umbral por omisión son 45 minutos, y no es arbitrario: los
    gránulos de UNA pasada abarcan 10-15 min y dos pasadas consecutivas del
    mismo satélite van a ~101 min, así que 45 cae holgado en medio.

    Se agrupa por tiempo y no por la clave de pasada (j01_d20260817_b45321)
    porque el nombre del JPG no la lleva: Polar2Grid bautiza por sello temporal.
    """
    grupos = []
    for vista in sorted(vistas, key=lambda v: (v.fecha, v.nombre)):
        if (grupos
                and vista.satelite_token == grupos[-1][-1].satelite_token
                and (vista.fecha - grupos[-1][-1].fecha) <= timedelta(minutes=hueco_min)):
            grupos[-1].append(vista)
        else:
            grupos.append([vista])
    return grupos


class Pasada:
    """Un grupo de vistas que salieron del mismo sobrevuelo."""

    def __init__(self, vistas, tz_offset):
        self.vistas = vistas
        self.inicio = vistas[0].fecha
        self.fin = vistas[-1].fecha
        self.satelite_token = vistas[0].satelite_token

        meta = Metadata()
        meta.enrich_from_filename(vistas[0].nombre)
        self.satelite = meta.get("satellite", self.satelite_token.upper())

        local = self.inicio + timedelta(hours=tz_offset)
        self.hora_local = local
        # Etiqueta cosmética. La regla es la hora local del inicio del grupo:
        # NOAA-20 cruza a las 13:30 y 01:30 locales, así que no hay caso dudoso.
        self.momento = "diurna" if 6 <= local.hour < 18 else "nocturna"

    @property
    def clave(self):
        return self.inicio.strftime("%Y%m%d_%H%M%S")

    @property
    def titulo(self):
        return (f"{self.satelite} · {self.inicio.strftime('%Y/%m/%d %H:%M')}Z "
                f"({self.hora_local.strftime('%H:%M')} local, {self.momento})")


# ==============================================================================
# LA NOTA DE LA PALETA
# ==============================================================================
# Todo lo que dice la ficha sobre la paleta se lee del CPT y de la tabla PALETAS
# de run_polar2grid_edr.sh. Ni una palabra escrita a mano aquí: si mañana se
# corrige un rango —como pasó con el skin del 2026-08-17, que subió de 315 a
# 325— la nota se corrige sola.

CLAVE_CPT = re.compile(r"^[A-Z_]+\s*=")


def cargar_paletas(script_edr):
    """Lee la tabla PALETAS de run_polar2grid_edr.sh como [(token, cpt), …].

    Se lee del script y no se copia aquí para que no haya dos listas que
    mantener. El orden importa: gana el primer token que aparezca como
    subcadena, igual que en `paleta_de()` del propio script.
    """
    if not os.path.isfile(script_edr):
        return []

    paletas, dentro = [], False
    with open(script_edr, encoding="utf-8") as fh:
        for linea in fh:
            if linea.startswith("PALETAS=("):
                dentro = True
                continue
            if dentro:
                if linea.startswith(")"):
                    break
                m = re.match(r'\s*"([^:"]+):([^"]+)"', linea)
                if m:
                    paletas.append((m.group(1), m.group(2)))
    return paletas


def descripcion_cpt(ruta):
    """La línea en prosa del encabezado del CPT.

    ColorPaletteTable levanta UNIT = pero no esta línea, así que se lee aquí. El
    encabezado es: primera línea el nombre del archivo, luego una o más de
    prosa, luego las claves (UNIT =, COLOR_MODEL =). Se toma la primera de
    prosa.
    """
    try:
        with open(ruta, encoding="utf-8", errors="replace") as fh:
            primera = True
            for linea in fh:
                linea = linea.strip()
                if not linea.startswith("#"):
                    break
                texto = linea.lstrip("#").strip()
                if primera:            # el nombre del propio archivo
                    primera = False
                    continue
                if not texto or CLAVE_CPT.match(texto):
                    continue
                return texto
    except OSError:
        pass
    return None


class Paleta:
    """Lo que la ficha va a decir de la paleta de un producto."""

    def __init__(self, cpt, ruta):
        self.cpt = cpt
        self.descripcion = descripcion_cpt(ruta)
        self.rango = None
        self.clases = []

        tabla = ColorPaletteTable(ruta)

        # Con `labels` poblado el CPT es categórico: no hay rango que enseñar
        # sino clases, que es justo lo que la barra de color impresa en la
        # imagen no alcanza a decir.
        if getattr(tabla, "labels", None):
            for valor in sorted(tabla.labels):
                color = tabla.colors.get(valor, (128, 128, 128))
                self.clases.append((valor, tabla.labels[valor], color))
        else:
            unidad = f" {tabla.units}" if tabla.units else ""
            self.rango = f"{_num(tabla.min_val)}–{_num(tabla.max_val)}{unidad}"


def _num(valor):
    """Formatea un extremo de rango sin decimales de adorno."""
    if float(valor) == int(float(valor)):
        return str(int(float(valor)))
    return f"{float(valor):g}"


class Paletas:
    """Resuelve nombre de archivo → Paleta, con caché."""

    def __init__(self, script_edr, colortables):
        self.tabla = cargar_paletas(script_edr)
        self.colortables = colortables
        self.cache = {}

    def de(self, nombre, categoria=None):
        cpt = CPT_POR_CATEGORIA.get(categoria)
        if cpt is None:
            for token, candidato in self.tabla:
                if token in nombre:
                    cpt = candidato
                    break
        if cpt is None:
            return None

        if cpt not in self.cache:
            ruta = os.path.join(self.colortables, cpt)
            self.cache[cpt] = Paleta(cpt, ruta) if os.path.isfile(ruta) else None
        return self.cache[cpt]


# Inundaciones es la excepción de siempre y también lo es aquí: su paleta no sale
# de la tabla PALETAS sino de la llamada a mapdrawer (run_polar2grid_edr.sh:920),
# porque el GeoTIFF ya trae el colormap incrustado por cspp_viirs_flood2tif.sh y
# a mapdrawer solo se le pasa el CPT para que dibuje la leyenda. Sin esta entrada
# la única vista con paleta categórica de la cadena saldría sin explicar sus
# clases, que es justo lo que menos se adivina mirando la imagen.
CPT_POR_CATEGORIA = {"flood": "flood.cpt"}


# El DNB es el caso contrario al de las paletas fijas y merece decirse, sobre
# todo siendo la imagen que se quiere presumir: va en escala de grises estirada
# al percentil 1-99 DE CADA ESCENA (run_polar2grid_l1.sh:484). Sin ese recorte
# la cola larga la deja casi negra; con él, dos DNB no son comparables en
# absoluto. Decirlo evita que alguien lea brillo como cantidad de luz.
NOTA_DNB = ("Escala de grises estirada al percentil 1–99 <em>de esta escena</em>. "
            "El realce es por escena, así que el brillo no es comparable entre pasadas.")

# La justificación de las paletas fijas va una vez por página y no por ficha:
# es la misma para todas y repetirla catorce veces sería ruido.
NOTA_PALETAS = ("Los rangos de las paletas son <strong>fijos, no ajustados a cada escena</strong>: "
                "es lo que permite comparar dos pasadas del mismo producto. El precio es poco "
                "contraste cuando el campo tiene rango estrecho de por sí.")


# ==============================================================================
# LA FICHA DE CADA IMAGEN
# ==============================================================================

class Ficha:
    """El pie de foto de una vista: qué es, de cuándo, con qué paleta."""

    def __init__(self, vista, paletas, tz_offset):
        self.vista = vista
        self.nombre = vista.nombre

        # SE LE PASA LA CATEGORÍA, NO SOLO EL NOMBRE, y no es un detalle:
        # enrich_from_filename busca el producto primero en el basename y
        # después en la RUTA COMPLETA. Los renderizadores le dan a geotiff2view
        # rutas como /output_fire_tif/<archivo> (run_polar2grid_edr.sh:787), así
        # que `confidence_cat` —que no tiene entrada propia en product_map— sale
        # rotulado "Fire" en la imagen gracias al directorio. Pasando solo el
        # basename, la ficha diría otra cosa que el JPG, que es exactamente lo
        # que esta reutilización está para evitar.
        meta = Metadata()
        meta.enrich_from_filename(os.path.join(vista.categoria, self.nombre))

        # Sin entrada en product_map no hay nombre de producto. Se rotula con el
        # archivo y se cuenta, porque es el mismo síntoma que una vista sin
        # nombre: al agregar un CPT hay que agregar también su entrada.
        self.producto = meta.get("product")
        self.sin_producto = self.producto is None
        if self.sin_producto:
            self.producto = self.nombre

        partes = [meta.get("satellite"), meta.get("sensor")]
        self.origen = " · ".join(p for p in partes if p)

        self.utc = vista.fecha.strftime("%Y/%m/%d %H:%M") + "Z"
        self.local = (vista.fecha + timedelta(hours=tz_offset)).strftime("%H:%M")

        m = REJILLA.search(self.nombre)
        self.resolucion = f"{m.group(2)} {m.group(3)}" if m else None

        self.paleta = paletas.de(self.nombre, vista.categoria)
        self.nota_dnb = "dnb" in self.nombre.lower()

        # Peso y dimensiones, que es lo que alguien quiere saber antes de darle
        # a descargar.
        self.bytes = os.path.getsize(vista.ruta)
        try:
            with Image.open(vista.ruta) as img:
                self.ancho, self.alto = img.size
        except OSError:
            self.ancho = self.alto = None

    @property
    def peso(self):
        mb = self.bytes / (1024 * 1024)
        return f"{mb:.1f} MB" if mb >= 1 else f"{self.bytes / 1024:.0f} kB"

    @property
    def dimensiones(self):
        if self.ancho:
            return f"{self.ancho} × {self.alto}"
        return None


# ==============================================================================
# HTML
# ==============================================================================

ESTILO = """\
/* Hoja propia y única: la galería no puede depender de ningún recurso externo,
   porque la carpeta se copia tal cual a un servidor web. */
:root {
    --fondo: #14171c;
    --tarjeta: #1d222a;
    --borde: #2c333e;
    --texto: #e6e9ee;
    --tenue: #98a2b3;
    --acento: #ffc94a;
}
* { box-sizing: border-box; }
body {
    margin: 0;
    padding: 2rem 1.5rem 4rem;
    background: var(--fondo);
    color: var(--texto);
    font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
main { max-width: 1180px; margin: 0 auto; }
h1 { font-size: 1.6rem; margin: 0 0 .3rem; }
h2 {
    font-size: 1.1rem;
    margin: 2.5rem 0 .2rem;
    padding-bottom: .4rem;
    border-bottom: 1px solid var(--borde);
}
a { color: var(--acento); }
.sub { color: var(--tenue); margin: 0 0 1.5rem; }
.nota {
    background: var(--tarjeta);
    border-left: 3px solid var(--acento);
    padding: .7rem .9rem;
    margin: 1.2rem 0 2rem;
    color: var(--tenue);
    font-size: .88rem;
    border-radius: 0 4px 4px 0;
}
.rejilla {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1.2rem;
    margin-top: 1.2rem;
}
.tarjeta {
    background: var(--tarjeta);
    border: 1px solid var(--borde);
    border-radius: 6px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
}
.tarjeta img { display: block; width: 100%; height: auto; background: #000; }
.cuerpo { padding: .75rem .9rem .9rem; }
.producto { font-weight: 600; margin-bottom: .15rem; }
.dato { color: var(--tenue); font-size: .85rem; }
.paleta {
    margin-top: .6rem;
    padding-top: .55rem;
    border-top: 1px solid var(--borde);
    color: var(--tenue);
    font-size: .8rem;
}
.paleta .rango { color: var(--texto); }
.clases { list-style: none; margin: .35rem 0 0; padding: 0; }
.clases li { display: flex; align-items: center; gap: .4rem; line-height: 1.5; }
.muestra {
    width: .8rem; height: .8rem;
    border: 1px solid var(--borde);
    border-radius: 2px;
    flex: none;
}
.descarga { display: block; margin-top: .7rem; font-size: .85rem; }
.tabla { border-collapse: collapse; margin-top: 1.2rem; width: 100%; }
.tabla td { padding: .5rem .2rem; border-bottom: 1px solid var(--borde); }
.tabla td:last-child { text-align: right; color: var(--tenue); }
.aviso { color: var(--tenue); font-size: .85rem; margin-top: 2.5rem; }
"""

CABECERA = """\
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titulo}</title>
<link rel="stylesheet" href="{css}">
"""


def _esc(texto):
    return html.escape(str(texto), quote=True)


def html_ficha(ficha, categoria_dir):
    """Una tarjeta: miniatura enlazada, ficha y enlace de descarga."""
    completa = _esc(ficha.nombre)
    mini = _esc(os.path.join("miniaturas", ficha.nombre))

    detalle = [f"{ficha.utc} ({ficha.local} local)"]
    if ficha.resolucion:
        detalle.append(ficha.resolucion)

    partes = [
        '<article class="tarjeta">',
        f'  <a href="{completa}"><img src="{mini}" alt="{_esc(ficha.producto)}" loading="lazy"></a>',
        '  <div class="cuerpo">',
        f'    <div class="producto">{_esc(ficha.producto)}</div>',
    ]
    if ficha.origen:
        partes.append(f'    <div class="dato">{_esc(ficha.origen)}</div>')
    partes.append(f'    <div class="dato">{_esc(" · ".join(detalle))}</div>')

    if ficha.paleta:
        partes.append('    <div class="paleta">')
        if ficha.paleta.descripcion:
            partes.append(f'      {_esc(ficha.paleta.descripcion)}<br>')
        if ficha.paleta.rango:
            partes.append(f'      Paleta <span class="rango">{_esc(ficha.paleta.rango)}</span> '
                          f'<span>({_esc(ficha.paleta.cpt)})</span>')
        if ficha.paleta.clases:
            partes.append(f'      Clases ({_esc(ficha.paleta.cpt)}):')
            partes.append('      <ul class="clases">')
            for valor, etiqueta, (r, g, b) in ficha.paleta.clases:
                muestra = f'background: rgb({r},{g},{b})'
                partes.append(f'        <li><span class="muestra" style="{muestra}"></span>'
                              f'{valor} — {_esc(etiqueta)}</li>')
            partes.append('      </ul>')
        partes.append('    </div>')
    elif ficha.nota_dnb:
        partes.append(f'    <div class="paleta">{NOTA_DNB}</div>')

    pie = [ficha.peso]
    if ficha.dimensiones:
        pie.append(ficha.dimensiones)
    partes.append(f'    <a class="descarga" href="{completa}" download>'
                  f'⬇ Descargar JPG completo ({_esc(" · ".join(pie))})</a>')
    partes.append('  </div>')
    partes.append('</article>')
    return "\n".join(partes)


def escribir_categoria(destino, categoria, titulo, fichas_por_pasada, lleva_paletas):
    """La página de una categoría: las tarjetas, agrupadas por pasada."""
    cuerpo = [CABECERA.format(titulo=_esc(titulo), css="../estilo.css"),
              '<main>',
              f'<h1>{_esc(titulo)}</h1>',
              '<p class="sub"><a href="../index.html">← Todas las categorías</a></p>']

    if lleva_paletas:
        cuerpo.append(f'<p class="nota">{NOTA_PALETAS}</p>')

    for pasada, fichas in fichas_por_pasada:
        cuerpo.append(f'<h2>{_esc(pasada.titulo)}</h2>')
        cuerpo.append('<div class="rejilla">')
        for ficha in fichas:
            cuerpo.append(html_ficha(ficha, categoria))
        cuerpo.append('</div>')

    cuerpo.append('</main>')

    ruta = os.path.join(destino, categoria, "index.html")
    with open(ruta, "w", encoding="utf-8") as fh:
        fh.write("\n".join(cuerpo) + "\n")


def copiar_anexo(destino, ruta, titulo):
    """Copia un directorio ya armado dentro de la galería y devuelve su enlace.

    Sirve para colgar de la galería material que no sale de la cadena — una
    comparativa de paletas, una nota— sin que este script tenga que saber nada
    de su contenido. La única exigencia es que traiga su propio index.html y
    que sea autocontenido, igual que el resto: nada de rutas absolutas.
    """
    nombre = os.path.basename(os.path.normpath(ruta))
    if not os.path.isfile(os.path.join(ruta, "index.html")):
        raise SystemExit(f"ERROR: el anexo {ruta} no tiene index.html")
    shutil.copytree(ruta, os.path.join(destino, nombre), dirs_exist_ok=True)
    return nombre, titulo


def escribir_indice(destino, pasadas, resumen_categorias, generado, anexos=()):
    """El índice raíz: las pasadas publicadas y las categorías, con su conteo."""
    titulo = "Vistas VIIRS — LANOT/UNAM"
    cuerpo = [CABECERA.format(titulo=_esc(titulo), css="estilo.css"),
              '<main>',
              f'<h1>{_esc(titulo)}</h1>']

    detalle = "; ".join(f"{p.titulo} — {n} vista{'s' if n != 1 else ''}" for p, n in pasadas)
    cuerpo.append(f'<p class="sub">{_esc(detalle)}</p>')
    cuerpo.append(f'<p class="nota">{NOTA_PALETAS}</p>')

    cuerpo.append('<table class="tabla">')
    for categoria, titulo_cat, cuenta in resumen_categorias:
        cuerpo.append(f'  <tr><td><a href="{_esc(categoria)}/index.html">'
                      f'{_esc(titulo_cat)}</a></td>'
                      f'<td>{cuenta} vista{"s" if cuenta != 1 else ""}</td></tr>')
    cuerpo.append('</table>')

    if anexos:
        cuerpo.append('<h2>Además</h2>')
        cuerpo.append('<table class="tabla">')
        for enlace, titulo in anexos:
            cuerpo.append(f'  <tr><td><a href="{_esc(enlace)}/index.html">'
                          f'{_esc(titulo)}</a></td><td>anexo</td></tr>')
        cuerpo.append('</table>')

    cuerpo.append(f'<p class="aviso">Generado el {generado}. '
                  'Las imágenes son las vistas decoradas de la cadena operativa de satélites '
                  'polares JPSS del LANOT-UNAM.</p>')
    cuerpo.append('</main>')

    with open(os.path.join(destino, "index.html"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(cuerpo) + "\n")


# ==============================================================================
# PUBLICACIÓN
# ==============================================================================

def miniatura(origen, salida, lado):
    with Image.open(origen) as img:
        img = img.convert("RGB")
        img.thumbnail((lado, lado), Image.LANCZOS)
        img.save(salida, "JPEG", quality=82, optimize=True)


def publicar(destino, pasadas, paletas, tz_offset, lado, anexos_pedidos=()):
    """Copia, redimensiona y escribe el HTML. Devuelve el resumen."""
    os.makedirs(destino, exist_ok=True)
    with open(os.path.join(destino, "estilo.css"), "w", encoding="utf-8") as fh:
        fh.write(ESTILO)

    resumen_categorias, sin_producto, copiadas = [], [], 0
    cuenta_por_pasada = {p.clave: 0 for p in pasadas}

    for categoria, titulo in CATEGORIAS:
        fichas_por_pasada, total, lleva_paletas = [], 0, False

        for pasada in pasadas:
            fichas = [Ficha(v, paletas, tz_offset)
                      for v in pasada.vistas if v.categoria == categoria]
            if fichas:
                fichas_por_pasada.append((pasada, fichas))
                total += len(fichas)
                cuenta_por_pasada[pasada.clave] += len(fichas)
                lleva_paletas = lleva_paletas or any(f.paleta for f in fichas)

        if not total:
            continue

        dir_cat = os.path.join(destino, categoria)
        dir_mini = os.path.join(dir_cat, "miniaturas")
        os.makedirs(dir_mini, exist_ok=True)

        for _, fichas in fichas_por_pasada:
            for ficha in fichas:
                # Copia real y no enlace: es lo que hace portátil a la carpeta.
                shutil.copy2(ficha.vista.ruta, os.path.join(dir_cat, ficha.nombre))
                miniatura(ficha.vista.ruta, os.path.join(dir_mini, ficha.nombre), lado)
                copiadas += 1
                if ficha.sin_producto:
                    sin_producto.append(ficha.nombre)

        escribir_categoria(destino, categoria, titulo, fichas_por_pasada, lleva_paletas)
        resumen_categorias.append((categoria, titulo, total))

    # datetime.now(timezone.utc) y no utcnow(): el venv del contenedor se
    # construye sobre el python3 de Rocky 8, así que el código tiene que ser
    # conservador, y utcnow() además está deprecado en los intérpretes nuevos.
    anexos = [copiar_anexo(destino, ruta, titulo)
              for ruta, titulo in anexos_pedidos]

    generado = datetime.now(timezone.utc).strftime("%Y/%m/%d %H:%M") + "Z"
    escribir_indice(destino,
                    [(p, cuenta_por_pasada[p.clave]) for p in pasadas],
                    resumen_categorias, generado, anexos)

    return resumen_categorias, copiadas, sin_producto, anexos


# ==============================================================================
# PRINCIPAL
# ==============================================================================

def main():
    ap = argparse.ArgumentParser(
        description="Arma una galería web autocontenida a partir del árbol de vistas.")
    ap.add_argument("--vistas", default="/vistas", help="Raíz del árbol de vistas")
    ap.add_argument("--destino", default="/publicacion", help="Carpeta de salida")
    ap.add_argument("--colortables", default="/usr/local/share/lanot/colortables",
                    help="Directorio de las CPT")
    ap.add_argument("--script-edr", default=None,
                    help="run_polar2grid_edr.sh, de donde se lee la tabla PALETAS")
    ap.add_argument("--ultimas", type=int, default=2,
                    help="Cuántas pasadas, de la más reciente hacia atrás (def. 2)")
    ap.add_argument("--pasada", action="append", default=[], metavar="AAAAMMDD_HH",
                    help="Fija una pasada por prefijo de sello. Repetible; anula --ultimas")
    ap.add_argument("--hueco-min", type=int, default=45,
                    help="Minutos de hueco que separan dos pasadas (def. 45)")
    ap.add_argument("--tz-offset", type=float, default=-6.0,
                    help="Horas respecto de UTC para la hora local (def. -6)")
    ap.add_argument("--miniatura", type=int, default=480,
                    help="Lado mayor de las miniaturas, en píxeles (def. 480)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Enseña qué publicaría y no escribe nada")
    ap.add_argument("--anexo", action="append", default=[], metavar="RUTA:TÍTULO",
                    help="Cuelga de la galería un directorio ya armado, con su "
                         "propio index.html. Repetible")
    args = ap.parse_args()

    anexos_pedidos = []
    for spec in args.anexo:
        # partition y no rpartition: se parte por el PRIMER dos puntos. La
        # versión anterior partía por el último, con el argumento de que una
        # ruta puede llevar ':' y un título no; el primer título real que se le
        # pasó lo desmintió ("Paletas de nubes: comparativa y presión de tope"),
        # y una ruta con dos puntos es mucho más rara que un título con ellos.
        ruta, _, titulo = spec.partition(":")
        if not ruta or not titulo:
            print(f"ERROR: --anexo mal formado: {spec!r} (se espera RUTA:TÍTULO)",
                  file=sys.stderr)
            return 1
        if not os.path.isdir(ruta):
            print(f"ERROR: el anexo no existe: {ruta}", file=sys.stderr)
            return 1
        anexos_pedidos.append((ruta, titulo))

    script_edr = args.script_edr or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "run_polar2grid_edr.sh")

    if not os.path.isdir(args.vistas):
        print(f"ERROR: no existe el árbol de vistas: {args.vistas}", file=sys.stderr)
        return 1

    vistas, sin_sello = descubrir(args.vistas)
    if not vistas:
        print(f"ERROR: no hay ningún JPG con sello temporal bajo {args.vistas}", file=sys.stderr)
        return 1

    grupos = agrupar(vistas, args.hueco_min)
    pasadas = [Pasada(g, args.tz_offset) for g in grupos]

    if args.pasada:
        elegidas = [p for p in pasadas if any(p.clave.startswith(pre) for pre in args.pasada)]
        if not elegidas:
            print(f"ERROR: ningún grupo empieza por {', '.join(args.pasada)}. "
                  f"Los que hay: {', '.join(p.clave for p in pasadas)}", file=sys.stderr)
            return 1
    else:
        elegidas = pasadas[-args.ultimas:]

    elegidas.sort(key=lambda p: p.inicio, reverse=True)

    print(f"Pasadas encontradas: {len(pasadas)} · seleccionadas: {len(elegidas)}")
    for pasada in elegidas:
        por_categoria = {}
        for vista in pasada.vistas:
            por_categoria[vista.categoria] = por_categoria.get(vista.categoria, 0) + 1
        detalle = ", ".join(f"{c} {n}" for c, n in sorted(por_categoria.items()))
        print(f"  · {pasada.titulo} — {len(pasada.vistas)} vistas ({detalle})")

    if sin_sello:
        print(f"  ⚠ {len(sin_sello)} archivo(s) sin sello temporal, ignorados")

    if args.dry_run:
        print("\n--dry-run: no se escribió nada.")
        for pasada in elegidas:
            for vista in pasada.vistas:
                print(f"    {vista.categoria}/{vista.nombre}")
        return 0

    paletas = Paletas(script_edr, args.colortables)
    if not paletas.tabla:
        print(f"  ⚠ no se pudo leer la tabla PALETAS de {script_edr}: "
              "las fichas saldrán sin nota de paleta")

    resumen, copiadas, sin_producto, anexos = publicar(
        args.destino, elegidas, paletas, args.tz_offset, args.miniatura,
        anexos_pedidos)

    print(f"\nPublicadas {copiadas} vistas en {len(resumen)} categorías:")
    for categoria, titulo, cuenta in resumen:
        print(f"  · {categoria}: {cuenta}")
    for enlace, titulo in anexos:
        print(f"  · anexo {enlace}/: {titulo}")

    if sin_producto:
        print(f"\n  ⚠ {len(sin_producto)} vista(s) sin nombre de producto — les falta su "
              "entrada en product_map de LANOT_tools/metadata.py:")
        for nombre in sin_producto:
            print(f"      {nombre}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
