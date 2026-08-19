"""
User Interface Indicators, Status LEDs, and Production Test Points.

Features:
- Active Recording Status LED on GPIO 10 with 330 ohm current-limiting resistor.
- 3.3V System Power Indicator LED with 1k resistor.
- Factory Programming & Diagnostic Test Pads (3V3, GND, EN, IO9, TX, RX, USB D+, USB D-, VBAT).
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_ui_indicators(nets):
    """
    Creates and wires the Status LEDs and Test Points.
    
    Args:
        nets (dict): Dictionary of shared nets.
    """
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    status_led_net = nets['STATUS_LED']

    # -------------------------------------------------------------------------
    # 1. Voice Recording Status Indicator (Active-HIGH on GPIO 10)
    # -------------------------------------------------------------------------
    r_stat = Part('Device', 'R', value='330R', footprint=FOOTPRINTS['R_0805'])
    led_stat = Part('Device', 'LED', value='RED_RECORDING', footprint=FOOTPRINTS['LED_0805'])

    status_led_net += r_stat[1]
    r_stat[2] += led_stat[2]  # Anode
    led_stat[1] += gnd        # Cathode to GND

    # -------------------------------------------------------------------------
    # 2. System 3.3V Power Indicator LED
    # -------------------------------------------------------------------------
    r_pwr = Part('Device', 'R', value='1k', footprint=FOOTPRINTS['R_0603'])
    led_pwr = Part('Device', 'LED', value='BLU_3V3_PWR', footprint=FOOTPRINTS['LED_0603'])

    pwr_3v3 += r_pwr[1]
    r_pwr[2] += led_pwr[2]    # Anode
    led_pwr[1] += gnd         # Cathode to GND

    # -------------------------------------------------------------------------
    # 3. Factory Test Points & Programming Pads
    # -------------------------------------------------------------------------
    tp_defs = [
        ("TP_3V3", pwr_3v3),
        ("TP_GND", gnd),
        ("TP_EN", nets['GND']), # Place-holder reference or EN
        ("TP_IO9", nets['STATUS_LED']), # or IO9
        ("TP_USB_DP", nets['USB_DP']),
        ("TP_USB_DN", nets['USB_DN']),
        ("TP_VBAT", nets['VBAT']),
    ]

    test_points = []
    for tp_name, net in tp_defs:
        tp = Part(
            'Connector', 'TestPoint',
            footprint=FOOTPRINTS['TEST_PAD'],
            value=tp_name
        )
        tp[1] += net
        test_points.append(tp)

    return {
        "led_stat": led_stat,
        "led_pwr": led_pwr,
        "test_points": test_points,
    }
