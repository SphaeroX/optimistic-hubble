"""
Global configuration, path setups, and footprint constants for the Voice Recorder PCB.
"""

import os
import sys

# Configure KiCad 8 environment paths
KICAD_INSTALL_DIR = r"C:\Program Files\KiCad\8.0"
KICAD_SYMBOLS_DIR = os.path.join(KICAD_INSTALL_DIR, "share", "kicad", "symbols")
KICAD_FOOTPRINTS_DIR = os.path.join(KICAD_INSTALL_DIR, "share", "kicad", "footprints")

os.environ["KICAD8_SYMBOL_DIR"] = KICAD_SYMBOLS_DIR
os.environ["KICAD_SYMBOL_DIR"] = KICAD_SYMBOLS_DIR
os.environ["KICAD8_FOOTPRINT_DIR"] = KICAD_FOOTPRINTS_DIR
os.environ["KICAD_FOOTPRINT_DIR"] = KICAD_FOOTPRINTS_DIR

# Base hardware directory
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CUSTOM_SYMBOLS_DIR = os.path.join(BASE_DIR, "symbols")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Standard SMD Footprints (KiCad 8 naming convention)
FOOTPRINTS = {
    "R_0603": "Resistor_SMD:R_0603_1608Metric",
    "R_0805": "Resistor_SMD:R_0805_2012Metric",
    "C_0603": "Capacitor_SMD:C_0603_1608Metric",
    "C_0805": "Capacitor_SMD:C_0805_2012Metric",
    "C_1206": "Capacitor_SMD:C_1206_3216Metric",
    "LED_0805": "LED_SMD:LED_0805_2012Metric",
    "LED_0603": "LED_SMD:LED_0603_1608Metric",
    "DIODE_SOD123": "Diode_SMD:D_SOD-123",
    "DIODE_SOT23": "Package_TO_SOT_SMD:SOT-23",
    "MOSFET_SOT23": "Package_TO_SOT_SMD:SOT-23",
    "LDO_SOT23_5": "Package_TO_SOT_SMD:SOT-23-5",
    "USBLC6_SOT23_6": "Package_TO_SOT_SMD:SOT-23-6",
    "USB_C_16P": "Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12",
    "JST_PH_2P": "Connector_JST:JST_PH_S2B-PH-K_1x02_P2.00mm_Horizontal",
    "SW_PUSH_SMD": "Button_Switch_SMD:SW_SPST_PTS645",
    "SW_SLIDE_SMD": "Button_Switch_SMD:SW_SPDT_PCM12",
    "ESP32C3_WROOM02": "RF_Module:ESP32-C3-WROOM-02",
    "INMP441_MIC": "Sensor_Audio:InvenSense_INMP441",
    "ICS43434_MIC": "Sensor_Audio:InvenSense_ICS-43434-6_3.5x2.65mm",
    "LSM6DS3_LGA14": "Package_LGA:LGA-14_3x2.5mm_P0.5mm_LayoutBorder1x6y",
    "W25Q128_SOIC8": "Package_SO:SOIC-8_5.23x5.23mm_P1.27mm",
    "TP4056_SOP8": "Package_SO:SOP-8-PP_3.9x4.9mm_P1.27mm_EP",
    "TEST_PAD": "TestPoint:TestPoint_Pad_D1.0mm_OD2.0mm",
}
