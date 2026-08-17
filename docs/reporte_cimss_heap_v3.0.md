**Subject:** CSPP HEAP v3.0 — no NUCAPS-EDR retrieval files produced; reproduced with your §3.3 test data

Dear CSPP team,

We are running CSPP HEAP v3.0 operationally at LANOT-UNAM (Mexico) for JPSS direct
broadcast, and `run_heap.bash` never produces the `NUCAPS-EDR` retrieval product. It
exits 0 and reports `EXECUTION COMPLETED SUCCESSFULLY`, with no warnings or errors.

We can reproduce it with **your own test data and your own documented command**, so we
believe this is not specific to our inputs.

## Reproduction, following §3.3 of the v3.0 Installation Guide

Using `CSPP_HEAP_TESTDATA_V3.0.tar.gz` (the NOAA-21 CrIS/ATMS overpass of
28 October 2025), exactly as documented:

```bash
cd nucaps_test_data
mkdir work
cd work
mkdir anc
run_heap.bash -s n21 -i ../input -o RO -p 4 -d $PWD/anc
```

**Expected**, per §3.3: *"Completion will take between 1-3 minutes on modern computers;
16 files per product type will be created for a total of 48 local NetCDF files."*

**Observed:** 32 files in 41 seconds.

| | Documented | Observed |
|---|---|---|
| Total NetCDF files | 48 | **32** |
| `NUCAPS-EDR_v3r2_*` | 16 | **0** |
| `NUCAPS-CCR-AR_v3r2_*` | 16 | **0** |
| `NUCAPS-OLR_v3r2_*` | 16 | 16 |
| `NUCAPS-ALL-HR_v3r2_*` | not documented | **16** |
| Wall time | 1–3 min | 41 s |

Exit status was 0. The full driver log is:

```
heap_handler.py:66 run
 └───INFO : HEAP perl wrapper execution beginning
***** BEGIN HEAP WRAPPER EXECUTION *****
Processing... - 0m 40s
heap_handler.py:68 run
 └───INFO : HEAP perl wrapper execution complete
***** END HEAP WRAPPER EXECUTION *****
runner.py:64 execute_module
 └───INFO : HEAP module execution time: 41.09 seconds
main.py:48 main
 └───INFO : EXECUTION COMPLETED SUCCESSFULLY
```

The word "retrieval" does not appear anywhere in the log, which suggests the retrieval
step is skipped rather than attempted and failed. The 41-second wall time also seems
inconsistent with a physically-iterative retrieval.

## Two questions about `NUCAPS-ALL-HR`

This filename is not documented in §1.7, which lists `NUCAPS-EDR`, `NUCAPS-CCR-AR` and
`NUCAPS-OLR`. Its contents look like a cloud-cleared-radiance product rather than a
retrieval — `ncdump -h` gives dimensions

```
Number_of_CrIS_FORs = 120 ;
Number_of_CrIS_FOVs = 9 ;
Number_of_CrIS_Channels = 2223 ;
```

and variables including `CrIS_Radiances`, `ATMS_Brightness_Temps`, `Cloud_Fraction`,
`Cloud_Height`, `Topography`, `Land_Fraction` and the CrIS/ATMS quality flags — but
**no** `Pressure`, `Temperature`, `H2O_MR`, `O3` or `Stability`. For comparison, a
genuine `NUCAPS-EDR_v3r2` file (from the CSPP Sounder QL v1.4 sample data) has
`Number_of_P_Levels = 100` and the full set of retrieved profiles.

1. Is `NUCAPS-ALL-HR` an expected v3.0 output, replacing `NUCAPS-CCR-AR`?
2. If so, is the absence of `NUCAPS-EDR` a separate problem, or are both symptoms of the
   same missing step?

## What we ruled out first

- **Output option.** `-o RO` is what §3.3 uses. We also tried `-o R` alone: the OLR files
  disappear and `NUCAPS-ALL-HR` still appears, so `-o` is parsed correctly per letter.
- **Processing mode.** `-m HR_IRMW` is the default and, per §3.1, `HR` is the only X value
  for JPSS.
- **Dynamic ancillary.** For our own passes the GFS cache had the correct dated directory
  (`2026_08_13_225`). For the §3.3 run, the software downloaded its own into `$PWD/anc`
  as documented, with no ancillary warnings.
- **Granule rejection.** No rejection messages appear in any log, and the
  `NUCAPS-GranuleInfo_*.txt` files look normal (`NUM_VALID_SCANS=4`, `IR_ONLY_FLAG=NO`,
  `RESOLUTION=HR`).
- **Our inputs and our staging.** Superseded by the fact that your test data reproduces it.

## Environment

- CSPP HEAP v3.0 (`CSPP_HEAP_V3.0.tar.gz`), installed by extracting into `/opt`, with
  `CSPP_HEAP_HOME=/opt/cspp_heap` and `cspp_heap_env.sh` sourced before every run.
- Rocky Linux 8 (per §1.3), inside an Apptainer container, with `perl` and `lftp`
  installed.
- Also reproduced outside the test case on NOAA-20 (`-s j01`) direct-broadcast CrIS and
  ATMS SDRs generated with CSPP SDR v4.1.1: 15 granules produced 15 `NUCAPS-ALL-HR` and
  15 `NUCAPS-OLR` in 23 seconds, and no `NUCAPS-EDR`.

Is there a dependency — coefficient or RTA data, a Perl module, an environment variable —
that is not covered by §1.3 and §2.2 and whose absence would cause the retrieval to be
skipped without an error? We are happy to run any diagnostic you suggest, including with
`--noclean` or `-n`, and to send the complete work directory and logs.

Thanks very much for your help.

Alejandro Sierra
LANOT — Laboratorio Nacional de Observación de la Tierra
Universidad Nacional Autónoma de México
