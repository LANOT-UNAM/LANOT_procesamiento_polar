# Guía de Scripts - Procesamiento de Satélites Polares con Contenedores

**LANOT - UNAM**  
**Proyecto:** Migración a arquitectura de contenedores (Apptainer)  
**Fecha:** Diciembre 2025

---

## 📋 Índice

1. [Descripción General](#descripción-general)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Scripts Principales](#scripts-principales)
4. [Guía de Uso](#guía-de-uso)
5. [Solución de Problemas](#solución-de-problemas)
6. [Mantenimiento](#mantenimiento)

---

## 📖 Descripción General

Este sistema procesa datos de satélites polares mediante dos flujos paralelos:

| Flujo | Satélites | Tecnología | Scripts |
|-------|-----------|------------|---------|
| **MODERNO** | NPP, NOAA-20, NOAA-21 | Contenedores Apptainer | `recibe.sh` + `procesar_cadena_completa.sh` |
| **LEGACY** | NOAA-15/18/19, METOP | Scripts tradicionales | `recibe.sh` + `noaa2`/`metop2.sh` |

---

## 🏗️ Arquitectura del Sistema

### Flujo de Datos (Satélites Modernos)

```
┌──────────────┐
│  Antena      │ Recibe datos del satélite
│  Receptora   │
└──────┬───────┘
       │ Archivo RAW (binario CCSDS)
       ▼
┌──────────────────────────────────────────────────────────────┐
│  recibe.sh                                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Analiza nombre archivo → Identifica satélite         │   │
│  │ - chain2-* → NPP (Suomi-NPP)                         │   │
│  │ - chain6-* → NOAA-20/21 (JPSS-1/2)                   │   │
│  │ - chain4-* → NOAA Legacy                             │   │
│  │ - chain5-* → METOP                                   │   │
│  └──────────────────────────────────────────────────────┘   │
└───────┬──────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  procesar_cadena_completa.sh                                 │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ PASO 1: RT-STPS v7.0 (Contenedor)                   │   │
│  │ ┌─────────────────────────────────────────────────┐ │   │
│  │ │ RAW → Level 0 (RDR)                             │ │   │
│  │ │ Decodifica telemetría CCSDS                     │ │   │
│  │ │ Archivos HDF5 organizados por instrumento      │ │   │
│  │ └─────────────────────────────────────────────────┘ │   │
│  │ Salida: /data/products/level0/*.h5                  │   │
│  │ Duración: 2-5 minutos                                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ PASO 2: CSPP SDR v4.1 (Contenedor)                  │   │
│  │ ┌─────────────────────────────────────────────────┐ │   │
│  │ │ Level 0 → Level 1 (SDR)                         │ │   │
│  │ │ Calibración radiométrica                        │ │   │
│  │ │ Geolocalización (lat/lon)                       │ │   │
│  │ │ Correcciones atmosféricas                       │ │   │
│  │ └─────────────────────────────────────────────────┘ │   │
│  │ Salida: /data/products/level1/SV*.h5                │   │
│  │ Duración: 5-10 minutos                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ PASO 3: Polar2Grid v3.1 (Contenedor)                │   │
│  │ ┌─────────────────────────────────────────────────┐ │   │
│  │ │ Level 1 → GeoTIFF                               │ │   │
│  │ │ Reproyección cartográfica (WGS84)               │ │   │
│  │ │ Generación de productos visuales:               │ │   │
│  │ │ - True Color (RGB natural)                      │ │   │
│  │ │ - False Color (térmico)                         │ │   │
│  │ └─────────────────────────────────────────────────┘ │   │
│  │ Salida: /data/products/geotiff/*.tif                │   │
│  │ Duración: 3-7 minutos                                │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### Estructura de Archivos

```
/opt/containers/                 # Contenedores compilados
├── rt_stps_7.0.sif             # RT-STPS + Patch 1 (NOAA-21)
├── cspp_sdr_v4.1.sif           # CSPP SDR
└── polar2grid_v3.1.sif         # Polar2Grid

/home/lanotadm/bin/             # Scripts de operación
├── recibe.sh                   # Despachador principal
└── procesar_cadena_completa.sh # Orquestador de contenedores

/var/log/lanot/polares/         # Logs centralizados
├── cadena/                     # Logs de recibe.sh y coordinación
│   └── YYYYMMDD_*.log
├── rt-stps/                    # Logs de RT-STPS
│   └── YYYYMMDD_HHMMSS_*.log
├── cspp-sdr/                   # Logs de CSPP SDR
│   └── YYYYMMDD_HHMMSS_*.log
└── polar2grid/                 # Logs de Polar2Grid
    └── YYYYMMDD_HHMMSS_*.log

/data/                          # Datos científicos
├── raw/                        # Archivos RAW de antena
├── products/
│   ├── level0/                 # RDR (Raw Data Records)
│   ├── level1/                 # SDR (Sensor Data Records)
│   └── geotiff/                # Imágenes finales
└── ancillary/                  # Datos auxiliares (LUTs, leapsec.dat)
```

---

## 📜 Scripts Principales

### 1. `recibe.sh` - Despachador de Tráfico

**Ubicación:** `~lanotadm/bin/recibe.sh`

**Función:** Recibe notificación de nuevo archivo RAW y lo enruta según el satélite

**Lógica de enrutamiento:**

| Patrón de archivo | Satélite | Acción |
|-------------------|----------|--------|
| `chain2-*` | Suomi-NPP | → `procesar_cadena_completa.sh` (contenedores) |
| `chain6-*` | NOAA-20/NOAA-21 | → `procesar_cadena_completa.sh` (contenedores) |
| `chain4-*` | NOAA-15/18/19 | → `noaa2` vía SSH a tsom03 (legacy) |
| `chain5-*` | METOP-A/B/C | → `metop2.sh` local (legacy) |

**Características:**
- ✅ Validación de existencia de archivo
- ✅ Logging automático con timestamp
- ✅ Ejecución en background con `nohup`
- ✅ Manejo de errores con códigos de salida

**Ejemplo de log:**
```
[2025-12-16 14:23:45 UTC] RECIBIDO: chain2-20251216_142300.raw
[2025-12-16 14:23:45 UTC] TIPO: Satélite moderno (NPP/JPSS) -> Procesamiento con contenedores
[2025-12-16 14:23:45 UTC] Proceso lanzado: PID=12345
[2025-12-16 14:23:45 UTC] Enrutamiento completado para chain2-20251216_142300.raw
```

---

### 2. `procesar_cadena_completa.sh` - Orquestador de Contenedores

**Ubicación:** `~lanotadm/bin/procesar_cadena_completa.sh`

**Función:** Coordina los tres pasos de procesamiento para satélites modernos

**Contenedores utilizados:**

| Paso | Contenedor | Función | Tiempo estimado |
|------|------------|---------|----------------|
| 1 | `rt_stps_7.0.sif` | RAW → Level 0 (RDR) | 2-5 min |
| 2 | `cspp_sdr_v4.1.sif` | Level 0 → Level 1 (SDR) | 5-10 min |
| 3 | `polar2grid_v3.1.sif` | Level 1 → GeoTIFF | 3-7 min |

**Características:**
- ✅ Modo estricto: `set -euo pipefail` (aborta en cualquier error)
- ✅ Detección automática de satélite por nombre de archivo
- ✅ Logs separados por contenedor y timestamp
- ✅ Limpieza automática de archivos temporales
- ✅ Contadores de archivos generados en cada paso
- ✅ Resumen final con rutas de productos

**Ejemplo de salida:**
```
==============================================================================
[2025-12-16 14:23:45] INICIO PROCESAMIENTO: chain2-20251216_142300.raw
==============================================================================
[2025-12-16 14:23:45] Satélite detectado: Suomi-NPP
[2025-12-16 14:23:45] Configuración XML: npp.xml

------------------------------------------------------------------------------
[2025-12-16 14:23:45] PASO 1/3: RT-STPS - Decodificación RAW → Level 0
------------------------------------------------------------------------------
[2025-12-16 14:28:12] RT-STPS completado exitosamente. Archivos RDR generados: 15

------------------------------------------------------------------------------
[2025-12-16 14:28:15] PASO 2/3: CSPP SDR - Calibración Level 0 → Level 1
------------------------------------------------------------------------------
[2025-12-16 14:35:42] CSPP SDR completado exitosamente. Archivos SDR generados: 28

------------------------------------------------------------------------------
[2025-12-16 14:35:45] PASO 3/3: Polar2Grid - Generación de imágenes GeoTIFF
------------------------------------------------------------------------------
[2025-12-16 14:41:23] Polar2Grid completado exitosamente. Imágenes generadas: 2

==============================================================================
[2025-12-16 14:41:23] PROCESAMIENTO COMPLETADO EXITOSAMENTE
==============================================================================
Archivo procesado: chain2-20251216_142300.raw
Satélite: NPP

Resultados:
  - Level 0 (RDR):  /data/products/level0  (15 archivos)
  - Level 1 (SDR):  /data/products/level1  (28 archivos)
  - GeoTIFF:        /data/products/geotiff  (2 archivos)

Logs disponibles en: /var/log/lanot/polares
==============================================================================
```

---

## 🚀 Guía de Uso

### Uso Normal (Automático)

El sistema funciona automáticamente cuando la antena receptora descarga un archivo RAW. **No requiere intervención manual.**

### Uso Manual (Reprocesamiento)

Si necesitas reprocesar un archivo RAW manualmente:

```bash
# 1. Verificar que el archivo RAW existe
ls -lh /data/raw/chain2-20251216_142300.raw

# 2. Ejecutar el despachador (simula recepción)
/home/lanotadm/bin/recibe.sh /data/raw/chain2-20251216_142300.raw

# 3. Monitorear progreso en tiempo real
tail -f /var/log/lanot/polares/cadena/$(date +%Y%m%d)_*.log
```

### Procesamiento Directo (Saltando `recibe.sh`)

Si solo quieres procesar un satélite moderno:

```bash
# Ejecutar directamente el orquestador
/home/lanotadm/bin/procesar_cadena_completa.sh /data/raw/chain2-20251216_142300.raw
```

---

## 🔧 Solución de Problemas

### 1. Error: "Satélite no reconocido"

**Síntoma:**
```
ERROR: No se pudo identificar el satélite desde el nombre: archivo.raw
```

**Causa:** El nombre del archivo no sigue los patrones esperados (`chain2-*`, `chain6-*`, etc.)

**Solución:**
1. Verificar el nombre del archivo:
   ```bash
   ls -l /data/raw/
   ```
2. Renombrar si es necesario:
   ```bash
   mv archivo.raw chain2-$(date +%Y%m%d_%H%M%S).raw
   ```

---

### 2. Error: "RT-STPS falló"

**Síntoma:**
```
ERROR: RT-STPS falló. Revise log: /var/log/lanot/polares/rt-stps/20251216_142345_NPP.log
```

**Diagnóstico:**
```bash
# Ver últimas líneas del log
tail -50 /var/log/lanot/polares/rt-stps/20251216_142345_NPP.log

# Buscar errores específicos
grep -i "error\|exception\|failed" /var/log/lanot/polares/rt-stps/20251216_142345_NPP.log
```

**Causas comunes:**

| Error en log | Causa | Solución |
|--------------|-------|----------|
| `LeapSecondException` | `leapsec.dat` desactualizado | Actualizar archivo (ver sección Mantenimiento) |
| `FileNotFoundException` | Archivo RAW corrupto | Solicitar retransmisión |
| `Java heap space` | Memoria insuficiente | Revisar uso de RAM del servidor |
| `Config file not found` | XML de satélite faltante | Verificar `/data/opt/RT-STPS/rt-stps/config/` |

---

### 3. Error: "CSPP SDR falló"

**Diagnóstico:**
```bash
tail -50 /var/log/lanot/polares/cspp-sdr/20251216_142812_NPP.log
```

**Causas comunes:**

| Error en log | Causa | Solución |
|--------------|-------|----------|
| `No ancillary data found` | LUTs desactualizados | Ejecutar `ancillary_download.sh` (ver Mantenimiento) |
| `RDR file corrupt` | Fallo en paso 1 (RT-STPS) | Revisar logs de RT-STPS |
| `Out of memory` | Procesos paralelos excesivos | Reducir `-p 12` a `-p 4` en el script |

---

### 4. Error: "No se encontró archivo RDR"

**Síntoma:**
```
ERROR: No se encontró archivo RDR generado por RT-STPS
```

**Causa:** RT-STPS finalizó pero no generó archivos HDF5

**Solución:**
```bash
# Verificar directorio Level 0
ls -lht /data/products/level0/ | head -20

# Si está vacío, RT-STPS falló silenciosamente
# Revisar log de RT-STPS para identificar el problema
```

---

### 5. Verificar Estado de Contenedores

```bash
# Verificar que los contenedores existen
ls -lh /opt/containers/*.sif

# Probar funcionamiento básico
apptainer exec /opt/containers/rt_stps_7.0.sif ./bin/batch.sh --help
apptainer exec /opt/containers/cspp_sdr_v4.1.sif viirs_sdr.sh --version
apptainer exec /opt/containers/polar2grid_v3.1.sif polar2grid.sh --version
```

---

## 🔄 Mantenimiento

### 1. Actualización de Leap Seconds (Cada 6 meses)

```bash
# Descargar versión actualizada
wget -O /data/ancillary/common/leapsec.dat \
    ftp://is.sci.gsfc.nasa.gov/ancillary/temporal/leapsec.dat

# Verificar última fecha registrada
tail -1 /data/ancillary/common/leapsec.dat
```

### 2. Actualización de Datos Auxiliares (Automatizar con cron)

```bash
# Agregar a crontab de lanotadm (crontab -e)
# Ejecutar todos los lunes a las 3 AM
0 3 * * 1 apptainer exec /opt/containers/cspp_sdr_v4.1.sif \
    ancillary_download.sh /data/ancillary 2>&1 | \
    tee -a /var/log/lanot/polares/cadena/ancillary_update.log
```

### 3. Limpieza de Logs Antiguos

```bash
# Configurar logrotate: /etc/logrotate.d/lanot-polares
/var/log/lanot/polares/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 lanotadm lanotadm
}

# Aplicar configuración
sudo logrotate -f /etc/logrotate.d/lanot-polares
```

### 4. Monitoreo de Espacio en Disco

```bash
# Ver uso de disco por directorio
du -sh /data/products/*

# Limpiar datos antiguos (ejemplo: más de 30 días)
find /data/products/level0 -name "*.h5" -mtime +30 -delete
find /data/products/level1 -name "*.h5" -mtime +30 -delete
```

### 5. Revisión de Logs Diarios

```bash
# Ver actividad del día
cat /var/log/lanot/polares/cadena/$(date +%Y%m%d)_recibe.log

# Buscar errores en todas las ejecuciones del día
grep -i error /var/log/lanot/polares/cadena/$(date +%Y%m%d)_*.log

# Contar procesamiento exitoso vs fallidos (últimos 7 días)
find /var/log/lanot/polares -name "*.log" -mtime -7 | \
    xargs grep -l "COMPLETADO EXITOSAMENTE" | wc -l
```

---

## 📞 Contacto y Soporte

Para dudas o problemas:
- **Documentación completa:** `migracion_polares.md`
- **Logs del sistema:** `/var/log/lanot/polares/`
- **Equipo LANOT:** [contacto interno]

---

**Última actualización:** Diciembre 2025  
**Versión del documento:** 1.0
