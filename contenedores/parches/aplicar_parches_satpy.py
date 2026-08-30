#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Parches al Satpy que viene dentro del bundle de Polar2Grid 3.2.

El bundle lleva su propio runtime de Python con satpy 0.59.1.dev110 congelado,
así que nada de lo que se arregle aguas arriba nos llega hasta Polar2Grid 3.3.
Esto aplica lo que necesitamos mientras tanto.

Se ejecuta desde el %post de polar2grid_v3.2-mapdrawer.def, con el intérprete
del propio bundle y ANTES del calentamiento, para que el __pycache__ se genere
ya parcheado: la imagen no se puede reescribir después.

Cada parche declara el texto exacto que espera encontrar. Si el bundle cambia,
no se aplica a medias: falla con un mensaje que dice cuál y por qué, y con
'set -e' eso tumba la compilación. Es deliberado — un parche que se aplica a
medias en un lector es justo la clase de fallo que solo aparece en producción.

Uso:
    python aplicar_parches_satpy.py [<site-packages>] [--verificar]

Sin ruta, la deduce de 'import satpy'. Con --verificar no escribe nada: solo
comprueba si están puestos, que es lo que hace el %test.
"""

import io
import os
import sys

# (archivo relativo a site-packages, texto viejo, texto nuevo, por qué)
PARCHES = [
    (
        "satpy/readers/nucaps.py",
        '        valid_min, valid_max = self[var_path + "/attr/valid_range"]\n',
        '        valid_min, valid_max = self.get(var_path + "/attr/valid_range", (None, None))\n',
        "pytroll/satpy#3450 (mergeado 2026-08-26): los NUCAPS-EDR v3r2 no traen "
        "valid_range en H2O_MR y 17 productos más. Sin esto, la pasada entera "
        "muere aunque los Temperature_* carguen bien.",
    ),
    (
        "satpy/readers/nucaps.py",
        "        datasets_loaded = super(NUCAPSReader, self).load(\n"
        "            dataset_keys, previous_datasets=previous_datasets)\n",
        "        datasets_loaded = super(NUCAPSReader, self).load(\n"
        "            dataset_keys, previous_datasets=previous_datasets)\n"
        "        dataset_keys &= set(datasets_loaded.keys())\n",
        "pytroll/satpy#3450, segunda mitad: sin depurar la lista de productos "
        "pedidos con los que de verdad cargaron, el filtrado posterior busca el "
        "que faltó y tumba la corrida. Este es el que de verdad abortaba.",
    ),
    (
        "satpy/readers/nucaps.py",
        '        d_tmp = self[var_path]\n'
        '        if "index" in ds_info:\n'
        '            d_tmp = d_tmp[int(ds_info["index"])]\n',
        '        d_tmp = self[var_path]\n'
        '        if "index" in ds_info:\n'
        '            d_tmp = d_tmp[int(ds_info["index"])]\n'
        '        if "column_index" in ds_info:\n'
        '            # Some variables pack several unrelated parameters along the last\n'
        '            # dimension. NUCAPS "Stability" is one: 16 parameters per field of\n'
        '            # regard, of which index 0 is CAPE and index 9 is the Lifted Index.\n'
        '            # Unlike "pressure_index" this carries no pressure-level semantics.\n'
        '            d_tmp = d_tmp[..., int(ds_info["column_index"])]\n',
        "CAPE y Lifted Index: van empaquetados en la última dimensión de "
        "Stability, y el lector solo sabía indexar la primera ('index') o la "
        "última con semántica de presión ('pressure_index').",
    ),
    (
        "satpy/readers/nucaps.py",
        '        if fill_value is not None:\n'
        '            data = data.where(data != fill_value)\n',
        '        for extra_fill in ds_info.get("extra_fill_values", []):\n'
        '            # Some products leave sentinel values that do not match the\n'
        '            # declared _FillValue. NUCAPS initialises the "Stability" arrays\n'
        '            # with -999.0 and leaves non-retrievals at that value instead of\n'
        '            # the -9999.0 declared in the file, so a plain _FillValue mask\n'
        '            # keeps them. They cannot be removed with valid_range either: a\n'
        '            # negative Lifted Index is physically meaningful.\n'
        '            data = data.where(data != extra_fill)\n'
        '        if fill_value is not None:\n'
        '            data = data.where(data != fill_value)\n',
        "El -999 de los no-recuperados de Stability, que NO es el _FillValue "
        "declarado (-9999). Lo avisa el propio código de CIMSS en "
        "cspp-sounder-ql-1.4/scripts/sounder_packages/nucaps.py.",
    ),
    (
        "satpy/readers/nucaps.py",
        '        file_units = ds_info.get("file_units",\n'
        '                                 self.get(var_path + "/attr/units"))\n'
        '        ds_info.update(getattr(self[var_path], "attrs", {}))\n',
        '        file_units = ds_info.get("file_units",\n'
        '                                 self.get(var_path + "/attr/units"))\n'
        '        # Kept before the file attributes overwrite ds_info below, otherwise a\n'
        '        # "units" declared in the YAML can never win. That matters when several\n'
        '        # products share one variable: NUCAPS packs CAPE (J/kg) and the Lifted\n'
        '        # Index (K) inside "Stability", whose own units attribute is "1".\n'
        '        yaml_units = ds_info.get("units")\n'
        '        ds_info.update(getattr(self[var_path], "attrs", {}))\n',
        "Sin esto el YAML no puede fijar las unidades, aunque la línea "
        '\'"units": ds_info.get("units", file_units)\' diga lo contrario: el '
        "update de los atributos del archivo la pisa antes.",
    ),
    (
        "satpy/readers/nucaps.py",
        '            "units": ds_info.get("units", file_units),\n',
        '            "units": yaml_units or ds_info.get("units", file_units),\n',
        "La otra mitad de lo anterior.",
    ),
    (
        "satpy/etc/readers/nucaps.yaml",
        "  Pressure_Levels:\n"
        "    name: Pressure_Levels\n"
        "    standard_name: air_pressure\n"
        "    file_type: nucaps\n"
        "    file_key: Pressure\n"
        "    index: 0",
        "  Pressure_Levels:\n"
        "    name: Pressure_Levels\n"
        "    standard_name: air_pressure\n"
        "    file_type: nucaps\n"
        "    file_key: Pressure\n"
        "    index: 0\n"
        "  CAPE:\n"
        "    name: CAPE\n"
        '    units: "J/kg"\n'
        "    coordinates: [longitude, latitude]\n"
        "    file_type: nucaps\n"
        "    file_key: Stability\n"
        "    column_index: 0\n"
        "    extra_fill_values: [-999.0]\n"
        "  Lifted_Index:\n"
        "    name: Lifted_Index\n"
        '    units: "K"\n'
        "    coordinates: [longitude, latitude]\n"
        "    file_type: nucaps\n"
        "    file_key: Stability\n"
        "    column_index: 9\n"
        "    extra_fill_values: [-999.0]",
        "Los dos productos nuevos. Stability[:, 0] es CAPE y Stability[:, 9] el "
        "Lifted Index; los índices salen del código de CSPP Sounder QL.",
    ),
]


def site_packages_por_omision():
    import satpy
    return os.path.dirname(os.path.dirname(os.path.realpath(satpy.__file__)))


def main(argv):
    verificar = "--verificar" in argv
    restos = [a for a in argv[1:] if not a.startswith("--")]
    raiz = restos[0] if restos else site_packages_por_omision()

    fallos = 0
    for archivo, viejo, nuevo, porque in PARCHES:
        ruta = os.path.join(raiz, archivo)
        texto = io.open(ruta, encoding="utf-8").read()

        if nuevo in texto:
            print("  ok   ya aplicado: %s" % porque.split(":")[0])
            continue
        if verificar:
            print("  FALTA  %s\n         %s" % (archivo, porque))
            fallos += 1
            continue
        if texto.count(viejo) != 1:
            print("  ERROR  el texto esperado aparece %d veces en %s"
                  % (texto.count(viejo), archivo))
            print("         parche: %s" % porque)
            print("         ¿bundle nuevo? Revisa este parche antes de seguir.")
            fallos += 1
            continue
        io.open(ruta, "w", encoding="utf-8").write(texto.replace(viejo, nuevo, 1))
        print("  aplicado: %s" % porque.split(":")[0])

    if fallos:
        return 1
    print("  %d parches en su sitio" % len(PARCHES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
