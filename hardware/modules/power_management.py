"""
Power Management Subsystem (PMU) for the Voice Assistant Device.

Features:
- USB-C 16-Pin Receptacle with CC1/CC2 5.1k pulldowns for USB-PD compatibility.
- High-Speed ESD protection array (USBLC6-2SC6) on VBUS, USB_D+, USB_D-.
- Standalone Linear LiPo Battery Charger (TP4056) with 500mA charge current & dual status LEDs.
- Automatic Power-Path / Ideal Diode circuit (P-MOSFET AO3401A + Schottky diode) for seamless switching between USB 5V and Battery.
- Ultra-Low-Noise 3.3V LDO Voltage Regulator (AP2112K-3.3, 600mA / 1A peak) with input/output ceramic filtering.
- JST-PH 2.0mm LiPo battery connector and SPDT power switch.
- Precision Battery Voltage Divider (2x 100k 1% + filter cap) for ESP32-C3 ADC battery monitoring.
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_power_management(nets):
    """
    Creates and wires the Power Management Unit.
    
    Args:
        nets (dict): Dictionary of shared nets (VBUS, VBAT, V_SYS, +3V3, GND, USB_DP, USB_DN, BATT_SENSE).
    """
    vbus = nets['VBUS']
    vbat = nets['VBAT']
    vbat_raw = nets['VBAT_RAW']
    v_sys = nets['V_SYS']
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    usb_dp = nets['USB_DP']
    usb_dn = nets['USB_DN']
    batt_sense = nets['BATT_SENSE']

    # -------------------------------------------------------------------------
    # 1. USB-C 16-Pin Receptacle
    # -------------------------------------------------------------------------
    usb_c = Part(
        'Connector', 'USB_C_Receptacle_USB2.0_16P',
        footprint=FOOTPRINTS['USB_C_16P'],
        value='TYPE-C-16P'
    )
    
    # Power & Ground
    usb_c['A1,B1,A12,B12'] += gnd
    usb_c['A4,B4,A9,B9'] += vbus
    
    # USB Data Lines
    usb_c['A6,B6'] += usb_dp
    usb_c['A7,B7'] += usb_dn
    
    # CC Pulldown Resistors (5.1k 1% for standard 5V/3A USB-C downstream device)
    r_cc1 = Part('Device', 'R', value='5.1k_1%', footprint=FOOTPRINTS['R_0603'])
    r_cc2 = Part('Device', 'R', value='5.1k_1%', footprint=FOOTPRINTS['R_0603'])
    usb_c['A5'] += r_cc1[1]
    r_cc1[2] += gnd
    usb_c['B5'] += r_cc2[1]
    r_cc2[2] += gnd

    # USB Receptacle Shield Grounding (1M ohm + 4.7nF in parallel for ESD/EMI)
    r_shield = Part('Device', 'R', value='1M', footprint=FOOTPRINTS['R_0805'])
    c_shield = Part('Device', 'C', value='4.7nF_1kV', footprint=FOOTPRINTS['C_0805'])
    usb_c['S1'] += r_shield[1], c_shield[1]
    r_shield[2] += gnd
    c_shield[2] += gnd

    # -------------------------------------------------------------------------
    # 2. High-Speed USB ESD Protection (USBLC6-2SC6)
    # -------------------------------------------------------------------------
    esd = Part(
        'Power_Protection', 'USBLC6-2SC6',
        footprint=FOOTPRINTS['USBLC6_SOT23_6'],
        value='USBLC6-2SC6'
    )
    esd['1,6'] += usb_dp
    esd['3,4'] += usb_dn
    esd['5'] += vbus
    esd['2'] += gnd

    # -------------------------------------------------------------------------
    # 3. LiPo Battery Charger (TP4056)
    # -------------------------------------------------------------------------
    tp4056 = Part(
        'Project_Symbols', 'TP4056',
        footprint=FOOTPRINTS['TP4056_SOP8'],
        value='TP4056'
    )
    
    # Decoupling Caps
    c_vbus = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_vbus[1] += vbus
    c_vbus[2] += gnd

    c_bat = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_bat[1] += vbat_raw
    c_bat[2] += gnd

    # Power & Control Pins
    tp4056['VCC'] += vbus
    tp4056['CE'] += vbus
    tp4056['TEMP'] += gnd
    tp4056['GND,EPAD'] += gnd
    tp4056['BAT'] += vbat_raw

    # Charge Current Programming Resistor (2.4k -> ~500mA Charge Rate)
    r_prog = Part('Device', 'R', value='2.4k_1%', footprint=FOOTPRINTS['R_0603'])
    tp4056['PROG'] += r_prog[1]
    r_prog[2] += gnd

    # Charging Status LEDs (Red = Charging, Green = Standby/Complete)
    r_chrg = Part('Device', 'R', value='1k', footprint=FOOTPRINTS['R_0603'])
    led_chrg = Part('Device', 'LED', value='RED_CHRG', footprint=FOOTPRINTS['LED_0603'])
    vbus += r_chrg[1]
    r_chrg[2] += led_chrg[2]  # Anode
    led_chrg[1] += tp4056['~{CHRG}']  # Cathode

    r_stdby = Part('Device', 'R', value='1k', footprint=FOOTPRINTS['R_0603'])
    led_stdby = Part('Device', 'LED', value='GRN_FULL', footprint=FOOTPRINTS['LED_0603'])
    vbus += r_stdby[1]
    r_stdby[2] += led_stdby[2]  # Anode
    led_stdby[1] += tp4056['~{STDBY}']  # Cathode

    # -------------------------------------------------------------------------
    # 4. Battery Connector & Main Power Slide Switch
    # -------------------------------------------------------------------------
    j_bat = Part(
        'Connector', 'Conn_01x02_Pin',
        footprint=FOOTPRINTS['JST_PH_2P'],
        value='JST-PH-2P-LiPo'
    )
    j_bat[1] += vbat_raw
    j_bat[2] += gnd

    sw_pwr = Part(
        'Switch', 'SW_SPDT',
        footprint=FOOTPRINTS['SW_SLIDE_SMD'],
        value='POWER_SWITCH'
    )
    sw_pwr[1] += vbat_raw  # Input from Battery
    sw_pwr[2] += vbat      # Switched Battery rail
    # Pin 3 is left open/NC

    # -------------------------------------------------------------------------
    # 5. Automatic Power-Path / Ideal Diode Circuit
    # -------------------------------------------------------------------------
    # P-MOSFET (AO3401A): Source = VBAT, Drain = V_SYS, Gate = VBUS + 100k pulldown
    q_pwr = Part(
        'Transistor_FET', 'AO3401A',
        footprint=FOOTPRINTS['MOSFET_SOT23'],
        value='AO3401A_P-FET'
    )
    q_pwr['S'] += vbat
    q_pwr['D'] += v_sys
    q_pwr['G'] += vbus

    r_gate_pd = Part('Device', 'R', value='100k', footprint=FOOTPRINTS['R_0603'])
    r_gate_pd[1] += q_pwr['G']
    r_gate_pd[2] += gnd

    # Schottky Diode (SS14 / BAT54C) from VBUS to V_SYS
    d_vbus = Part(
        'Device', 'D_Schottky',
        footprint=FOOTPRINTS['DIODE_SOD123'],
        value='SS14_Schottky'
    )
    d_vbus[2] += vbus   # Anode
    d_vbus[1] += v_sys  # Cathode

    # -------------------------------------------------------------------------
    # 6. Ultra-Low-Noise 3.3V LDO Voltage Regulator (AP2112K-3.3)
    # -------------------------------------------------------------------------
    ldo = Part(
        'Regulator_Linear', 'AP2112K-3.3',
        footprint=FOOTPRINTS['LDO_SOT23_5'],
        value='AP2112K-3.3'
    )
    
    # Input Decoupling (10uF Ceramic on V_SYS)
    c_ldo_in = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_ldo_in[1] += v_sys
    c_ldo_in[2] += gnd

    # Power & Enable
    ldo['VIN'] += v_sys
    ldo['EN'] += v_sys
    ldo['GND'] += gnd
    ldo['VOUT'] += pwr_3v3

    # Output Decoupling (10uF + 100nF Ceramic on +3V3)
    c_ldo_out1 = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_ldo_out2 = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_ldo_out1[1] += pwr_3v3
    c_ldo_out1[2] += gnd
    c_ldo_out2[1] += pwr_3v3
    c_ldo_out2[2] += gnd

    # -------------------------------------------------------------------------
    # 7. Battery Voltage Monitor (High-Z Divider to ADC)
    # -------------------------------------------------------------------------
    r_bat1 = Part('Device', 'R', value='100k_1%', footprint=FOOTPRINTS['R_0603'])
    r_bat2 = Part('Device', 'R', value='100k_1%', footprint=FOOTPRINTS['R_0603'])
    c_bat_filt = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])

    vbat += r_bat1[1]
    r_bat1[2] += batt_sense
    batt_sense += r_bat2[1], c_bat_filt[1]
    r_bat2[2] += gnd
    c_bat_filt[2] += gnd

    return {
        "usb_c": usb_c,
        "esd": esd,
        "tp4056": tp4056,
        "ldo": ldo,
        "q_pwr": q_pwr,
        "j_bat": j_bat,
        "sw_pwr": sw_pwr,
    }
