#!/usr/bin/env python3
# ==============================================================================
# metop_l1b_para_mirs.py — copia de trabajo de un par AMSU-A/MHS 1b de AAPP
# en la forma que CSPP MiRS 4.0 sabe leer.
#
# MiRS no lee los .l1b por su nombre de archivo sino por el nombre de conjunto
# de datos que AAPP escribe en la cabecera (LNT.AMAX.MC.D26324.S1521.E1530…),
# y de ahí salen dos tropiezos con los l1b de esta cadena:
#
#   1. El código de sitio. AAPP lo compila (--site-id, SITE_ID=LNT en
#      aapp_v8.15.def, como en stratus) y lo escribe al inicio de la cabecera y
#      al inicio de ese nombre. El driver de MiRS solo deja pasar los que
#      empiezan con SSE (el de SSEC, que lo distribuye) o NSS (NOAA): con LNT
#      no copia nada al directorio del gránulo y el script de MiRS muere con
#      "Error: date xxxx-xx-xx is incorrect", mientras el driver sale en 0
#      (tahan, 2026-11-20). Aquí se pone SSE, que es el camino de recepción
#      directa del driver (lo renombra él a NSS).
#
#   2. La hora del MHS. El script de MiRS busca el MHS armando su nombre con el
#      del AMSU-A y la HORA de inicio (S14*). MHS y AMSU-A no empiezan en el
#      mismo minuto, y si caen a los dos lados de una hora no se encuentran:
#      "ERROR: No mhs SDR data files found" con AMSU-A S1459 y MHS S1500
#      (METOP-B, 2026-11-20 14:59). Se le pone al MHS el .S….E…. del AMSU-A.
#      Es solo la etiqueta: los tiempos de cada línea, que son los que MiRS usa
#      para colocar un sensor sobre el otro, no se tocan.
#
# Los archivos originales no se modifican: se escriben copias en el directorio
# de salida, con el mismo nombre de archivo.
#
# Uso:
#   metop_l1b_para_mirs.py <amsual1b> <mhsl1b> <directorio_de_salida>
#
# Sale en 1 si una cabecera no es la esperada (no empieza con un código de tres
# letras ni trae el nombre de conjunto de datos), en vez de copiar a ciegas.
# ==============================================================================

import os
import re
import sys

SITIO_MIRS = b"SSE"
NOMBRE = re.compile(rb"([A-Z]{3})\.(AMAX|MHSX)\.M[A-C]\.D\d{5}(\.S\d{4}\.E\d{4}\.)B\d+")


def leer(ruta):
    datos = bytearray(open(ruta, "rb").read())
    cabecera = bytes(datos[:80])
    m = NOMBRE.search(cabecera)
    if not m or cabecera[:3] != m.group(1):
        sys.exit(f"ERROR: cabecera inesperada en {ruta}: {cabecera[:64]!r}")
    datos[0:3] = SITIO_MIRS
    datos[m.start(1):m.end(1)] = SITIO_MIRS
    return datos, m


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__ or "uso: metop_l1b_para_mirs.py <amsual1b> <mhsl1b> <salida>")
    amsua, mhs, salida = sys.argv[1:4]

    d_amsua, m_amsua = leer(amsua)
    d_mhs, m_mhs = leer(mhs)
    if m_amsua.group(2) != b"AMAX" or m_mhs.group(2) != b"MHSX":
        sys.exit(f"ERROR: se esperaba AMSU-A y MHS, en ese orden: {amsua} {mhs}")

    horas_amsua = m_amsua.group(3)
    if m_mhs.group(3) != horas_amsua:
        d_mhs[m_mhs.start(3):m_mhs.end(3)] = horas_amsua

    for ruta, datos in ((amsua, d_amsua), (mhs, d_mhs)):
        with open(os.path.join(salida, os.path.basename(ruta)), "wb") as f:
            f.write(datos)

    print(f"AMSU-A: {bytes(d_amsua[m_amsua.start():m_amsua.end()]).decode()}")
    print(f"MHS:    {bytes(d_mhs[m_mhs.start():m_mhs.end()]).decode()}"
          + ("" if m_mhs.group(3) == horas_amsua else
             f"  (era {m_mhs.group(3).decode().strip('.')})"))


if __name__ == "__main__":
    main()
