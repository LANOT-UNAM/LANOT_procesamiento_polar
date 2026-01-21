import os

# --- CONFIGURACIÓN DE RUTAS ---
# Mapeo de Sensores a sus "Application Entities" (AE) nativos de RT-STPS.
# Si no enviamos los paquetes de navegación (RNSCA) al VIIRS, el archivo saldrá PURO.
config = {
    "VIIRS": {
        "apids": range(800, 824),
        "target": "VIIRS_SCI_AE_RDR",
        "vcid": 6
    },
    "ATMS": {
        "apids": [515] + list(range(528, 532)),
        "target": "ATMS_SCI_AE_RDR",
        "vcid": 11
    },
    "CRIS": {
        "apids": range(1280, 1401),
        "target": "CRIS_SCI_AE_RDR",
        "vcid": 13
    },
    "OMPS": {
        "apids": range(560, 601),
        "target": "OMPS_NPSCI_AE_RDR",
        "vcid": 16
    }
    # NOTA: Omitimos RNSCA (VCID 0) explícitamente para evitar que ensucie los archivos de ciencia.
    # Si RT-STPS genera un RNSCA por defecto, bien. Si no, al menos VIIRS funcionará.
}

# --- GENERACIÓN DEL XML ---
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

# Generamos los Paths con los atributos OBLIGATORIOS: label, channel_link, spacecraft
for sensor, data in config.items():
    vcid = data['vcid']
    # Aquí estaba el error anterior: faltaba channel_link
    xml += f'        <path label="PATH_{sensor}" channel_link="VCID{vcid}" spacecraft="spid1">\n'
    
    for apid in data['apids']:
        pk_label = f"{sensor}_{apid}"
        xml += f'            <pklink appid="{apid}" label="{pk_label}"/>\n'
    
    xml += '        </path>\n'

# Agregamos path para RNSCA (VCID 0) aunque no lo linkeemos, para que no dé error de estructura
xml += '        <path label="PATH_RNSCA" channel_link="VCID0" spacecraft="spid1">\n'
xml += '            <pklink appid="0" label="RNSCA_0"/>\n'
xml += '        </path>\n'

xml += """    </ccsds_services>

    <links>
"""

# Conectamos cada paquete a su RDR destino
for sensor, data in config.items():
    target_rdr = data['target']
    xml += f'\n        \n'
    for apid in data['apids']:
        pk_label = f"{sensor}_{apid}"
        xml += f'        <link from="{pk_label}" to="{target_rdr}"/>\n'

xml += """    </links>
</rt_stps>
"""

# Guardar
output_path = "config/jpss1.xml"
with open(output_path, "w") as f:
    f.write(xml)

print(f"✅ XML V4 (Definitivo) generado en: {output_path}")

