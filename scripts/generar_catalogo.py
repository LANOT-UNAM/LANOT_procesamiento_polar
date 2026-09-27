#!/usr/bin/env python3
# ==============================================================================
# generar_catalogo.py — docs/catalogo_productos.tsv → docs/catalogo_productos.md
#
# El TSV es la fuente; el .md, lo que se lee. Se ejecuta desde la raíz del repo,
# como generar_xml.py:
#
#   python3 scripts/generar_catalogo.py               # regenera el .md
#   python3 scripts/generar_catalogo.py --verificar   # contrasta TSV ÷ código
#
# --verificar existe para que el catálogo no se quede atrás sin que nadie lo
# note. Revisa que:
#   · todo producto que los run_polar2grid_*.sh piden con -p tenga su fila, y
#     que ninguna fila pida algo que ya no se pide;
#   · la paleta de cada fila con vista sea la que le daría paleta_de() de
#     run_polar2grid_edr.sh, y que el CPT exista en LANOT_tools;
#   · cada fila con vista tenga su token en product_map de LANOT_tools, o la
#     imagen saldría sin nombre de producto;
#   · cada ruta sea un directorio que algún run_*.sh crea;
#   · el .md esté al día con el TSV.
# Sale en 1 con la lista de lo que no cuadra. LANOT_tools se busca en
# ~/lanot/LANOT_tools (override: LANOT_TOOLS); si no está, esas dos
# comprobaciones se avisan y se saltan.
#
# Solo biblioteca estándar: tiene que correr igual aquí que en tahan.
# ==============================================================================

import argparse
import os
import re
import sys
from collections import OrderedDict

TSV = "docs/catalogo_productos.tsv"
MD = "docs/catalogo_productos.md"
SCRIPTS = "scripts"
RENDERIZADORES = ["scripts/run_polar2grid_l1.sh", "scripts/run_polar2grid_edr.sh"]

COLUMNAS = ("id nombre nivel sensor satelites formato contenido resolucion ruta "
            "patron ruta_vista vista p2g origen depende_de notas").split()

NIVELES = OrderedDict([
    ("L1", "Level 1: SDR"),
    ("L2", "Level 2: productos geofísicos"),
    ("geotiff", "GeoTIFF en rejilla"),
    ("vista", "Vistas sin GeoTIFF propio"),
])

SATELITES = {"npp": "Suomi-NPP", "j01": "NOAA-20", "j02": "NOAA-21"}

NADA = "—"


def leer_tsv(ruta):
    filas = []
    cabecera = None
    with open(ruta, encoding="utf-8") as f:
        for n, linea in enumerate(f, 1):
            linea = linea.rstrip("\n")
            if not linea or linea.startswith("#"):
                continue
            campos = linea.split("\t")
            if cabecera is None:
                cabecera = campos
                if cabecera != COLUMNAS:
                    sys.exit(f"ERROR: {ruta}:{n}: las columnas no son las esperadas\n"
                             f"  esperadas: {' '.join(COLUMNAS)}\n"
                             f"  leídas:    {' '.join(cabecera)}")
                continue
            if len(campos) != len(COLUMNAS):
                sys.exit(f"ERROR: {ruta}:{n}: {len(campos)} campos, se esperaban {len(COLUMNAS)}")
            fila = dict(zip(COLUMNAS, campos))
            fila["_linea"] = n
            filas.append(fila)
    ids = [f["id"] for f in filas]
    repetidos = sorted({i for i in ids if ids.count(i) > 1})
    if repetidos:
        sys.exit(f"ERROR: ids repetidos en {ruta}: {', '.join(repetidos)}")
    for f in filas:
        if f["nivel"] not in NIVELES:
            sys.exit(f"ERROR: {ruta}:{f['_linea']}: nivel desconocido '{f['nivel']}'")
    return filas


# ------------------------------------------------------------------------------
# Página
# ------------------------------------------------------------------------------

def celda(texto):
    return texto.replace("|", "\\|")


def satelites_legibles(s):
    return ", ".join(SATELITES.get(x.strip(), x.strip()) for x in s.split(","))


def tiene_vista(f):
    return f["vista"] != NADA


def pendientes(f):
    """Columnas con algún '?': dato que falta verificar contra un archivo real."""
    return [c for c in COLUMNAS if "?" in f[c]]


def generar_md(filas):
    o = []
    w = o.append
    w("# Catálogo de productos de la cadena polar")
    w("")
    w(f"> Generado desde `{TSV}` con `scripts/generar_catalogo.py`. **No editar a mano**: "
      "los cambios van en el TSV.")
    w("")
    w("Productos que el LANOT genera a partir de la recepción directa de los satélites polares "
      "Suomi-NPP, NOAA-20 y NOAA-21, de Level 1 en adelante. Todas las rutas son relativas a "
      "`/data/output/jpss/`.")
    w("")
    w("- **Level 1 (SDR)**: radiancias calibradas y geolocalizadas, en la geometría del "
      "instrumento (swath), un archivo por gránulo o por pasada.")
    w("- **Level 2**: variables geofísicas calculadas con CSPP, también en swath.")
    w("- **GeoTIFF**: una selección de Level 1 y Level 2 remallada a una rejilla "
      "latitud-longitud fija (`config/grid.yaml`). Es **dato** (float32, sin realce), salvo "
      "donde se indica que es imagen.")
    w("- **Vista**: imagen decorada (JPG, o SVG en el Skew-T) para mirar, no para calcular. "
      "Solo llevan vista los productos que alguien mira.")
    w("")
    w("Una **pasada** es el conjunto de gránulos de un satélite sin huecos de más de 20 min. "
      "En los nombres de GeoTIFF y vistas el satélite va como `npp`, `noaa20` o `noaa21`; en "
      "los de CSPP, como `npp`, `j01` o `j02` (o `n20`/`n21` en algunos Level 2).")
    w("")

    w("## Resumen")
    w("")
    for nivel, titulo in NIVELES.items():
        del_nivel = [f for f in filas if f["nivel"] == nivel]
        if not del_nivel:
            continue
        w(f"### {titulo}")
        w("")
        w("| Producto | Sensor | Satélites | Formato | Vista |")
        w("|---|---|---|---|---|")
        for f in del_nivel:
            w(f"| [{celda(f['nombre'])}](#{f['id']}) | {celda(f['sensor'])} | "
              f"{celda(satelites_legibles(f['satelites']))} | {celda(f['formato'])} | "
              f"{'sí' if tiene_vista(f) else 'no'} |")
        w("")

    w("## Fichas")
    w("")
    for nivel, titulo in NIVELES.items():
        del_nivel = [f for f in filas if f["nivel"] == nivel]
        if not del_nivel:
            continue
        w(f"### {titulo}")
        w("")
        for f in del_nivel:
            w(f'<a id="{f["id"]}"></a>')
            w("")
            w(f"#### {f['nombre']}")
            w("")
            w(f"`{f['id']}` · {f['sensor']} · {satelites_legibles(f['satelites'])}")
            w("")
            w(f"- **Contenido**: {f['contenido']}")
            w(f"- **Formato**: {f['formato']}")
            w(f"- **Resolución**: {f['resolucion']}")
            if f["notas"] and f["notas"] != NADA:
                w(f"- **Notas**: {f['notas']}")
            w("")
            w("<details><summary>Para operación</summary>")
            w("")
            w(f"- Ruta: `{f['ruta']}` · patrón `{f['patron']}`")
            if tiene_vista(f):
                w(f"- Vista: `{f['ruta_vista']}` con `{f['vista']}`")
            w(f"- Origen: {f['origen']}")
            w(f"- Depende de: {f['depende_de']}")
            if f["p2g"] != NADA:
                w(f"- Polar2Grid `-p`: `{f['p2g']}`")
            w("")
            w("</details>")
            w("")

    con_pendientes = [f for f in filas if pendientes(f)]
    if con_pendientes:
        w("## Por verificar")
        w("")
        w("Los `?` marcan datos que faltan confirmar contra un archivo real en tahan "
          "(`ncdump -h`, `gdalinfo`), en vez de deducirlos:")
        w("")
        for f in con_pendientes:
            w(f"- [{celda(f['nombre'])}](#{f['id']}): {', '.join(pendientes(f))}")
        w("")
    return "\n".join(o)


# ------------------------------------------------------------------------------
# Verificación contra el código
# ------------------------------------------------------------------------------

ASIGNACION = re.compile(r'^\s*([A-Z][A-Z0-9_]*)="([^"]*)"')
VARIABLE = re.compile(r"\$\{?([A-Z][A-Z0-9_]*)\}?")


def productos_pedidos(ruta):
    """Productos que un renderizador pide con -p a polar2grid.sh.

    Sigue las asignaciones VAR="…" del script en orden, así que
    ATMOS_DATOS="$ATMOS_DATOS …" se acumula como en bash. Tras un -p se toman
    palabras hasta la primera bandera; una variable cuyo valor empieza con
    bandera (P2G_DATOS) también corta.
    """
    variables = {}
    pedidos = set()
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.lstrip().startswith("#"):
                continue
            m = ASIGNACION.match(linea)
            if m:
                variables[m.group(1)] = VARIABLE.sub(
                    lambda v: variables.get(v.group(1), v.group(0)), m.group(2))
                continue
            if "polar2grid.sh" not in linea:
                continue
            palabras = linea.replace('"', " ").split()
            i = 0
            while i < len(palabras):
                if palabras[i] != "-p":
                    i += 1
                    continue
                i += 1
                while i < len(palabras):
                    p = palabras[i]
                    m = VARIABLE.fullmatch(p)
                    valor = variables.get(m.group(1), "").split() if m else [p]
                    if not valor or valor[0].startswith(("-", "$")):
                        break
                    pedidos.update(x for x in valor if not x.startswith(("-", "$")))
                    i += 1
    return pedidos


def paletas_de_render(ruta):
    """Los pares clave:cpt de PALETAS=( … ) en run_polar2grid_edr.sh, en orden."""
    pares = []
    dentro = False
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            s = linea.strip()
            if s.startswith("PALETAS=("):
                dentro = True
                continue
            if dentro:
                if s.startswith(")"):
                    break
                m = re.match(r'^"([^":]+):([^"]+)"', s)
                if m:
                    pares.append((m.group(1), m.group(2)))
    return pares


def paleta_de(nombre, pares):
    for clave, cpt in pares:
        if clave in nombre:
            return cpt
    return None


def claves_product_map(ruta):
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    ini = texto.find("product_map = [")
    if ini < 0:
        return None
    fin = texto.find("]\n", ini)
    return re.findall(r"^\s*\('([^']+)',", texto[ini:fin], re.M)


def directorios_creados():
    """Directorios de /data/output/jpss que nombra algún script de scripts/."""
    dirs = set()
    for nombre in sorted(os.listdir(SCRIPTS)):
        if not nombre.endswith(".sh"):
            continue
        with open(os.path.join(SCRIPTS, nombre), encoding="utf-8") as f:
            texto = f.read()
        for m in re.finditer(r"/data/output/jpss/([A-Za-z0-9_/]+)", texto):
            dirs.add(m.group(1).strip("/"))
        for m in re.finditer(r'\$(GEOTIFF|VISTAS)/([a-z_/]+)', texto):
            dirs.add(f"{m.group(1).lower()}/{m.group(2).strip('/')}")
    return dirs


def verificar(filas):
    faltas = []
    avisos = []

    # 1. -p de los renderizadores ÷ columna p2g
    pedidos = set()
    for r in RENDERIZADORES:
        pedidos |= productos_pedidos(r)
    en_tsv = {}
    for f in filas:
        if f["p2g"] != NADA:
            for p in f["p2g"].split():
                en_tsv[p] = f["id"]
    for p in sorted(pedidos - en_tsv.keys()):
        faltas.append(f"Polar2Grid produce '{p}' y ninguna fila lo declara en p2g")
    for p in sorted(en_tsv.keys() - pedidos):
        faltas.append(f"{en_tsv[p]}: declara '{p}' en p2g y ningún renderizador lo pide")

    # 2. Paleta de cada vista geotiff2view = la que elegiría paleta_de()
    pares = paletas_de_render("scripts/run_polar2grid_edr.sh")
    lanot_tools = os.environ.get("LANOT_TOOLS", os.path.expanduser("~/lanot/LANOT_tools"))
    dir_cpt = os.path.join(lanot_tools, "colortables")
    for f in filas:
        if not f["vista"].endswith(".cpt"):
            continue
        nombre = f["patron"].replace("{sat}", "noaa21")
        esperada = paleta_de(nombre, pares)
        if esperada != f["vista"]:
            faltas.append(f"{f['id']}: vista con {f['vista']}, pero run_polar2grid_edr.sh "
                          f"le daría {esperada or 'ninguna (sin vista)'}")
        if os.path.isdir(dir_cpt) and not os.path.isfile(os.path.join(dir_cpt, f["vista"])):
            faltas.append(f"{f['id']}: {f['vista']} no está en {dir_cpt}")
    if not os.path.isdir(dir_cpt):
        avisos.append(f"no está {dir_cpt}: no se comprobó que existan los CPT")

    # 3. product_map: la etiqueta de cada vista
    metadata = os.path.join(lanot_tools, "metadata.py")
    claves = claves_product_map(metadata) if os.path.isfile(metadata) else None
    if claves is None:
        avisos.append(f"no se pudo leer product_map de {metadata}: no se comprobaron las etiquetas")
    else:
        for f in filas:
            if f["vista"] in (NADA, "skewt"):
                continue
            nombre = (f["ruta_vista"] + f["patron"]).lower()
            if not any(c in nombre for c in claves):
                faltas.append(f"{f['id']}: ninguna clave de product_map aparece en "
                              f"'{f['patron']}': la vista saldría sin nombre de producto")

    # 4. Rutas
    dirs = directorios_creados()
    for f in filas:
        for col in ("ruta", "ruta_vista"):
            if f[col] != NADA and f[col].strip("/") not in dirs:
                faltas.append(f"{f['id']}: {col} '{f[col]}' no la crea ningún script de {SCRIPTS}/")

    # 5. El .md al día
    if not os.path.isfile(MD):
        faltas.append(f"no existe {MD}: correr sin --verificar para generarlo")
    else:
        with open(MD, encoding="utf-8") as fh:
            if fh.read() != generar_md(filas) + "\n":
                faltas.append(f"{MD} no está al día con {TSV}: regenerar")

    for a in avisos:
        print(f"  ⚠ {a}")
    n_pend = sum(1 for f in filas if pendientes(f))
    if n_pend:
        print(f"  · {n_pend} productos con datos por verificar (?) — ver el final de {MD}")
    if faltas:
        print(f"❌ El catálogo no cuadra con el código ({len(faltas)}):")
        for x in faltas:
            print(f"  - {x}")
        return 1
    print(f"✅ Catálogo al día: {len(filas)} productos, {len(pedidos)} productos de Polar2Grid cubiertos")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Genera o verifica el catálogo de productos.")
    ap.add_argument("--verificar", action="store_true",
                    help="contrasta el TSV contra los scripts y LANOT_tools, sin escribir")
    args = ap.parse_args()

    if not os.path.isfile(TSV):
        sys.exit(f"ERROR: no encuentro {TSV}; ejecutar desde la raíz del repo")
    filas = leer_tsv(TSV)

    if args.verificar:
        sys.exit(verificar(filas))

    with open(MD, "w", encoding="utf-8") as f:
        f.write(generar_md(filas) + "\n")
    print(f"✅ {MD}: {len(filas)} productos")


if __name__ == "__main__":
    main()
