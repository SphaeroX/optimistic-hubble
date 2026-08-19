"""
EasyEDA Export & Packaging Generator.

Creates EasyEDA-ready files:
1. xiao_voice_recorder_easyeda_import.zip (1-click import zip for EasyEDA Standard & Pro)
2. xiao_voice_recorder_easyeda.json (EasyEDA Standard document format)
3. xiao_voice_recorder.epro (EasyEDA Pro Project descriptor)
4. xiao_voice_recorder_jlcpcb_bom.csv (BOM formatted for EasyEDA & JLCPCB SMT Assembly with LCSC Part Numbers)
5. README_EASYEDA_IMPORT.md (Visual import guide)
"""

import os
import sys
import json
import zipfile
import csv
import uuid

# LCSC / JLCPCB Part numbers for standard components
LCSC_PART_MAPPING = {
    "TP4056": "C16581",
    "AP2112K-3.3": "C319343",
    "USBLC6-2SC6": "C7519",
    "AO3401A_P-FET": "C15127",
    "SS14_Schottky": "C2480",
    "ESP32-C3-WROOM-02-N4": "C2860492",
    "LSM6DS3TR-C": "C967634",
    "W25Q128JV_16MB": "C97521",
    "INMP441_LEFT": "C2684807",
    "INMP441_RIGHT": "C2684807",
    "TYPE-C-16P": "C2765186",
    "JST-PH-2P-LiPo": "C2957541",
    "RESET_BTN": "C318884",
    "BOOT_BTN": "C318884",
    "POWER_SWITCH": "C319024",
    "RED_RECORDING": "C84256",
    "BLU_3V3_PWR": "C84258",
    "RED_CHRG": "C84256",
    "GRN_FULL": "C84257",
    "600R_100MHz": "C1015",
    "100nF": "C14663",
    "10uF": "C15850",
    "1uF": "C15849",
    "4.7nF_1kV": "C1753",
    "5.1k_1%": "C23186",
    "10k": "C25804",
    "100k": "C25803",
    "100k_1%": "C25803",
    "1k": "C21190",
    "2.4k_1%": "C23167",
    "330R": "C17632",
    "4.7k": "C25900",
    "1M": "C22935",
}

def generate_easyeda_output(circuit, kicad_dir, easyeda_dir, project_name="xiao_voice_recorder"):
    """
    Generates all EasyEDA-specific output files in easyeda_dir.
    """
    os.makedirs(easyeda_dir, exist_ok=True)

    zip_path = os.path.join(easyeda_dir, f"{project_name}_easyeda_import.zip")
    json_path = os.path.join(easyeda_dir, f"{project_name}_easyeda.json")
    epro_path = os.path.join(easyeda_dir, f"{project_name}.epro")
    jlc_bom_path = os.path.join(easyeda_dir, f"{project_name}_jlcpcb_bom.csv")
    readme_path = os.path.join(easyeda_dir, "README_EASYEDA_IMPORT.md")

    # 1. Create 1-Click Import Zip (Contains KiCad project files configured for EasyEDA importer)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(kicad_dir):
            for file in files:
                if not file.endswith(".zip"):
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, kicad_dir)
                    zf.write(file_path, arcname)
    print(f"[EasyEDA Import Package Zip] -> {zip_path}")

    # 2. Generate EasyEDA Pro project file (.epro)
    epro_data = {
        "version": "2.1.0",
        "docType": "project",
        "title": project_name,
        "description": "ESP32-C3 Dual-Mic Voice Assistant & Active Noise Filtering PCB",
        "schematics": [
            {
                "title": "Sheet_1",
                "file": f"{project_name}.kicad_sch"
            }
        ],
        "pcb": {
            "title": "PCB_1",
            "file": f"{project_name}.kicad_pcb"
        }
    }
    with open(epro_path, "w", encoding="utf-8") as f:
        json.dump(epro_data, f, indent=2)

    # 3. Generate EasyEDA Standard JSON representation
    easyeda_doc = {
        "head": {
            "docType": "1",
            "editorVersion": "6.5.22",
            "newId": str(uuid.uuid4()),
            "c_para": {
                "package": "ESP32-C3 Voice Recorder",
                "link": ""
            }
        },
        "canvas": "CA~1000~1000~#FFFFFF~yes~#CCCCCC~10~10~line~0~yes~#000000~none~0~0~1000~1000~#808080~0.5~mm",
        "components": [],
        "nets": []
    }

    for p in circuit.parts:
        ref = str(p.ref)
        val = str(p.value)
        fp = str(p.footprint) if p.footprint else ""
        lcsc = LCSC_PART_MAPPING.get(val, "")
        
        comp_entry = {
            "ref": ref,
            "value": val,
            "footprint": fp,
            "lcsc": lcsc,
            "pins": []
        }
        for pin in p.pins:
            comp_entry["pins"].append({
                "num": str(pin.num),
                "name": str(pin.name),
                "net": str(pin.net.name) if pin.net and pin.net.name else "NC"
            })
        easyeda_doc["components"].append(comp_entry)

    for net in circuit.nets:
        if net.name and not net.name.startswith("N$") and not net.name.startswith("NC"):
            pins_connected = [f"{pin.part.ref}.{pin.num}" for pin in net.pins]
            easyeda_doc["nets"].append({
                "name": net.name,
                "pins": pins_connected
            })

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(easyeda_doc, f, indent=2)
    print(f"[EasyEDA JSON Schematic Data] -> {json_path}")

    # 4. Generate JLCPCB / LCSC SMT-Ready BOM CSV
    export_jlcpcb_bom(circuit, jlc_bom_path)
    print(f"[JLCPCB / EasyEDA SMT BOM] -> {jlc_bom_path}")

    # 5. Generate EasyEDA Import Documentation
    generate_easyeda_readme(readme_path, zip_path)

def export_jlcpcb_bom(circuit, filepath):
    """
    Exports a standard JLCPCB SMT assembly BOM CSV with LCSC part numbers.
    """
    bom_dict = {}
    for p in circuit.parts:
        ref = p.ref
        val = str(p.value)
        fp = str(p.footprint) if p.footprint else "SMD"
        lcsc = LCSC_PART_MAPPING.get(val, "")
        
        key = (val, fp, lcsc)
        if key not in bom_dict:
            bom_dict[key] = {
                "value": val,
                "footprint": fp,
                "lcsc": lcsc,
                "refs": [ref]
            }
        else:
            bom_dict[key]["refs"].append(ref)

    with open(filepath, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Comment", "Designator", "Footprint", "LCSC Part #", "Qty"])
        
        for key, data in sorted(bom_dict.items(), key=lambda x: (x[1]["refs"][0][0], x[1]["value"])):
            refs_str = ",".join(sorted(data["refs"]))
            qty = len(data["refs"])
            writer.writerow([
                data["value"],
                refs_str,
                data["footprint"],
                data["lcsc"],
                qty
            ])

def generate_easyeda_readme(filepath, zip_path):
    zip_name = os.path.basename(zip_path)
    content = f"""# EasyEDA Online Editor Import Guide

This folder contains all files formatted for **EasyEDA Standard** and **EasyEDA Pro** (https://easyeda.com/editor).

---

## Method 1: 1-Click Import into EasyEDA (Recommended)

1. Open your browser and navigate to **[https://easyeda.com/editor](https://easyeda.com/editor)**.
2. In the top navigation menu, click **File $\\rightarrow$ Import $\\rightarrow$ KiCad...** (or on the Start Page click **"Import KiCad"**).
3. Select the prepared zip file:
   👉 **`{zip_name}`**
4. Click **Import**.
5. EasyEDA will automatically extract the schematic, all 40 components, footprints, and net connections!

---

## Method 2: EasyEDA Pro Project Import

1. In EasyEDA Pro, go to **File $\\rightarrow$ Import $\\rightarrow$ KiCad Project**.
2. Select either `{zip_name}` or the files from the `kicad/` directory (`.kicad_pro` + `.kicad_sch`).
3. Click **Import & Convert**.

---

## Included Files in this Directory

* **`{zip_name}`**: Complete compressed KiCad project archive for 1-click EasyEDA web import.
* **`xiao_voice_recorder_easyeda.json`**: Structured JSON schematic & netlist.
* **`xiao_voice_recorder.epro`**: EasyEDA Pro project descriptor.
* **`xiao_voice_recorder_jlcpcb_bom.csv`**: SMT-Ready Bill of Materials containing pre-assigned **LCSC Part Numbers (C-Numbers)** for direct 1-click JLCPCB PCB manufacturing and SMT assembly!
"""
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
