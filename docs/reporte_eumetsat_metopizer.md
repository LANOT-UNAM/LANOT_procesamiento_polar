> **Estado: borrador, sin enviar (2026-11-18).** Para el User Service Helpdesk de EUMETSAT,
> ops@eumetsat.int, que es quien distribuye el Metopizer desde el User Portal. El parche que
> describe está en `contenedores/parches/metopizer-3.57_rs_decode_return.patch` y lo explica
> `contenedores/parches/README.md`. Al enviarlo, anotar aquí la fecha y la respuesta, y
> conservar el texto tal cual se envió.
>
> Va en inglés. Lo de abajo de la raya es el correo.

---

**Subject:** Metopizer 3.57: `rs_decode()` lacks a return statement; `cadu_to_ccsds` crashes when built with GCC 8 or later

Dear EUMETSAT User Service,

We run a direct-readout station at the Laboratorio Nacional de Observación de la Tierra
(LANOT), Universidad Nacional Autónoma de México, and process Metop-B and Metop-C AHRPT
passes with the Metopizer and AAPP. While moving our processing from Metopizer 3.51.1 to
3.57 (`metopizer_3_57_tar_9b77fef66a.zip`, from the User Portal), we found a defect that
makes `cadu_to_ccsds` unusable when built with a current compiler. We would like to report
it, together with the one-line fix.

**The defect.** In `src/rs.cpp`, `rs_decode()` is declared to return `int`, but its body
calls `decode_rs_ccsds()` without returning the result:

```cpp
int rs_decode(unsigned char *data,int *eras_pos,int no_eras,int pad)
{
	// cout << "rs_decode called\n";
	get_rs_library();
	decode_rs_ccsds(data, eras_pos, no_eras, pad);
}
```

In C++, flowing off the end of a non-void function is undefined behaviour. Since GCC 8 the
compiler treats that path as unreachable and emits a trap instruction (`ud2`) there.

**What happens.** Built with GCC 14.3.1 (Rocky Linux 10), using `CXXFLAGS="-std=c++14"` as
`INSTALL.rst` recommends, `cadu_to_ccsds` dies as soon as it decodes the first CADU of a
real pass:

- with `-O0`: `SIGILL` (illegal instruction). The backtrace points to `rs.cpp:65`, the
  `ud2` inside `rs_decode()`, called from `CVCDUToVCDU::cvcdu_to_vcdu`
  (`cvcdutovcdu.cpp:134`);
- with `-O2`: `SIGSEGV`.

Older compilers do not trap. Our production build of 3.51.1, compiled with GCC 6, has worked
for years only by chance: the return value of `decode_rs_ccsds()` happens to remain in the
return register.

**The fix** is to return the value:

```diff
--- a/src/rs.cpp
+++ b/src/rs.cpp
@@ -62,5 +62,5 @@
 {
 	// cout << "rs_decode called\n";
 	get_rs_library();
-	decode_rs_ccsds(data, eras_pos, no_eras, pad);
+	return decode_rs_ccsds(data, eras_pos, no_eras, pad);
 }
```

With this change, and with no other modification, `cadu_to_ccsds` processes a Metop-C pass
from 2026-11-18 (16:01–16:12 UTC) in 13 s and writes all twelve instrument streams.
`ccsds_to_l0` then produces the seven Level 0 products, and the MMAM and TLE it extracts
are byte-identical to those of our 3.51.1 installation for the same pass. Building with
`-Wreturn-type` shows no other function with the same problem.

**Two related notes**, in case they are useful for the documentation:

1. The Metopizer loads libfec at run time with `dlopen("libfec.so")`, so the dependency does
   not appear in `ldd` or at link time. When it is missing, `cadu_to_ccsds` exits with
   "Cannot open Reed-Solomon library libfec". The original libfec site (ka9q.net) is no longer
   maintained and the library is not packaged for Rocky Linux. We use
   `github.com/quiet/libfec`, built with CMake as a shared library; built with its classic
   `./configure`, it includes 32-bit SIMD assembly that fails on x86_64.
2. `INSTALL.rst` already mentions the C++17 `byte` conflict. A note that GCC 8 or later
   requires the fix above would save other users the same investigation.

Thank you for maintaining the Metopizer. We are happy to provide more details or to test a
corrected release.

Kind regards,

Alejandro Aguilar Sierra
Laboratorio Nacional de Observación de la Tierra (LANOT)
Instituto de Geografía, Universidad Nacional Autónoma de México
