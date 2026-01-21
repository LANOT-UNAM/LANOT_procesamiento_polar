import os

# --- 1. DEFINICIÓN DE SENSORES Y SUS RDRs NATIVOS ---
# Mapeamos los APIDs a los nombres internos que RT-STPS ya conoce (ver logs).
# Esto asegura que se generen los archivos estándar (RVIIRS, RATMS, etc).

config = {
    # VIIRS Ciencia -> RDR Nativo
    "VIIRS": {
        "apids": range(800, 824),
        "target": "VIIRS_SCI_AE_RDR",
        "vcid": 6
    },
    # ATMS Ciencia -> RDR Nativo
    "ATMS": {
        "apids": [515] + list(range(528, 532)),
        "target": "ATMS_SCI_AE_RDR",
        "vcid": 11
    },
    # CrIS Ciencia -> RDR Nativo
    "CRIS": {
        "apids": range(1280, 1401),
        "target": "CRIS_SCI_AE_RDR",
        "vcid": 13
    },
    # OMPS Ciencia -> RDR Nativo (Usamos NPSCI como principal)
    "OMPS": {
        "apids": range(560, 601),
        "target": "OMPS_NPSCI_AE_RDR",
        "vcid": 16
    },
    # NAVEGACIÓN (Spacecraft Diary)
    # RT-STPS suele rutear esto automáticamente si se define el link.
    # Usaremos una etiqueta genérica que suele funcionar.
    "RNSCA": {
        "apids": range(0, 128),
        "target": "RNSCA_AE_RDR", # Nombre estándar probable
        "vcid": 0 # Principalmente VCID 0, pero también 1 y 24
    }
}

# --- 2. GENERACIÓN DEL XML ---
xml = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rt_stps SYSTEM "rt-stps.dtd">
<rt_stps id="JPSS-1">
    
    <frame_sync frameLength="1024" PnEncoded="true">
        <timestamp epoch="19580101000000"/>
    </frame_sync>
    <reed_solomon useStandardCCSDS="true" doBlockCorrection="true" discardUncorrectables="true" interleave="4"/>

    <spacecrafts>
        <spacecraft label="spid1" id="159"/>
    </spacecrafts>

    <cadu_service>
        <svlink vcid="0" spid="159" label="VCID0"/>
        <svlink vcid="1" spid="159" label="VCID1"/>
        <svlink vcid="6" spid="159" label="VCID6"/>
        <svlink vcid="11" spid="159" label="VCID11"/>
        <svlink vcid="13" spid="159" label="VCID13"/>
        <svlink vcid="16" spid="159" label="VCID16"/>
        <svlink vcid="24" spid="159" label="VCID24"/>
    </cadu_service>

    <ccsds_services>
"""

# Generamos un <path> para cada VCID importante
# NOTA: En v7.0, el 'label' del path debe coincidir con el label del svlink.
vcids_to_process = [0, 1, 6, 11, 13, 16, 24]

for vcid in vcids_to_process:
    # Atributo spacecraft es OBLIGATORIO en v7.0
    xml += f'        <path label="VCID{vcid}" spacecraft="spid1">\n'
    
    # Insertar <pklink> para los APIDs que viajan en este VCID
    for sensor, data in config.items():
        # Lógica simple de asignación por VCID
        match = False
        if sensor == "RNSCA" and vcid in [0, 1, 24]: match = True
        elif sensor == "VIIRS" and vcid == 6: match = True
        elif sensor == "ATMS" and vcid == 11: match = True
        elif sensor == "CRIS" and vcid == 13: match = True
        elif sensor == "OMPS" and vcid == 16: match = True
        
        if match:
            for apid in data['apids']:
                pk_label = f"{sensor}_{apid}"
                # Definimos el paquete dentro del path
                xml += f'            <pklink appid="{apid}" label="{pk_label}"/>\n'
    
    xml += '        </path>\n'

xml += """    </ccsds_services>

    """

# Conectamos cada paquete a su RDR destino
for sensor, data in config.items():
    target_rdr = data['target']
    xml += f'\n    \n'
    for apid in data['apids']:
        pk_label = f"{sensor}_{apid}"
        xml += f'    <link from="{pk_label}" to="{target_rdr}"/>\n'

xml += "</rt_stps>"

# Guardar
output_path = "config/jpss1.xml"
with open(output_path, "w") as f:
    f.write(xml)

print(f"✅ XML V3 generado en: {output_path}")

