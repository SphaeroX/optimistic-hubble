"""
IMU Motion Sensor Subsystem (LSM6DS3TR-C / BMI160) for Tap-to-Record Detection.

Features:
- 6-Axis Accelerometer & Gyroscope (LSM6DS3TR-C / LSM6DS3).
- Hardware I2C Interface with 4.7k pull-up resistors (SCL = GPIO 7, SDA = GPIO 6).
- SDO/SA0 tied to GND for standard I2C address 0x6A.
- CS tied to 3.3V to permanently configure standard I2C bus mode.
- INT1 hardware interrupt line routed directly to ESP32-C3 GPIO 1 for tap detection.
- Multi-tier decoupling capacitors (1uF bulk + 100nF VDD + 100nF VDDIO).
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_imu_sensor(nets):
    """
    Creates and wires the IMU Sensor module.
    
    Args:
        nets (dict): Dictionary of shared nets.
    """
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    i2c_scl = nets['I2C_SCL']
    i2c_sda = nets['I2C_SDA']
    imu_int = nets['IMU_INT']

    # -------------------------------------------------------------------------
    # 1. LSM6DS3TR-C 6-Axis Motion Sensor
    # -------------------------------------------------------------------------
    imu = Part(
        'Sensor_Motion', 'LSM6DS3',
        footprint=FOOTPRINTS['LSM6DS3_LGA14'],
        value='LSM6DS3TR-C'
    )

    # Power & Ground Connections
    imu['VDD'] += pwr_3v3
    imu['VDDIO'] += pwr_3v3
    imu['GND'] += gnd

    # Decoupling Network (1uF bulk + dual 100nF)
    c_imu_bulk = Part('Device', 'C', value='1uF', footprint=FOOTPRINTS['C_0603'])
    c_imu_vdd = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_imu_vddio = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])

    c_imu_bulk[1] += pwr_3v3
    c_imu_bulk[2] += gnd
    c_imu_vdd[1] += pwr_3v3
    c_imu_vdd[2] += gnd
    c_imu_vddio[1] += pwr_3v3
    c_imu_vddio[2] += gnd

    # -------------------------------------------------------------------------
    # 2. I2C Bus & Pull-Up Resistors
    # -------------------------------------------------------------------------
    r_scl_pu = Part('Device', 'R', value='4.7k', footprint=FOOTPRINTS['R_0603'])
    r_sda_pu = Part('Device', 'R', value='4.7k', footprint=FOOTPRINTS['R_0603'])

    pwr_3v3 += r_scl_pu[1], r_sda_pu[1]
    r_scl_pu[2] += i2c_scl
    r_sda_pu[2] += i2c_sda

    imu['SCL'] += i2c_scl
    imu['SDA'] += i2c_sda

    # Mode Selection & Address Setting
    imu['CS'] += pwr_3v3         # CS = HIGH -> Selects I2C mode
    imu['SDO/SA0'] += gnd       # SA0 = LOW -> I2C Address 0x6A

    # -------------------------------------------------------------------------
    # 3. Hardware Motion / Tap Interrupt
    # -------------------------------------------------------------------------
    imu['INT1'] += imu_int      # Connected to GPIO 1 for tap detection wake-up

    return {
        "imu": imu,
        "r_scl_pu": r_scl_pu,
        "r_sda_pu": r_sda_pu,
    }
