"""
Dual I2S MEMS Microphones Subsystem for Voice Assistant & Active Noise Filtering.

Features:
- Dual I2S MEMS Microphones (INMP441 / ICS-43434).
- Synchronous phase-aligned stereo capture on a shared 3-wire I2S bus.
- Mic 1 (Left Channel / Voice Mic): L/R tied to GND.
- Mic 2 (Right Channel / Ambient Noise Mic): L/R tied to +3V3_AUDIO.
- Clean dedicated +3V3_AUDIO power rail with Ferrite Bead / Pi-filter decoupling
  to eliminate Wi-Fi RF burst noise from the microphone pre-amplifiers.
"""

from skidl import *
from hardware.config import FOOTPRINTS

def create_audio_mems(nets):
    """
    Creates and wires the Dual MEMS Microphone Audio Subsystem.
    
    Args:
        nets (dict): Dictionary of shared nets.
    """
    pwr_3v3 = nets['+3V3']
    gnd = nets['GND']
    i2s_sck = nets['I2S_SCK']
    i2s_ws = nets['I2S_WS']
    i2s_sd = nets['I2S_SD']

    # -------------------------------------------------------------------------
    # 1. Clean Audio Power Rail Filter (Ferrite Bead + Bulk Cap)
    # -------------------------------------------------------------------------
    pwr_3v3_audio = Net('+3V3_AUDIO')
    nets['+3V3_AUDIO'] = pwr_3v3_audio

    # Ferrite Bead / Low-pass filter (e.g. 600 Ohm @ 100MHz, SMD 0805)
    fb_audio = Part('Device', 'FerriteBead', footprint=FOOTPRINTS['R_0805'], value='600R_100MHz')
    c_audio_bulk = Part('Device', 'C', value='10uF', footprint=FOOTPRINTS['C_0805'])
    c_audio_hf = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])

    pwr_3v3 += fb_audio[1]
    fb_audio[2] += pwr_3v3_audio
    
    c_audio_bulk[1] += pwr_3v3_audio
    c_audio_bulk[2] += gnd
    c_audio_hf[1] += pwr_3v3_audio
    c_audio_hf[2] += gnd

    # -------------------------------------------------------------------------
    # 2. Mic 1: Left Channel (Primary Voice / Speech Microphone)
    # -------------------------------------------------------------------------
    mic1 = Part(
        'Project_Symbols', 'INMP441',
        footprint=FOOTPRINTS['INMP441_MIC'],
        value='INMP441_LEFT'
    )
    
    c_mic1 = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_mic1[1] += pwr_3v3_audio
    c_mic1[2] += gnd

    mic1['VDD'] += pwr_3v3_audio
    mic1['GND'] += gnd
    mic1['SCK'] += i2s_sck
    mic1['WS'] += i2s_ws
    mic1['SD'] += i2s_sd
    mic1['L/R'] += gnd  # L/R = GND -> Left Channel Slot

    # -------------------------------------------------------------------------
    # 3. Mic 2: Right Channel (Ambient Noise Reference Microphone)
    # -------------------------------------------------------------------------
    mic2 = Part(
        'Project_Symbols', 'INMP441',
        footprint=FOOTPRINTS['INMP441_MIC'],
        value='INMP441_RIGHT'
    )
    
    c_mic2 = Part('Device', 'C', value='100nF', footprint=FOOTPRINTS['C_0603'])
    c_mic2[1] += pwr_3v3_audio
    c_mic2[2] += gnd

    mic2['VDD'] += pwr_3v3_audio
    mic2['GND'] += gnd
    mic2['SCK'] += i2s_sck
    mic2['WS'] += i2s_ws
    mic2['SD'] += i2s_sd
    mic2['L/R'] += pwr_3v3_audio  # L/R = 3V3 -> Right Channel Slot

    return {
        "fb_audio": fb_audio,
        "mic1": mic1,
        "mic2": mic2,
    }
