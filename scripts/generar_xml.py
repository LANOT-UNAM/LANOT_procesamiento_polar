import os

# Configuración de APIDs por sensor para NOAA-20 (JPSS-1)
config_sensores = {
    "VIIRS": {"vcid": 6,  "apids": range(800, 824)},
    "ATMS":  {"vcid": 11, "apids": [515, 528, 530, 531]},
    "CRIS":  {"vcid": 13, "apids": range(1280, 1401)},
    "OMPS":  {"vcid": 16, "apids": range(560, 601)},
    "RNSCA": {"vcid": 0,  "apids": range(0, 128)}
}

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

# Definimos los <path> con la sintaxis exacta de RT-STPS 7.0
for sensor, data in config_sensores.items():
    vcid = data['vcid']
    xml += f'        <path label="VCID{vcid}" spacecraft="spid1" maxRationalPacketSize="65535" OCFpresent="true">\n'
    for apid in data['apids']:
        xml += f'            <pklink appid="{apid}" label="ID_{sensor}_{apid}"/>\n'
    xml += '        </path>\n'

xml += """    </ccsds_services>

    <links>
"""

# Mapeo a los Application Entities (AE) nativos
targets = {
    "VIIRS": "VIIRS_SCI_AE_RDR",
    "ATMS":  "ATMS_SCI_AE_RDR",
    "CRIS":  "CRIS_SCI_AE_RDR",
    "OMPS":  "OMPS_NPSCI_AE_RDR",
    "RNSCA": "RNSCA_AE_RDR"
}

for sensor, target in targets.items():
    xml += f'\n        \n'
    for apid in config_sensores[sensor]['apids']:
        xml += f'        <link from="ID_{sensor}_{apid}" to="{target}"/>\n'

xml += """    </links>
</rt_stps>
"""

# --- CAMBIO DE RUTA ---
output_path = "config/jpss1.xml"
# Aseguramos que la carpeta config exista en el repo antes de escribir
os.makedirs("config", exist_ok=True)

with open(output_path, "w") as f:
    f.write(xml)

print(f"✅ XML generado en tu repositorio: {output_path}")
print("   Ahora puedes hacer 'git status' y 'git diff' para revisarlo.")

