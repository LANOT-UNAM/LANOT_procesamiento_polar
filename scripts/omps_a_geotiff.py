#!/usr/bin/env python3
# ==============================================================================
# omps_a_geotiff.py — V8TOZ de CSPP OMPS EDR → GeoTIFF float32 en una rejilla
#
# Corre DENTRO de polar2grid_v3.2-mapdrawer.sif, con el intérprete del bundle de
# Polar2Grid, que es el que trae rasterio y netCDF4:
#
#   /opt/polar2grid/libexec/python_runtime/bin/python3 omps_a_geotiff.py \
#       --grid-config /config/grid.yaml --grid wgs84_geo_5km -o /salida V8TOZ-EDR_*.nc
#
# POR QUÉ NO POLAR2GRID: el lector de OMPS llega en Polar2Grid 3.3 y tenemos la
# 3.2. El `omps_edr` de Satpy que ya trae el bundle es para los productos de
# NASA (TC_EDR_TO3-*.h5) y exige la órbita en el nombre del archivo, que los de
# CSPP no llevan. Este script ocupa el lugar que ocuparía `polar2grid.sh -w
# geotiff`: entrega el dato en la rejilla y nada más; la vista la hace
# geotiff2view, como con el resto de Level 2. El día que llegue la 3.3 se borra.
#
# POR QUÉ SE RASTERIZA LA HUELLA Y NO VECINO MÁS CERCANO: el pixel de OMPS
# cambia mucho según el satélite —177 columnas en NOAA-21, 139 en NOAA-20, 35 en
# NPP (tahan, 2026-09-22)— y dentro del swath crece del nadir al borde (18 → 49
# km en NOAA-20). Un radio de influencia que llene los bordes de NPP embarra
# los de NOAA-21. El archivo trae las cuatro esquinas de cada pixel, en orden
# y con orientación consistente (verificado en los tres satélites), así que
# cada pixel se pinta con su huella real y no hay radio que ajustar.
#
# QUÉ SE ENMASCARA: el relleno (-9999) y lo que está fuera de valid_range, que
# netCDF4 ya enmascara solo, y además ErrorFlag = 7. Esa bandera junta
# EXACTAMENTE los valores absurdos: sobre 409 mil pixeles de nueve pasadas, los
# 8 con ErrorFlag = 7 —todos de NPP— dieron 4 a 80 DU, y los demás códigos (0,
# 1, 4, 5) valores físicos de 242 a 332 DU. QualityFlag no discrimina nada:
# vale 0 en todos.
#
# Salida: <sat>_omps_ColumnAmountO3_<AAAAMMDD_HHMMSS>_<rejilla>.tif, con la forma
# de nombre de Polar2Grid (satélite primero, sello del primer gránulo) para que
# metadata.py de LANOT_tools lo reconozca igual que a los demás. El TIFF lleva
# la etiqueta `product`, que geotiff2view lee antes que el nombre del archivo.
#
# Códigos de salida, los mismos que geotiff2view: 0 escribió el GeoTIFF, 3 no
# había un solo pixel válido (y no escribe nada), 1 error.
# ==============================================================================

import argparse
import glob
import math
import os
import sys
from datetime import datetime

import netCDF4
import numpy as np
import rasterio
import rasterio.features
import yaml
from rasterio.transform import from_origin

SIN_DATOS = 3

# Cómo nombra CSPP OMPS al satélite (n21, no j02 como los SDR) → cómo lo
# nombra Polar2Grid en sus salidas.
SATELITES = {"npp": "npp", "j01": "noaa20", "n20": "noaa20", "j02": "noaa21", "n21": "noaa21"}

ERROR_FLAG_MALO = 7

ETIQUETAS = {
    "ColumnAmountO3": "Total Ozone",
}


def resolucion(grid_config, grid):
    with open(grid_config) as f:
        rejillas = yaml.safe_load(f)
    if grid not in rejillas:
        sys.exit(f"ERROR: la rejilla {grid} no está en {grid_config}")
    r = rejillas[grid]
    if r.get("projection", {}).get("EPSG") != 4326:
        sys.exit(f"ERROR: {grid} no es EPSG:4326; este script solo sabe de lat/lon")
    return float(r["resolution"]["dx"]), float(r["resolution"]["dy"])


def satelite_de(nombre):
    # V8TOZ-EDR_v4r5_n21_s202609222014368_e..._c....nc
    partes = nombre.split("_")
    if len(partes) < 3 or partes[2] not in SATELITES:
        sys.exit(f"ERROR: no reconozco el satélite en {nombre}")
    return SATELITES[partes[2]]


def leer(archivo, variable):
    """Polígonos (lista de anillos lon/lat) y valores válidos de un gránulo."""
    with netCDF4.Dataset(archivo) as d:
        valor = d[variable][:]
        lat = d["LatitudeCorners"][:]
        lon = d["LongitudeCorners"][:]
        error = d["ErrorFlag"][:]
        inicio = d.getncattr("time_coverage_start")

    malo = np.ma.getmaskarray(valor)
    malo |= np.ma.getmaskarray(lat).any(axis=-1) | np.ma.getmaskarray(lon).any(axis=-1)
    malo |= np.ma.filled(error, 0) >= ERROR_FLAG_MALO
    bien = ~malo
    return (np.ma.getdata(lon)[bien], np.ma.getdata(lat)[bien],
            np.ma.getdata(valor)[bien].astype(np.float32), inicio)


def main():
    p = argparse.ArgumentParser(description="V8TOZ de CSPP OMPS → GeoTIFF float32")
    p.add_argument("archivos", nargs="+", help="V8TOZ-EDR_*.nc de UNA pasada")
    p.add_argument("-o", "--salida", required=True, help="directorio de salida")
    p.add_argument("--grid-config", required=True, help="config/grid.yaml")
    p.add_argument("--grid", default="wgs84_geo_5km")
    p.add_argument("--variable", default="ColumnAmountO3")
    args = p.parse_args()

    archivos = sorted(f for a in args.archivos for f in glob.glob(a))
    if not archivos:
        sys.exit("ERROR: no hay archivos V8TOZ que convertir")
    satelites = {satelite_de(os.path.basename(f)) for f in archivos}
    if len(satelites) != 1:
        sys.exit(f"ERROR: archivos de más de un satélite: {sorted(satelites)}")
    sat = satelites.pop()

    dx, dy = resolucion(args.grid_config, args.grid)

    lons, lats, valores, inicios = [], [], [], []
    for f in archivos:
        lo, la, v, ini = leer(f, args.variable)
        lons.append(lo); lats.append(la); valores.append(v); inicios.append(ini)
    lon = np.concatenate(lons)
    lat = np.concatenate(lats)
    valor = np.concatenate(valores)
    print(f"{len(archivos)} gránulos, {valor.size} pixeles válidos de {args.variable}")

    if valor.size == 0:
        print("Sin un solo pixel válido: no se escribe GeoTIFF")
        return SIN_DATOS

    # Extensión: la de las huellas, ajustada hacia afuera a múltiplos de la
    # resolución para que dos pasadas en la misma rejilla caigan en la misma malla.
    oeste = math.floor(lon.min() / dx) * dx
    este = math.ceil(lon.max() / dx) * dx
    sur = math.floor(lat.min() / dy) * dy
    norte = math.ceil(lat.max() / dy) * dy
    ancho = int(round((este - oeste) / dx))
    alto = int(round((norte - sur) / dy))
    transform = from_origin(oeste, norte, dx, dy)

    poligonos = (
        ({"type": "Polygon",
          "coordinates": [[(float(x[i]), float(y[i])) for i in (0, 1, 2, 3, 0)]]}, float(v))
        for x, y, v in zip(lon, lat, valor)
    )
    # all_touched: sin él, una celda cuyo centro cae en la rendija entre dos
    # huellas vecinas —que no comparten las esquinas al milímetro— se queda sin
    # pintar, y la vista sale salpicada de puntos negros y con una costura entre
    # gránulos (tahan, 2026-09-22, en los tres satélites). El precio es que el
    # borde del swath crece a lo más una celda.
    rejilla = rasterio.features.rasterize(
        poligonos, out_shape=(alto, ancho), transform=transform,
        fill=np.nan, dtype="float32", all_touched=True)

    # Sello del primer gránulo, como Polar2Grid: AAAAMMDD_HHMMSS
    sello = min(datetime.strptime(i, "%Y-%m-%dT%H:%M:%SZ") for i in inicios)
    nombre = f"{sat}_omps_{args.variable}_{sello:%Y%m%d_%H%M%S}_{args.grid}.tif"
    destino = os.path.join(args.salida, nombre)

    perfil = dict(driver="GTiff", width=ancho, height=alto, count=1, dtype="float32",
                  crs="EPSG:4326", transform=transform, nodata=np.nan,
                  compress="deflate", tiled=True, blockxsize=256, blockysize=256)
    with rasterio.open(destino, "w", **perfil) as dst:
        dst.write(rejilla, 1)
        dst.update_tags(product=ETIQUETAS.get(args.variable, args.variable))

    pintados = int(np.isfinite(rejilla).sum())
    print(f"{destino}: {ancho} × {alto}, {pintados} celdas con dato, "
          f"{np.nanmin(rejilla):.1f} a {np.nanmax(rejilla):.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
