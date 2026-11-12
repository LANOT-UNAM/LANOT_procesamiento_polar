#!/bin/bash
# Regenera docs/resumen_procesamiento_polar.pdf: el resumen del proyecto para
# mandar fuera (descripción, diagrama, productos, software, estado), sin rutas
# ni instrucciones de operación. El PDF no se versiona; estas fuentes sí.
#
# Necesita mmdc (mermaid-cli), reportlab, pypdf y las fuentes DejaVu.
# puppeteer.json apunta mmdc al Chrome del sistema; si en otra máquina está en
# otro lado, ajustar executablePath.
#
#   docs/resumen/generar.sh [salida.pdf]
#
# Al cambiar el diagrama (cadena.mmd), mirar el PDF antes de darlo por bueno:
# los defectos de un Mermaid no se ven leyendo el texto.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALIDA="${1:-$AQUI/../resumen_procesamiento_polar.pdf}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mmdc -p "$AQUI/puppeteer.json" -i "$AQUI/cadena.mmd" -o "$TMP/cadena.pdf" -f -b white
python3 "$AQUI/texto.py" "$TMP/texto.pdf"
python3 "$AQUI/ensamblar.py" "$TMP/cadena.pdf" "$TMP/texto.pdf" "$SALIDA"
