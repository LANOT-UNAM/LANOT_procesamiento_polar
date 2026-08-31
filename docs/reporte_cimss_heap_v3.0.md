> **Estado: enviado, contestado y CERRADO — el fallo era NUESTRO.** Publicado el 2026-08-24 en
> el foro de SSEC, [tema 60121](https://forums.ssec.wisc.edu/viewtopic.php?t=60121). Kathy S.
> contestó el **2026-08-25** descartando el error de operación (*"I do not think you are
> executing the software incorrectly"*), explicando que `NUCAPS-ALL-HR` son archivos
> intermedios —no un sustituto de `NUCAPS-CCR-AR`— y pidiendo dos diagnósticos: correr fuera
> del contenedor y repetir con `--noclean`.
>
> El segundo destapó la causa el **2026-08-29**, y es de este lado: el bundle instalado
> **dentro del `.sif`**, que es de solo lectura. `airsb103.exe` abre una unidad Fortran sin
> nombre dentro de su propio árbol de instalación y muere con `Cannot open file 'fort.40':
> Read-only file system`; eso aborta `HEAP_Retrieval.pl` y con él los conversores a NetCDF, y
> `run_heap.bash` **sale en 0** de todos modos. Con el bundle montado desde el host salen las
> cinco familias: 16 gránulos con los datos de prueba de §3.3 y 14 sobre datos propios de
> NOAA-20. El primer diagnóstico no se pudo hacer: el host es Rocky 10 y los binarios están
> ligados contra el HDF5 de EL8.
>
> La respuesta que cierra el hilo —la corrección, las dos afirmaciones erróneas del reporte y
> las dos sugerencias a CIMSS— está **al final de este archivo, pendiente de publicar**.
>
> Lo que sigue es el texto tal como se envió, sin retocar.

---

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

## Your own benchmark has the two products we never get

The test data ships with a `benchmark_edr/` directory, whose contents are exactly the 48
files §3.3 describes:

```
  16  NUCAPS-CCR-AR_v3r2_*
  16  NUCAPS-EDR_v3r2_*
  16  NUCAPS-OLR_v3r2_*
```

So the reference output for this very test case contains the two products our run does not
produce, and does not contain `NUCAPS-ALL-HR`, the only one it does.

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

Since it appears neither in §1.7 nor in `benchmark_edr/`, we do not think it is a
documented replacement for `NUCAPS-CCR-AR`.

1. What is `NUCAPS-ALL-HR`, and under what circumstances does the software write it
   instead of the three documented products?
2. Is its presence a symptom of the same missing step that leaves us without
   `NUCAPS-EDR` and `NUCAPS-CCR-AR`, or an unrelated matter?

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

---

# Respuesta de seguimiento — para publicar en el hilo

Redactada el 2026-08-29, después de que kathys contestara (2026-08-25) y de que su consejo
—correr con `--noclean`— destapara la causa, que resultó ser **nuestra**. Va en el mismo hilo:
<https://forums.ssec.wisc.edu/viewtopic.php?t=60121>. En inglés, como el resto.

---

Hi Kathy,

**Please stop work on this — the bug is ours, not yours.** CSPP HEAP v3.0 is fine. We found
the cause this morning, and we found it by doing what you asked: re-running with `--noclean`.
That was the missing piece, and I'll explain why below because it may be worth knowing for
other users.

**The cause.** We run HEAP inside an Apptainer container, with the bundle installed *into* the
image. An Apptainer image is a read-only filesystem. `airsb103.exe` opens an unnamed Fortran
unit inside the installation tree, and that write fails:

```
At line 330 of file read_nl.F (unit = 40)
Fortran runtime error: Cannot open file 'fort.40': Read-only file system
FATAL: Error in HEAP_Retrieval.pl: Error running airsb103.exe
```

`HEAP_Retrieval.pl` aborts, and with it the NetCDF converters — hence no `NUCAPS-EDR` and no
`NUCAPS-CCR-AR`. `NUCAPS-OLR` survives because `main_cris_olr` writes it on a different path.
That is also why the run took 41 seconds instead of the documented 1–3 minutes.

**The proof, before the explanation.** Same image, same test data, same command — the only
change being the bundle bind-mounted from a writable disk instead of installed inside the
image — produces all five families: 16 `NUCAPS-EDR`, 16 `NUCAPS-CCR-AR`, 16 `NUCAPS-CCR`, 16
`NUCAPS-ALL-HR`, 16 `NUCAPS-OLR`, in 1m 59s. We've since moved the bundle out of the image
permanently.

**Two things in my original report were wrong, and I'd like to correct them on the record.**

1. I wrote that the word "retrieval" never appears in the logs, and concluded the retrieval
   step was never attempted. It *is* attempted. That observation was about the wrapper log —
   the only one that survived, because without `--noclean` the working directory is cleaned up.
   `HEAP_Retrieval.log` and `nucaps_retrieval.log` are there in the failing runs too, and the
   first one has held the exact error message all along.
2. I argued that since your own test case reproduced the failure, the problem could not be on
   our side. That reasoning had a hole in it: your test case rules out *our inputs*, not *our
   installation*. Every single run — yours and ours — went through the same broken image.

**It bit us three times, in three different ways, and that is the interesting part.** Once we
moved the bundle out of the image and onto disk, the same class of problem reappeared twice
more as ordinary Unix permissions, because the deployed tree belonged to a different user than
the one running the chain:

```
sh: .../Common_Bin/main_nucaps_preprocessor: Permission denied        (no execute)
Fortran runtime error: Cannot open file 'fort.40': Permission denied  (no write)
```

Read-only filesystem, no execute, no write — three distinct failures, all in the same place,
and **all three exited 0**. The final one is now behind us: on our own NOAA-20 CrIS and ATMS
data the package produces all five families, 14 granules each, in 1m 57s.

**One observation you may find worth acting on.** The failure is detected internally: the log
ends with `FATAL: Error in HEAP_Retrieval.pl` followed by

```
ERROR MESSAGING SYSTEM IMPROPERLY SET UP. UNABLE TO E-MAIL ERROR MESSAGE.
```

but `run_heap.bash` still exits 0 and prints `EXECUTION COMPLETED SUCCESSFULLY`. In an
unattended chain that is the worst possible outcome: our orchestrator recorded fourteen
successful passes that had produced no soundings at all. If the wrapper propagated a non-zero
exit status when a module reports FATAL, every one of the three failures above would have
surfaced on the first run instead of the fifteenth — and we would never have opened this
thread. A line in the installation guide noting that the installation tree must be readable,
writable and executable by the account running the software — which rules out installing it
inside a container image, and matters for any shared installation — would also have saved us
two weeks.

**On running outside the container**, which you asked for: we could not. Our host is Rocky
Linux 10.2 and the HEAP binaries are linked against the EL8 HDF5 (`libhdf5.so.103`,
`libhdf5_hl.so.100`), which that release does not provide, so they don't load at all. That is
precisely why we run HEAP in a Rocky 8 container — not as a layer between HEAP and a supported
system, but as the way to give it the system your manual specifies. Worth knowing if other
users start moving to EL10.

Thank you for the time you already put into this, and sorry for pointing it at the wrong
place. The `--noclean` suggestion is what solved it.

Alejandro Sierra
LANOT — Laboratorio Nacional de Observación de la Tierra
Universidad Nacional Autónoma de México
