> **Estado: preparado, sin abrir.** PR a `pytroll/satpy` que David Hoese pidió en el
> [tema 60122](https://forums.ssec.wisc.edu/viewtopic.php?t=60122) del foro de SSEC
> (*"a pull request may be the easiest way for me to see what you mean"*), en respuesta al
> ofrecimiento de `respuesta_polar2grid_nucaps.bbcode`.
>
> La rama es `nucaps-cape-lifted-index` en `~/lanot/satpy` (commit `f596913`, sobre
> `5b9051c2c` de `main`). Se abre desde el fork de asierra:
>
>     cd ~/lanot/satpy
>     gh repo fork pytroll/satpy --remote --remote-name fork
>     git push -u fork nucaps-cape-lifted-index
>     gh pr create --repo pytroll/satpy --base main --head asierra:nucaps-cape-lifted-index \
>         --title "Add CAPE and Lifted Index to the NUCAPS reader" --body-file <este texto, desde la línea --->
>
> Es la versión para upstream de los cinco parches propios de
> `contenedores/parches/aplicar_parches_satpy.py`, con dos cosas que el parche del bundle no
> tenía: `get_shape` también quita la dimensión de `column_index`, y el enmascarado pasa a un
> método propio porque `get_dataset` superaba el límite de complejidad de ruff. **Cuando
> Polar2Grid traiga un Satpy con esto, se quitan esos cinco parches**, como los dos de #3450.
>
> Lo que sigue es el cuerpo del PR, en Markdown (GitHub sí lo interpreta).

---

NUCAPS EDRs carry CAPE and the Lifted Index, but the reader can't reach them. This adds both as datasets, following up on the discussion in the [SSEC forum thread](https://forums.ssec.wisc.edu/viewtopic.php?t=60122) about #3450.

## Why the reader couldn't load them

Both live in the `Stability` variable, which packs 16 parameters per field of regard along its last dimension. The file describes them itself:

```
Stability:description = "1 CAPE; 2 CIN; 3 Pressure level @ Lifted Condensation Level (LCL); ... 10 Lifted Index (LI) @ 500 hPa; 11-16 empty/not used."
Stability:units = "1"
Stability:valid_range = 0.f, 1000000.f
Stability:_FillValue = -9999.f
```

Three things were in the way:

1. **No way to pick a column.** `index` addresses the first dimension, and `pressure_index` addresses the last but carries pressure-level semantics with it (surface pressure, pressure levels). This adds `column_index`, a plain last-axis selection; `get_shape` drops that dimension too.
2. **The fill value that's actually used isn't the declared one.** NUCAPS leaves non-retrievals in `Stability` at `-999.0`, not at the declared `_FillValue` of `-9999.0` (CIMSS's own CSPP Sounder QL code notes this). They can't be masked through `valid_range` either: a negative Lifted Index is meaningful, and the declared `[0, 1e6]` only fits CAPE. This adds `extra_fill_values`, a list of sentinels to mask per dataset.
3. **Units from the YAML never won.** `get_metadata` updates `ds_info` with the variable's own attributes *before* reading `ds_info.get("units", file_units)`, so a `units` declared in the YAML was always replaced by the file's. With two products sharing a variable whose units are `"1"`, that matters. The YAML value is now kept and takes precedence.

The masking moved into a small `_mask_invalid` method, unchanged, to keep `get_dataset` under the complexity limit.

## Checked on real data

NOAA-21 NUCAPS-EDR v3r2 granules from our direct-broadcast station (13 granules over Mexico, 2026-09-22, 1560 fields of regard):

| | CAPE | Lifted_Index |
|---|---|---|
| units | J/kg | K |
| non-retrievals at `-999.0` (now masked) | 6 | 6 |
| accepted retrievals (`Quality_Flag == 0`) | 0 – 6142 | −10.7 – 3.3 |
| negative values kept | — | yes |

Values outside those ranges (CAPE up to 13 091 J/kg, LI up to 36.9 K) only appear in rejected retrievals, which the reader already masks by default with `mask_quality`.

The reader only applies `valid_max` — as the existing comment says — which is why the file's `valid_range = [0, 1e6]` doesn't wipe out negative Lifted Index values today. The new test declares that same `valid_range` on its fake `Stability`, so it fails if `valid_min` masking is ever enabled for this variable.

## Tests

`test_load_cape_and_lifted_index` checks units, shape (data and `attrs["shape"]`), that both `-999.0` and `-9999.0` are masked and that negative Lifted Index values survive. Each of the four changes was reverted in turn to confirm the test fails without it. The existing 22 NUCAPS tests pass unchanged.

 - [x] Tests added
 - [x] Fully documented (module docstring)
 - [x] Add your name to `AUTHORS.md` if not there already

🤖 Generated with [Claude Code](https://claude.com/claude-code)
