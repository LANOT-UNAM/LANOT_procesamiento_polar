# Parches al Satpy del bundle de Polar2Grid

El bundle de Polar2Grid 3.2 trae su propio runtime de Python con
**satpy 0.59.1.dev110 congelado dentro**. Nada de lo que se arregle aguas arriba
nos llega hasta Polar2Grid 3.3, así que lo que necesitamos lo aplicamos aquí.

`aplicar_parches_satpy.py` lleva la lista, y cada entrada explica **por qué**
existe. Lo ejecuta el `%post` de `polar2grid_v3.2-mapdrawer.def` con el
intérprete del propio bundle, y el `%test` lo vuelve a llamar con `--verificar`:
una sola lista, imposible de desincronizar.

## Cómo probarlos sin compilar nada

En bucéfalo está el bundle extraído en `/data/cspp/polar2grid_v_3_2/`, con la
**suite de tests de Satpy** incluida — y los del lector `nucaps` son
`unittest.TestCase` puro, así que corren con el intérprete del bundle sin
pytest… salvo `test_netcdf_utils`, que sí lo importa. La receta completa:

```bash
S=/tmp/pruebas                 # donde sea
SP=/data/cspp/polar2grid_v_3_2/libexec/python_runtime/lib/python3.11/site-packages
PY=/data/cspp/polar2grid_v_3_2/libexec/python_runtime/bin/python

# pytest aparte, sin tocar el bundle
$PY -m pip install --quiet --target="$S/pylibs" pytest

# copia del árbol con symlinks, para poder sustituir solo lo que se parchea
cp -rs "$SP/satpy" "$S/arbol/satpy"
for f in satpy/readers/nucaps.py satpy/etc/readers/nucaps.yaml; do
    rm -f "$S/arbol/$f"; cp "$SP/$f" "$S/arbol/$f"
done

python3 aplicar_parches_satpy.py "$S/arbol"

# OJO: satpy resuelve su etc/ con realpath, así que con symlinks acabaría
# leyendo el YAML del bundle. Hay que apuntarlo con SATPY_CONFIG_PATH.
mkdir -p "$S/cfg/readers" && cp "$S/arbol/satpy/etc/readers/nucaps.yaml" "$S/cfg/readers/"

SATPY_CONFIG_PATH=$S/cfg PYTHONPATH=$S/arbol:$S/pylibs \
    $PY -m unittest satpy.tests.reader_tests.test_nucaps
```

## Qué hacer con cada parche

Los dos primeros son **pytroll/satpy#3450**, ya mergeado aguas arriba: se
retiran al pasar a Polar2Grid 3.3, con todo lo demás de este directorio si para
entonces también han subido los otros.

Los cinco restantes —`column_index`, `extra_fill_values`, la precedencia de
`units` y las dos entradas del YAML— son **nuestros y están sin proponer**.
Deberían ir como PR a `pytroll/satpy`: el lector no tiene mantenedor activo y
davidh pidió expresamente que reportáramos lo que encontrásemos.
