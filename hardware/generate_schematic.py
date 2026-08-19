#!/usr/bin/env python3
"""
Main Schematic Generator & Dual-Export Pipeline for KiCad & EasyEDA.

Generates:
1. hardware/output/kicad/
   - xiao_voice_recorder.kicad_pro (KiCad 8 Project)
   - xiao_voice_recorder.kicad_sch (Fully wired and labeled schematic)
   - xiao_voice_recorder.kicad_pcb (PCB layout)
   - xiao_voice_recorder.net (KiCad Netlist)
   - xiao_voice_recorder.xml (XML Netlist)
   - xiao_voice_recorder_bom.csv (KiCad BOM)
   - sym-lib-table & fp-lib-table (Libraries)

2. hardware/output/easyeda/
   - xiao_voice_recorder_easyeda_import.zip (1-Click EasyEDA Online Import Archive)
   - xiao_voice_recorder_easyeda.json (EasyEDA Standard JSON Schematic)
   - xiao_voice_recorder.epro (EasyEDA Pro Project)
   - xiao_voice_recorder_jlcpcb_bom.csv (SMT Assembly BOM with LCSC C-Numbers)
   - README_EASYEDA_IMPORT.md (Step-by-Step Import Instructions)
"""

import os
import sys
import csv
import builtins

# Add workspace and hardware directory to path
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
sys.path.insert(0, PROJECT_ROOT)

from hardware.config import (
    KICAD_SYMBOLS_DIR,
    CUSTOM_SYMBOLS_DIR,
    OUTPUT_DIR,
    KICAD_OUTPUT_DIR,
    EASYEDA_OUTPUT_DIR,
    FOOTPRINTS,
)

from skidl import *

# Configure SKiDL for KiCad 8
set_default_tool(KICAD8)
if CUSTOM_SYMBOLS_DIR not in lib_search_paths[KICAD8]:
    lib_search_paths[KICAD8].append(CUSTOM_SYMBOLS_DIR)
if KICAD_SYMBOLS_DIR not in lib_search_paths[KICAD8]:
    lib_search_paths[KICAD8].append(KICAD_SYMBOLS_DIR)

from hardware.modules.power_management import create_power_management
from hardware.modules.esp32c3_core import create_esp32c3_core
from hardware.modules.audio_mems import create_audio_mems
from hardware.modules.imu_sensor import create_imu_sensor
from hardware.modules.spi_storage import create_spi_storage
from hardware.modules.ui_indicators import create_ui_indicators
from hardware.kicad_project_generator import generate_kicad_project
from hardware.easyeda_generator import generate_easyeda_output

def build_circuit():
    """Builds the complete multi-subsystem circuit netlist."""
    print("=" * 70)
    print("Building ESP32-C3 Dual-Mic Voice Assistant Schematic...")
    print("=" * 70)

    # -------------------------------------------------------------------------
    # Global Net Definitions
    # -------------------------------------------------------------------------
    nets = {
        # Power Rails
        'VBUS': Net('VBUS'),
        'VBAT_RAW': Net('VBAT_RAW'),
        'VBAT': Net('VBAT'),
        'V_SYS': Net('V_SYS'),
        '+3V3': Net('+3V3'),
        'GND': Net('GND'),
        
        # USB Interface
        'USB_DP': Net('USB_DP'),
        'USB_DN': Net('USB_DN'),
        
        # Audio Bus (I2S)
        'I2S_SCK': Net('I2S_SCK'),
        'I2S_WS': Net('I2S_WS'),
        'I2S_SD': Net('I2S_SD'),
        
        # Sensor Bus (I2C) & Interrupts
        'I2C_SCL': Net('I2C_SCL'),
        'I2C_SDA': Net('I2C_SDA'),
        'IMU_INT': Net('IMU_INT'),
        
        # Storage Bus (SPI)
        'SPI_CS': Net('SPI_CS'),
        'SPI_CLK': Net('SPI_CLK'),
        'SPI_MISO': Net('SPI_MISO'),
        'SPI_MOSI': Net('SPI_MOSI'),
        
        # UI & Sensing
        'STATUS_LED': Net('STATUS_LED'),
        'BATT_SENSE': Net('BATT_SENSE'),
    }

    # Tag power and ground nets for ERC
    nets['+3V3'].drive = POWER
    nets['GND'].drive = POWER
    nets['VBUS'].drive = POWER
    nets['VBAT'].drive = POWER

    # -------------------------------------------------------------------------
    # Instantiate Subsystems
    # -------------------------------------------------------------------------
    print("1. Adding Power Management Unit (USB-C, TP4056, Power-Path, AP2112K LDO)...")
    pmu = create_power_management(nets)

    print("2. Adding ESP32-C3 Microcontroller Core (Reset RC, Boot Strapping, USB)...")
    mcu = create_esp32c3_core(nets)

    print("3. Adding Dual I2S MEMS Microphones (Phase-Aligned Stereo Beamforming)...")
    audio = create_audio_mems(nets)

    print("4. Adding LSM6DS3 Motion Sensor (Tap-to-Record Hardware Interrupt)...")
    imu = create_imu_sensor(nets)

    print("5. Adding External Winbond 16MB SPI Flash Storage...")
    storage = create_spi_storage(nets)

    print("6. Adding UI Indicators (Status LED, Power LED, Test Points)...")
    ui = create_ui_indicators(nets)

    print("-" * 70)
    print("Circuit graph constructed successfully!")
    return nets

def export_artifacts():
    """Generates and exports all KiCad and EasyEDA files."""
    circuit = builtins.default_circuit
    project_name = "xiao_voice_recorder"
    
    # -------------------------------------------------------------------------
    # 1. Generate KiCad Project Files (hardware/output/kicad/)
    # -------------------------------------------------------------------------
    print("\n" + "=" * 30 + " 1. KICAD 8 OUTPUT " + "=" * 30)
    netlist_path = os.path.join(KICAD_OUTPUT_DIR, f"{project_name}.net")
    xml_path = os.path.join(KICAD_OUTPUT_DIR, f"{project_name}.xml")
    bom_path = os.path.join(KICAD_OUTPUT_DIR, f"{project_name}_bom.csv")

    print("[KiCad Netlist] ->", netlist_path)
    generate_netlist(file_=netlist_path)

    print("[KiCad XML Netlist] ->", xml_path)
    generate_xml(file_=xml_path)

    generate_kicad_project(circuit, output_dir=KICAD_OUTPUT_DIR, project_name=project_name)

    print("[KiCad BOM] ->", bom_path)
    export_custom_bom(bom_path, circuit)

    # -------------------------------------------------------------------------
    # 2. Generate EasyEDA Output Files (hardware/output/easyeda/)
    # -------------------------------------------------------------------------
    print("\n" + "=" * 30 + " 2. EASYEDA OUTPUT " + "=" * 30)
    generate_easyeda_output(
        circuit=circuit,
        kicad_dir=KICAD_OUTPUT_DIR,
        easyeda_dir=EASYEDA_OUTPUT_DIR,
        project_name=project_name
    )

    print("\n" + "=" * 70)
    print("ALL HARDWARE PROJECT ARTIFACTS GENERATED SUCCESSFULLY!")
    print(f"KiCad Project Folder:   {KICAD_OUTPUT_DIR}")
    print(f"EasyEDA Project Folder: {EASYEDA_OUTPUT_DIR}")
    print("=" * 70)

def export_custom_bom(filepath, circuit):
    """Exports a grouped and formatted Bill of Materials CSV."""
    parts = circuit.parts
    bom_dict = {}
    
    for p in parts:
        ref = p.ref
        val = str(p.value)
        fp = str(p.footprint) if p.footprint else "Unspecified"
        desc = getattr(p, 'description', '')
        
        key = (val, fp)
        if key not in bom_dict:
            bom_dict[key] = {
                "value": val,
                "footprint": fp,
                "refs": [ref],
                "description": desc,
            }
        else:
            bom_dict[key]["refs"].append(ref)

    with open(filepath, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Item", "Designators", "Qty", "Value", "Footprint", "Description"])
        
        item = 1
        for key, data in sorted(bom_dict.items(), key=lambda x: (x[1]["refs"][0][0], x[1]["value"])):
            refs_str = ", ".join(sorted(data["refs"]))
            qty = len(data["refs"])
            writer.writerow([
                item,
                refs_str,
                qty,
                data["value"],
                data["footprint"],
                data["description"]
            ])
            item += 1

if __name__ == "__main__":
    nets = build_circuit()
    export_artifacts()
