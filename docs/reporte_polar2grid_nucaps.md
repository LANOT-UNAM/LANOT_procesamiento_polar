**Subject:** Polar2Grid v3.2, `nucaps` reader: `KeyError: 'H2O_MR/attr/valid_range'` on NUCAPS-EDR v3r2 files

Dear Polar2Grid team,

We run Polar2Grid v3.2 operationally at LANOT-UNAM (Mexico) for JPSS direct broadcast.
While adding NUCAPS sounding products to our chain we hit what looks like a small
oversight in the `nucaps` reader: any `H2O_MR_*mb` product aborts the run with a
`KeyError`, while the temperature products from the same files load and render correctly.

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

**Observed:** the run dies with

```
KeyError: 'H2O_MR/attr/valid_range'
```

Dropping `H2O_MR_853mb` from the same command, everything else runs to completion.

## Where it comes from

In `satpy/readers/nucaps.py` (Satpy `0.59.1.dev110+g9cccb77a6`, as bundled in the v3.2
tarball), `NUCAPSFileHandler.get_dataset` reads the two attributes in consecutive lines,
but with different accessors:

```python
193:        valid_min, valid_max = self[var_path + "/attr/valid_range"]
194:        fill_value = self.get(var_path + "/attr/_FillValue")
```

`__getitem__` indexes `self.file_content` directly, so a missing attribute raises
`KeyError`; `get()` on the next line takes a default. The v3r2 granules do not carry
`valid_range` on `H2O_MR` — `ncdump -h` shows only `long_name`, `units`, `coordinates` and
`_FillValue`. Other variables in the same file *do* carry it (`Stability`, for instance,
has `valid_range = 0.f, 1000000.f`), which is presumably why this has gone unnoticed.

What makes us fairly confident this is an oversight rather than a contract is that the
code **twenty-five lines below already handles the attribute being absent**:

```python
218:        if valid_min is not None and valid_max is not None:
219:            # the original .cfg/INI based reader only checked valid_max
220:            data = data.where((data <= valid_max))
```

So the one-line change would seem to be enough, using the same accessor as the line below
it:

```python
valid_min, valid_max = self.get(var_path + "/attr/valid_range", (None, None))
```

We have not opened a PR because we do not know whether other readers depend on the
current behaviour, and we cannot test against the wider corpus of NUCAPS files you have.

Note this is not really about water vapour: `nucaps.yaml` defines eighteen other
`pressure_based` datasets the same way (`O3`, `Liquid_H2O_MR`, `CO`, `CH4`, `HNO3`, `N2O`,
`SO2`, their `_MR` variants…), and any of them will take the same path on any file that
omits `valid_range`. We only tested `H2O_MR` because it is the one our forecasters asked
for.

## Two things that made it harder to diagnose

**1. `--list-products` advertises the products that cannot be read.** It lists all 100
`H2O_MR_*mb` layers alongside the 100 `Temperature_*mb`, so there is no way to tell in
advance which of the advertised products will fail. We only found out at load time.

**2. One unreadable product aborts the whole call.** Asking for four `Temperature_*mb`
plus one `H2O_MR_*mb` produced **no output at all** — not even the temperature GeoTIFFs,
which are written normally when the water vapour product is left out of the same command.
For an operational chain this is the expensive half: by the time the run dies, the
resampling has already been paid for.

Would it be reasonable for a per-product failure to be logged and skipped, so the rest of
the request still completes? We appreciate this may be a deliberate all-or-nothing
contract; if so, please ignore this second half — the `KeyError` is what blocks us.

## What does work, for the record

Everything else we tried from the same files renders end to end: `Temperature_853mb`,
`Temperature_707mb`, `Temperature_497mb` and `Skin_Temperature`, resampled to a 5 km
WGS-84 grid and written as float32 GeoTIFF. `Temperature_497mb` came out between 257 and
270 K with a mean of 265, showing a cold pocket to the north and warm air toward the Gulf
of Mexico — physically sensible. The reader is clearly working; it is specifically the
`valid_range` lookup.

We also confirmed that the speckled appearance of the fields is the quality mask doing its
job, not a resampling artefact: raising `--radius-of-influence` to 35 km barely changes it,
while `--no-mask-quality` fills every gap. Mentioning it only so it is not mistaken for a
symptom of the same problem.

## Environment

- Polar2Grid v3.2 (`CSPP_POLAR2GRID_V3.2.tar.gz`), unmodified, inside an Apptainer
  container on Rocky Linux 9.
- Satpy `0.59.1.dev110+g9cccb77a6`, as bundled.
- Input: `NUCAPS-EDR_v3r2_n21_*.nc`, from the CSPP Sounder QL v1.4 sample data.
- Reader `nucaps`, writer `geotiff`, custom grid definition passed with `--grid-configs`.

If this belongs upstream in Satpy rather than in the Polar2Grid bundle, we are happy to
open the issue at `pytroll/satpy` instead — just say the word. We can also send the
offending granule and the full traceback.

Thanks very much for your work on Polar2Grid; it does the heavy lifting in our chain.

Alejandro Sierra
LANOT — Laboratorio Nacional de Observación de la Tierra
Universidad Nacional Autónoma de México

---

# Respuesta de seguimiento — para publicar en el hilo

Redactada el 2026-08-29, después de que davidh contestara (2026-08-25) y mergeara
[pytroll/satpy#3450](https://github.com/pytroll/satpy/pull/3450) el 2026-08-26. Va en el
mismo hilo: <https://forums.ssec.wisc.edu/viewtopic.php?t=60122>. En inglés, como el resto.

---

Hi David,

Thank you — a fix merged within two days of the report is more than we expected, especially
for a reader you've told us has no dedicated funding behind it.

**On "the resampling is already paid for": you're right, and that phrasing was wrong.** I
wrote it assuming the `KeyError` surfaced somewhere after the data had been loaded, so that
the expensive part of the job was already done when the run died. Your explanation makes
clear that isn't what happens — the load fails first, and with lazy dask evaluation nothing
gets resampled. I should have checked before putting it that way.

What I actually meant to argue survives without that claim, and it's simpler: for us the
unit of work is one command per satellite pass, run unattended. When a single unreadable
product takes the whole call down, the pass produces *nothing* — including the four
temperature fields that loaded perfectly well — and it takes a human noticing the empty
output directory to find out. That is the cost, rather than any wasted computation. So your
second fix, the one I hadn't identified, is exactly the part that matters to us: I had
diagnosed the `valid_range` lookup and assumed it was also what aborted the run, when in
fact Satpy was catching that and the real casualty was the post-load pass over the
requested keys, looking for a product that never arrived. Good to have the correct picture.

**On `--list-products`:** understood, and no argument from us. Knowing that the advertised
list is what the reader's configuration declares rather than what will actually load is
enough — now that failures degrade instead of aborting, an over-optimistic list costs us
nothing.

**Your fix works on the real files — confirmed here.** We run Polar2Grid v3.2 from the
bundled tarball, so `satpy 0.59.1.dev110` is frozen inside it and the fix won't reach us
until v3.3. Rather than wait, we applied your two lines to `satpy/readers/nucaps.py` in our
container recipe (anchored so the build fails if the file ever stops matching what the patch
expects, and it comes out cleanly when we move to 3.3). Two results you may find useful:

- The command from the original report — the four temperature fields **plus**
  `H2O_MR_853mb`, over the same 19 `NUCAPS-EDR_v3r2_n21` granules — now ends in `SUCCESS`
  with 5 GeoTIFFs, where before it died with the `KeyError` and produced none.
- Your two lines apply unchanged to `0.59.1.dev110`, and your updated `test_nucaps.py` runs
  against that version as-is: 2 errors before the patch, all 22 passing after. In our
  reproduction the failure surfaces in `_mask_data_below_surface_pressure`, which is what
  made the second bug legible to us.

One observation, offered as information rather than as a request: with the fix,
`valid_min`/`valid_max` are `None` for these variables, so the `valid_max` masking is
skipped entirely and only `_FillValue` is applied. That turns out to be harmless on real
data — our `H2O_MR_853mb` comes out at 0.001–0.018 g/g (mean 0.010), which is physically
sensible mixing ratio for 850 hPa over Mexico, and those are the true extremes of the field,
not a clipped range. So there seems to be no need for a fallback range; we just wanted you
to have the measurement rather than the assumption.

**An offer.** Our sounder branch isn't live yet — CSPP HEAP v3.0 runs here but doesn't emit
`NUCAPS-EDR` on our data, which we're chasing separately with the HEAP team — so everything
above was tested against the CSPP Sounder QL v1.4 sample granules. Once we do have
operational NUCAPS files from our own direct-broadcast passes, we'll be exercising this
reader daily over Mexico and the Gulf. Given that it isn't actively maintained, we're glad
to report whatever we run into, and to test candidate fixes against real files if that's
useful to you. Just tell us where you'd prefer such reports — here, or as issues at
`pytroll/satpy`.

Thanks again.

Alejandro Sierra
LANOT — Laboratorio Nacional de Observación de la Tierra
Universidad Nacional Autónoma de México
