import os

# CONFIGURACIÓN: Lista de APIDs por sensor (Filtros estrictos)
sensores = {
    "RVIIRS": list(range(800, 824)),          # VIIRS Ciencia
    "RATMS":  [515] + list(range(528, 532)),  # ATMS Ciencia
    "RCRIS":  list(range(1280, 1401)),        # CrIS Ciencia
    "ROMPS":  list(range(560, 601)),          # OMPS Ciencia
    "RNSCA":  list(range(0, 128))             # Navegación
}

# Mapeo de Canales Virtuales (VCID) a Sensores
vcid_map = {
    6:  "RVIIRS",
    11: "RATMS",
    13: "RCRIS",
    16: "ROMPS",
    0:  "RNSCA",
    1:  "RNSCA",
    24: "RNSCA"
}

# --- INICIO DEL XML ---
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

# Generar Paths (Aquí estaba el error: faltaba spacecraft="spid1")
for vcid, sensor_label in vcid_map.items():
    # CORRECCIÓN: Se agrega spacecraft="spid1"
    xml += f'        <path label="PATH_VC{vcid}" channel_link="VCID{vcid}" spacecraft="spid1">\n'
    
    apid_list = sensores[sensor_label]
    for apid in apid_list:
        pk_label = f"{sensor_label}_{apid}"
        xml += f'            <pklink appid="{apid}" label="{pk_label}"/>\n'
    
    xml += '        </path>\n'

xml += """    </ccsds_services>

    """

# Definir los contenedores RDR
for sensor in sensores.keys():
    xml += f'    <rdr label="{sensor}"/>\n'

xml += """
    """

# Generar los Links finales
for sensor_label, apid_list in sensores.items():
    xml += f'\n    \n'
    for apid in apid_list:
        pk_label = f"{sensor_label}_{apid}"
        # Conectamos el paquete individual al RDR correspondiente
        xml += f'    <link from="{pk_label}" to="{sensor_label}"/>\n'

xml += "</rt_stps>"

# Guardar archivo
output_path = "config/jpss1.xml"
with open(output_path, "w") as f:
    f.write(xml)

print(f"✅ XML Generado en: {output_path}")

