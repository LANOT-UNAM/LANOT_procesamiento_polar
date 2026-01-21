import os

# Mapeo de APIDs según la lógica de JPSS-1 (NOAA-20)
# Separamos los APIDs por el sensor al que pertenecen
config_sensores = {
    "VIIRS": {"vcid": 6,  "apids": range(800, 824)},
    "ATMS":  {"vcid": 11, "apids": [515, 528, 530, 531]},
    "CRIS":  {"vcid": 13, "apids": range(1280, 1401)},
    "OMPS":  {"vcid": 16, "apids": range(560, 601)},
    "RNSCA": {"vcid": 0,  "apids": range(0, 128)} # Incluimos navegación por separado
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

# Generamos los <path> usando la sintaxis exacta de tu jpss2.xml
for sensor, data in config_sensores.items():
    vcid = data['vcid']
    # Usamos los atributos que vimos en tu sed: label, spacecraft, etc.
    xml += f'        <path label="VCID{vcid}" spacecraft="spid1" maxRationalPacketSize="65535" OCFpresent="true">\n'
    for apid in data['apids']:
        xml += f'            <pklink appid="{apid}" label="{sensor}_{apid}"/>\n'
    xml += '        </path>\n'

xml += """    </ccsds_services>

    <links>
"""

# Definimos los targets RDR nativos (los que vimos en tus logs anteriores)
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
        xml += f'        <link from="{sensor}_{apid}" to="{target}"/>\n'

xml += """    </links>
</rt_stps>
"""

output_path = "config/jpss1.xml"
with open(output_path, "w") as f:
    f.write(xml)

print(f"✅ XML V5 Generado exitosamente.")

