"""
ESP32-C3 Microcontroller Core Subsystem.

Features:
- ESP32-C3-WROOM-02 Module with integrated 4MB Flash & 2.4GHz PCB Antenna.
- Decoupling capacitor network (10uF bulk + 100nF high-frequency ceramic caps).
- Standard Espressif Reset RC Circuit (10k pull-up + 1uF delay cap) with tactile EN pushbutton.
- Boot Strapping Circuit (10k pull-up on GPIO 9) with tactile BOOT/User pushbutton.
- Direct routing of Native USB D+/D- lines (GPIO 18 / 19) to the protected USB-C interface.
- Complete GPIO mapping for I2S Microphones, I2C IMU, SPI Flash, ADC, and Status LED.
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_esp32c3_core(nets):
    """
    Creates and wires the ESP32-C3 Core module.
    
    Args:
        nets (dict): Dictionary of shared nets.
    """
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    
    # -------------------------------------------------------------------------
    # 1. ESP32-C3-WROOM-02 Module
    # -------------------------------------------------------------------------
    mcu = Part(
        'Project_Symbols', 'ESP32-C3-WROOM-02',
        footprint=FOOTPRINTS['ESP32C3_WROOM02'],
        value='ESP32-C3-WROOM-02-N4'
    )

    # Power & Ground Pins
    mcu['3V3'] += pwr_3v3
    mcu['GND,EPAD'] += gnd

    # Decoupling Capacitors (Placed close to 3V3 pin)
    c_mcu_bulk = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_mcu_hf = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_mcu_bulk[1] += pwr_3v3
    c_mcu_bulk[2] += gnd
    c_mcu_hf[1] += pwr_3v3
    c_mcu_hf[2] += gnd

    # -------------------------------------------------------------------------
    # 2. Reset Circuit (EN / CHIP_PU)
    # -------------------------------------------------------------------------
    # 10k Pull-up to 3.3V + 1uF timing capacitor to GND (Espressif recommended)
    r_en_pu = Part('Device', 'R', value='10k', footprint=FOOTPRINTS['R_0603'])
    c_en_delay = Part('Device', 'C', value='1uF', footprint=FOOTPRINTS['C_0603'])
    sw_reset = Part('Switch', 'SW_Push', footprint=FOOTPRINTS['SW_PUSH_SMD'], value='RESET_BTN')

    pwr_3v3 += r_en_pu[1]
    r_en_pu[2] += mcu['EN']
    mcu['EN'] += c_en_delay[1], sw_reset[1]
    c_en_delay[2] += gnd
    sw_reset[2] += gnd

    # -------------------------------------------------------------------------
    # 3. Boot / User Button Circuit (GPIO 9)
    # -------------------------------------------------------------------------
    # 10k Pull-up to 3.3V (Boot mode active-low on boot)
    r_boot_pu = Part('Device', 'R', value='10k', footprint=FOOTPRINTS['R_0603'])
    sw_boot = Part('Switch', 'SW_Push', footprint=FOOTPRINTS['SW_PUSH_SMD'], value='BOOT_BTN')

    pwr_3v3 += r_boot_pu[1]
    r_boot_pu[2] += mcu['IO9']
    mcu['IO9'] += sw_boot[1]
    sw_boot[2] += gnd

    # -------------------------------------------------------------------------
    # 4. Native USB Interface (GPIO 18 / 19)
    # -------------------------------------------------------------------------
    mcu['IO18'] += nets['USB_DN']
    mcu['IO19'] += nets['USB_DP']

    # -------------------------------------------------------------------------
    # 5. Shared I2S Audio Bus Lines
    # -------------------------------------------------------------------------
    mcu['IO2'] += nets['I2S_SCK']   # Bit Clock
    mcu['IO3'] += nets['I2S_WS']    # Word Select / Frame Clock
    mcu['IO4'] += nets['I2S_SD']    # Serial Data In

    # -------------------------------------------------------------------------
    # 6. I2C Sensor Bus Lines & Interrupt
    # -------------------------------------------------------------------------
    mcu['IO7'] += nets['I2C_SCL']   # Hardware I2C Clock
    mcu['IO6'] += nets['I2C_SDA']   # Hardware I2C Data
    mcu['IO1'] += nets['IMU_INT']   # Motion / Tap Wake-Up Interrupt

    # -------------------------------------------------------------------------
    # 7. SPI Storage Expansion Lines
    # -------------------------------------------------------------------------
    mcu['IO5'] += nets['SPI_CS']    # SPI Chip Select
    mcu['IO8'] += nets['SPI_CLK']   # SPI Clock
    mcu['IO20'] += nets['SPI_MISO'] # SPI MISO
    mcu['IO21'] += nets['SPI_MOSI'] # SPI MOSI

    # -------------------------------------------------------------------------
    # 8. User Interface & ADC Sensing
    # -------------------------------------------------------------------------
    mcu['IO10'] += nets['STATUS_LED'] # Recording Indicator LED
    mcu['IO0'] += nets['BATT_SENSE']  # LiPo Battery Voltage ADC

    return {
        "mcu": mcu,
        "sw_reset": sw_reset,
        "sw_boot": sw_boot,
    }
