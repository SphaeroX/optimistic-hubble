"""
External High-Capacity SPI NOR Flash Storage Subsystem (Winbond W25Q128JV).

Features:
- 16 Megabyte (128 Megabit) Ultra-High-Speed SPI NOR Flash.
- Dedicated hardware SPI bus connection to ESP32-C3:
  - CS: GPIO 5 (with 10k pull-up)
  - CLK: GPIO 8
  - MISO (DO): GPIO 20
  - MOSI (DI): GPIO 21
- Active-Low Write Protect (~WP) and Hold (~HOLD) lines secured with 10k pull-ups.
- Extends continuous audio recording from 4 minutes up to 35 minutes!
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_spi_storage(nets):
    """
    Creates and wires the External SPI Flash Storage module.
    
    Args:
        nets (dict): Dictionary of shared nets.
    """
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    spi_cs = nets['SPI_CS']
    spi_clk = nets['SPI_CLK']
    spi_miso = nets['SPI_MISO']
    spi_mosi = nets['SPI_MOSI']

    # -------------------------------------------------------------------------
    # 1. Winbond W25Q128JVSSIQ (16 MB SPI Flash)
    # -------------------------------------------------------------------------
    flash = Part(
        'Memory_Flash', 'W25Q128JVS',
        footprint=FOOTPRINTS['W25Q128_SOIC8'],
        value='W25Q128JV_16MB'
    )

    # Power & Ground
    flash['VCC'] += pwr_3v3
    flash['GND'] += gnd

    # Decoupling Capacitor
    c_flash = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_flash[1] += pwr_3v3
    c_flash[2] += gnd

    # SPI Bus Connections
    flash['CLK'] += spi_clk
    flash['DO(IO1)'] += spi_miso
    flash['DI(IO0)'] += spi_mosi

    # Chip Select with 10k Pull-Up to prevent unselected bus noise
    r_cs_pu = Part('Device', 'R', value='10k', footprint=FOOTPRINTS['R_0603'])
    pwr_3v3 += r_cs_pu[1]
    r_cs_pu[2] += spi_cs
    flash['~{CS}'] += spi_cs

    # Write Protect (~WP / IO2) and Hold (~HOLD / IO3) Pull-Ups
    r_wp_pu = Part('Device', 'R', value='10k', footprint=FOOTPRINTS['R_0603'])
    r_hold_pu = Part('Device', 'R', value='10k', footprint=FOOTPRINTS['R_0603'])
    
    pwr_3v3 += r_wp_pu[1], r_hold_pu[1]
    r_wp_pu[2] += flash['IO2']
    r_hold_pu[2] += flash['IO3']

    return {
        "flash": flash,
        "r_cs_pu": r_cs_pu,
    }
