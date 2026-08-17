**Subject:** Polar2Grid v3.2, `nucaps` reader: `KeyError: 'H2O_MR/attr/valid_range'` on NUCAPS-EDR v3r2 files

> **[PENDIENTE ANTES DE ENVIAR — en tahan, no se puede desde bucéfalo]**
> Faltan dos datos que hay que pegar tal cual antes de mandar esto. Están marcados
> abajo con `[PEGAR …]`:
>
> ```bash
> # 1. La traza completa. La corrida está en el log de aquella prueba; si no se
> #    conserva, se reproduce con el comando de "Reproduction" de abajo.
> #    Conviene capturarla entera:  … 2>&1 | tee /data/tmp/nucaps_h2o.log
>
> # 2. La versión de Satpy que trae el bundle:
> apptainer exec /opt/containers/polar2grid_v3.2-mapdrawer.sif \
>     bash -lc 'python -c "import satpy; print(satpy.__version__)"'
> ```
>
> Este bloque no va en el correo: se borra al enviarlo.

Dear Polar2Grid team,

We run Polar2Grid v3.2 operationally at LANOT-UNAM (Mexico) for JPSS direct broadcast.
While adding NUCAPS sounding products to our chain we hit what looks like a mismatch
between the `nucaps` reader and the v3r2 file format: any `H2O_MR_*mb` product aborts the
run with a `KeyError`, while the temperature products from the same files load and render
correctly.

## Reproduction

Input: 19 `NUCAPS-EDR_v3r2_n21_*.nc` granules — the sample data shipped with **CSPP
Sounder QL v1.4**, not files of our own making.

```bash
polar2grid.sh -r nucaps -w geotiff \
    --grid-configs /path/to/grid.yaml -g wgs84_geo_5km \
    -p Temperature_853mb H2O_MR_853mb \
    --dtype float32 --no-enhance \
    -f NUCAPS-EDR_v3r2_n21_*.nc
```

**Observed:**

```
[PEGAR AQUÍ LA TRAZA COMPLETA]
```

The failing lookup is `H2O_MR/attr/valid_range`, in

```
satpy/readers/nucaps.py:193
```

which reads the variable's `valid_range` attribute unconditionally. The v3r2 granules do
not carry that attribute on `H2O_MR` — `ncdump -h` shows only `long_name`, `units`,
`coordinates` and `_FillValue`. Other variables in the same file *do* carry it
(`Stability`, for instance, has `valid_range = 0.f, 1000000.f`), which is presumably why
the code path is not usually exercised.

## Two things that make it harder to work around

**1. `--list-products` advertises the products that cannot be read.** It lists all 100
`H2O_MR_*mb` layers alongside the 100 `Temperature_*mb`, so there is no way to tell in
advance which of the advertised products will fail. We only found out at load time.

**2. One unreadable product aborts the whole call.** Asking for four `Temperature_*mb`
plus one `H2O_MR_*mb` produced **no output at all** — not even the temperature GeoTIFFs,
which are readable and which are written normally when the water vapour product is left
out of the same command. For an operational chain this is the expensive part: the
resampling has already been paid for by the time the run dies.

Would it be reasonable for a per-product failure to be logged and skipped, so the rest of
the request still completes? We appreciate this may be a deliberate all-or-nothing
contract; if so, ignore this half of the report — the `KeyError` itself is the thing that
blocks us.

## What does work, for the record

Everything else we tried from the same files renders end to end: `Temperature_853mb`,
`Temperature_707mb`, `Temperature_497mb` and `Skin_Temperature`, resampled to a 5 km
WGS-84 grid and written as float32 GeoTIFF. `Temperature_497mb` came out between 257 and
270 K with a mean of 265, showing a cold pocket to the north and warm air toward the Gulf
of Mexico — physically sensible. So the reader is clearly working; it is specifically the
`valid_range` lookup on this variable.

We also confirmed that the speckled appearance of the fields is the quality mask doing its
job, not a resampling artefact (raising `--radius-of-influence` to 35 km barely changes it,
while `--no-mask-quality` fills every gap). Mentioning it only so it is not mistaken for a
symptom of the same problem.

## Environment

- Polar2Grid v3.2 (`CSPP_POLAR2GRID_V3.2.tar.gz`), unmodified, inside an Apptainer
  container on Rocky Linux 9.
- Satpy version as bundled: `[PEGAR LA SALIDA DE satpy.__version__]`
- Input: `NUCAPS-EDR_v3r2_n21_*.nc`, from the CSPP Sounder QL v1.4 sample data.
- Reader `nucaps`, writer `geotiff`, custom grid definition passed with `--grid-configs`.

If this belongs upstream in Satpy rather than in the Polar2Grid bundle, we are happy to
open the issue at `pytroll/satpy` instead — just say the word. We can also send the
offending granule and the full log.

Thanks very much for your work on Polar2Grid; it does the heavy lifting in our chain.

Alejandro Sierra
LANOT — Laboratorio Nacional de Observación de la Tierra
Universidad Nacional Autónoma de México
