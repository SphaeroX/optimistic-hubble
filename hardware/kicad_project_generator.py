"""
Comprehensive KiCad 8 Project & Schematic Generator.

Generates a complete, native KiCad 8 project:
1. xiao_voice_recorder.kicad_pro (Project Configuration)
2. xiao_voice_recorder.kicad_sch (Fully Connected Schematic with wires, labels, and blocks)
3. xiao_voice_recorder.kicad_pcb (PCB Board file)
4. sym-lib-table & fp-lib-table (Library tables)
"""

import os
import sys
import uuid
import re
import json

from hardware.config import (
    KICAD_SYMBOLS_DIR,
    CUSTOM_SYMBOLS_DIR,
    OUTPUT_DIR,
    FOOTPRINTS,
)

def extract_lib_symbol(sym_filepath, symbol_name):
    """
    Extracts the full raw (symbol "...") definition from a .kicad_sym file
    to embed inside (lib_symbols ...) in .kicad_sch.
    """
    if not os.path.exists(sym_filepath):
        return None
    with open(sym_filepath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Find start of symbol
    start_str = f'(symbol "{symbol_name}"'
    sym_start = content.find(start_str)
    if sym_start == -1:
        return None

    # Balance parentheses to get complete block
    depth = 0
    sym_end = -1
    for i in range(sym_start, len(content)):
        if content[i] == '(':
            depth += 1
        elif content[i] == ')':
            depth -= 1
            if depth == 0:
                sym_end = i + 1
                break

    if sym_end != -1:
        return content[sym_start:sym_end]
    return None

def parse_symbol_pins(sym_text):
    """
    Parses pin numbers, names, and relative coordinates from a symbol text definition.
    """
    if not sym_text:
        return {}

    pin_matches = re.finditer(
        r'\(pin\s+(\w+)\s+\w+\s+\(at\s+([-0-9.]+)\s+([-0-9.]+)(?:\s+([-0-9.]+))?\)\s+\(length\s+([-0-9.]+)\).*?\(name\s+"([^"]*)".*?\(number\s+"([^"]*)"',
        sym_text,
        re.DOTALL
    )

    pins = {}
    for m in pin_matches:
        ptype, px, py, angle, length, pname, pnum = m.groups()
        angle = float(angle) if angle else 0.0
        pins[pnum] = {
            "type": ptype,
            "name": pname,
            "x": float(px),
            "y": float(py),
            "angle": angle,
            "length": float(length) if length else 2.54,
        }
    return pins

def generate_kicad_project(circuit, project_name="xiao_voice_recorder"):
    """
    Generates all KiCad 8 project files.
    """
    pro_path = os.path.join(OUTPUT_DIR, f"{project_name}.kicad_pro")
    sch_path = os.path.join(OUTPUT_DIR, f"{project_name}.kicad_sch")
    pcb_path = os.path.join(OUTPUT_DIR, f"{project_name}.kicad_pcb")
    sym_table_path = os.path.join(OUTPUT_DIR, "sym-lib-table")
    fp_table_path = os.path.join(OUTPUT_DIR, "fp-lib-table")

    # 1. Generate .kicad_pro
    pro_data = {
        "board": {
            "design_settings": {
                "defaults": {
                    "board_outline_line_width": 0.1,
                    "copper_line_width": 0.2,
                }
            }
        },
        "meta": {
            "filename": f"{project_name}.kicad_pro",
            "version": 1
        },
        "net_settings": {},
        "schematic": {
            "drawing": {
                "dashed_lines_dash_length_ratio": 12.0,
                "dashed_lines_gap_length_ratio": 3.0,
                "default_line_thickness": 6.0,
                "default_text_size": 50.0,
            }
        },
        "sheets": [
            [str(uuid.uuid4()), ""]
        ]
    }
    with open(pro_path, "w", encoding="utf-8") as f:
        json.dump(pro_data, f, indent=2)
    print(f"[KiCad Project File] -> {pro_path}")

    # 2. Generate sym-lib-table & fp-lib-table
    rel_custom_sym = os.path.relpath(
        os.path.join(CUSTOM_SYMBOLS_DIR, "Project_Symbols.kicad_sym"),
        OUTPUT_DIR
    ).replace("\\", "/")
    
    sym_table_content = f"""(sym_lib_table
  (version 7)
  (lib (name "Project_Symbols")(type "KiCad")(uri "${{KIPRJMOD}}/{rel_custom_sym}")(options "")(descr "Project Custom Symbols"))
)
"""
    with open(sym_table_path, "w", encoding="utf-8") as f:
        f.write(sym_table_content)

    fp_table_content = """(fp_lib_table
  (version 7)
)
"""
    with open(fp_table_path, "w", encoding="utf-8") as f:
        f.write(fp_table_content)

    # 3. Generate Complete .kicad_sch with Embedded Symbols, Wires, and Net Labels
    build_complete_schematic(circuit, sch_path)

    # 4. Generate Initial .kicad_pcb
    build_initial_pcb(project_name, pcb_path)

def build_initial_pcb(project_name, pcb_path):
    """Creates a clean initial KiCad 8 PCB layout file."""
    pcb_content = f"""(kicad_pcb
	(version 20240108)
	(generator "antigravity_pcb_bridge")
	(generator_version "8.0")
	(general
		(thickness 1.6)
		(legacy_teardrops no)
	)
	(paper "A4")
	(title_block
		(title "ESP32-C3 Dual-Mic Voice Assistant PCB")
		(date "2026-08-19")
		(rev "1.0")
		(company "Unified PCB Hardware")
		(comment 1 "All-in-One PCB: ESP32-C3, Dual I2S MEMS Mics, IMU, LiPo PMU")
	)
	(layers
		(0 "F.Cu" signal)
		(31 "B.Cu" signal)
		(32 "B.Adhes" user "B.Adhesive")
		(33 "F.Adhes" user "F.Adhesive")
		(34 "B.Paste" user)
		(35 "F.Paste" user)
		(36 "B.SilkS" user "B.Silkscreen")
		(37 "F.SilkS" user "F.Silkscreen")
		(38 "B.Mask" user)
		(39 "F.Mask" user)
		(40 "Dwgs.User" user "User.Drawings")
		(41 "Cmts.User" user "User.Comments")
		(42 "Eco1.User" user "User.Eco1")
		(43 "Eco2.User" user "User.Eco2")
		(44 "Edge.Cuts" user)
		(45 "Margin" user)
		(46 "B.CrtYd" user "B.Courtyard")
		(47 "F.CrtYd" user "F.Courtyard")
		(48 "B.Fab" user)
		(49 "F.Fab" user)
	)
	(setup
		(pad_to_mask_clearance 0)
		(allow_soldermask_bridges_in_footprints no)
		(pcbplotparams
			(layerselection 0x00010fc_ffffffff)
			(plot_on_all_layers_selection 0x0000000_00000000)
			(disableapertmacros no)
			(usegerberextensions no)
			(usegerberattributes yes)
			(usegerberadvancedattributes yes)
			(creategerberjobfile yes)
			(dashed_line_dash_ratio 12.000000)
			(dashed_line_gap_ratio 3.000000)
			(svgprecision 4)
			(plotframeref no)
			(viasonmask no)
			(mode 1)
			(useauxorigin no)
			(hpglpennumber 1)
			(hpglpenspeed 20)
			(hpglpendiameter 15.000000)
			(pdf_front_fp_property_popups yes)
			(pdf_back_fp_property_popups yes)
			(dxfpolygonmode yes)
			(dxfimperialunits yes)
			(dxfusepcbnewfont yes)
			(psnegative no)
			(psa4output no)
			(psmaxphotosize no)
			(psusea4output no)
			(scale 1.000000)
			(autoscale no)
			(outputformat 1)
			(mirror no)
			(drillshape 1)
			(scaleselection 1)
			(outputdirectory "")
		)
	)
	(net 0 "")
)
"""
    with open(pcb_path, "w", encoding="utf-8") as f:
        f.write(pcb_content)
    print(f"[KiCad PCB Board File] -> {pcb_path}")

def build_complete_schematic(circuit, sch_path):
    """
    Builds a fully wired, annotated, and sectioned KiCad 8 schematic.
    """
    sch_lines = [
        '(kicad_sch',
        '  (version 20231120)',
        '  (generator "antigravity_kicad8_bridge")',
        '  (generator_version "8.0")',
        f'  (uuid "{uuid.uuid4()}")',
        '  (paper "A3")',
        '  (title_block',
        '    (title "ESP32-C3 Dual-Mic Voice Assistant & DSP Filter")',
        '    (date "2026-08-19")',
        '    (rev "v1.0")',
        '    (company "Unified Custom PCB")',
        '    (comment 1 "Full Single-Board Solution: ESP32-C3, Dual I2S MEMS Mics, IMU, LiPo PMU")',
        '  )',
        '  (lib_symbols'
    ]

    # Map of part library search
    # Collect all unique (lib_name, sym_name) used by parts
    sym_cache = {}
    sym_pin_cache = {}

    for part in circuit.parts:
        lib_name = getattr(part, 'lib', None) or getattr(part, 'library', 'Device')
        sym_name = getattr(part, 'name', part.ref)

        # Check in Project_Symbols or standard KiCad library
        key = f"{lib_name}:{sym_name}"
        if key not in sym_cache:
            sym_text = None
            if str(lib_name) == "Project_Symbols" or "Project_Symbols" in str(getattr(part, 'origin_lib', '')):
                custom_sym_file = os.path.join(CUSTOM_SYMBOLS_DIR, "Project_Symbols.kicad_sym")
                sym_text = extract_lib_symbol(custom_sym_file, sym_name)
            
            if not sym_text:
                # Try in standard KiCad symbols
                cand_file = os.path.join(KICAD_SYMBOLS_DIR, f"{lib_name}.kicad_sym")
                if os.path.exists(cand_file):
                    sym_text = extract_lib_symbol(cand_file, sym_name)
            
            if not sym_text:
                # Search across all symbols in standard dir
                for fn in os.listdir(KICAD_SYMBOLS_DIR):
                    if fn.endswith(".kicad_sym"):
                        sym_text = extract_lib_symbol(os.path.join(KICAD_SYMBOLS_DIR, fn), sym_name)
                        if sym_text:
                            break

            if sym_text:
                # Prepend lib_name to symbol identifier if needed
                sym_cache[key] = sym_text
                sym_pin_cache[key] = parse_symbol_pins(sym_text)
                sch_lines.append(sym_text)

    sch_lines.append('  )') # Close lib_symbols

    # Functional Layout Blocks on A3 Page (420 x 297 mm)
    # Define bounding boxes and section header banners
    blocks = [
        {"title": "1. POWER MANAGEMENT & BATTERY CHARGER (USB-C, TP4056, POWER-PATH, 3.3V LDO)", "x": 20, "y": 20, "w": 180, "h": 125},
        {"title": "2. ESP32-C3 CORE MICROCONTROLLER (WROOM-02, RESET, BOOT, USB D+/D-)", "x": 215, "y": 20, "w": 185, "h": 125},
        {"title": "3. DUAL I2S MEMS MICROPHONES (STEREO NOISE CANCELLATION)", "x": 20, "y": 155, "w": 120, "h": 120},
        {"title": "4. 6-AXIS IMU (LSM6DS3 TAP DETECTOR)", "x": 150, "y": 155, "w": 85, "h": 120},
        {"title": "5. 16MB SPI FLASH STORAGE (W25Q128)", "x": 245, "y": 155, "w": 80, "h": 120},
        {"title": "6. STATUS INDICATORS & TEST PADS", "x": 335, "y": 155, "w": 65, "h": 120},
    ]

    for b in blocks:
        # Bounding box
        bx, by, bw, bh = b["x"], b["y"], b["w"], b["h"]
        sch_lines.append(f'  (polyline (pts (xy {bx} {by}) (xy {bx+bw} {by}) (xy {bx+bw} {by+bh}) (xy {bx} {by+bh}) (xy {bx} {by})) (stroke (width 0.3) (type dash)) (uuid "{uuid.uuid4()}"))')
        # Title text
        sch_lines.append(f'  (text "{b["title"]}" (at {bx+3} {by+5} 0) (effects (font (size 2.0 2.0) (bold yes)) (justify left)) (uuid "{uuid.uuid4()}"))')

    # Classify components into their designated visual block positions
    wires_and_labels = []
    
    # Track placed coordinates for each part
    placed_positions = assign_component_positions(circuit.parts)

    for part, (px, py) in placed_positions.items():
        ref = str(part.ref)
        val = str(part.value)
        fp = str(part.footprint) if part.footprint else ""
        desc = getattr(part, 'description', '')
        lib_name = getattr(part, 'lib', None) or getattr(part, 'library', 'Device')
        sym_name = getattr(part, 'name', part.ref)
        key = f"{lib_name}:{sym_name}"

        sym_uuid = str(uuid.uuid4())
        sch_lines.append(f'  (symbol')
        sch_lines.append(f'    (lib_id "{lib_name}:{sym_name}")')
        sch_lines.append(f'    (at {px:.2f} {py:.2f} 0)')
        sch_lines.append(f'    (unit 1)')
        sch_lines.append(f'    (exclude_from_sim no)')
        sch_lines.append(f'    (in_bom yes)')
        sch_lines.append(f'    (on_board yes)')
        sch_lines.append(f'    (dnp no)')
        sch_lines.append(f'    (uuid "{sym_uuid}")')
        sch_lines.append(f'    (property "Reference" "{ref}" (at {px:.2f} {py-4.0:.2f} 0) (effects (font (size 1.27 1.27))))')
        sch_lines.append(f'    (property "Value" "{val}" (at {px:.2f} {py+4.0:.2f} 0) (effects (font (size 1.27 1.27))))')
        sch_lines.append(f'    (property "Footprint" "{fp}" (at {px:.2f} {py:.2f} 0) (effects (font (size 1.27 1.27)) (hide yes)))')
        sch_lines.append(f'    (property "Description" "{desc}" (at {px:.2f} {py:.2f} 0) (effects (font (size 1.27 1.27)) (hide yes)))')

        pins_info = sym_pin_cache.get(key, {})

        for pin in part.pins:
            pnum = str(pin.num)
            p_uuid = str(uuid.uuid4())
            sch_lines.append(f'    (pin "{pnum}" (uuid "{p_uuid}"))')

            # Calculate actual pin connection point in schematic coordinates
            # Note: in KiCad schematic coordinate system, +Y is downwards!
            p_info = pins_info.get(pnum)
            if p_info:
                # Pin relative offset
                pin_dx = p_info["x"]
                pin_dy = -p_info["y"] # Inverted Y in symbol definitions
                pin_ang = p_info["angle"]
                pin_len = p_info["length"]
            else:
                # Fallback for standard 2-pin passives (vertical)
                pin_dx = 0.0
                pin_dy = -3.81 if pnum == '1' else 3.81
                pin_ang = 270 if pnum == '1' else 90
                pin_len = 2.54

            # Attachment point on the symbol
            conn_x = px + pin_dx
            conn_y = py + pin_dy

            # Stub direction based on pin angle
            stub_len = 5.08
            if pin_ang == 0:     # Pin pointing Left, wire extends Left
                stub_x = conn_x - stub_len
                stub_y = conn_y
                lbl_rot = 180
                lbl_just = "right"
            elif pin_ang == 180: # Pin pointing Right, wire extends Right
                stub_x = conn_x + stub_len
                stub_y = conn_y
                lbl_rot = 0
                lbl_just = "left"
            elif pin_ang == 90:  # Pin pointing Down, wire extends Down
                stub_x = conn_x
                stub_y = conn_y + stub_len
                lbl_rot = 270
                lbl_just = "right"
            elif pin_ang == 270: # Pin pointing Up, wire extends Up
                stub_x = conn_x
                stub_y = conn_y - stub_len
                lbl_rot = 90
                lbl_just = "left"
            else:
                stub_x = conn_x + stub_len
                stub_y = conn_y
                lbl_rot = 0
                lbl_just = "left"

            # Check net connection
            net = pin.net
            if net and net.name and not net.name.startswith("N$") and not net.name.startswith("NC"):
                net_name = net.name
                wire_uuid = str(uuid.uuid4())
                lbl_uuid = str(uuid.uuid4())

                # Add Wire Stub
                wires_and_labels.append(
                    f'  (wire (pts (xy {conn_x:.2f} {conn_y:.2f}) (xy {stub_x:.2f} {stub_y:.2f})) (stroke (width 0) (type default)) (uuid "{wire_uuid}"))'
                )

                # Add Net Label at stub endpoint
                wires_and_labels.append(
                    f'  (label "{net_name}" (at {stub_x:.2f} {stub_y:.2f} {lbl_rot}) (fields_autoplaced yes) (effects (font (size 1.27 1.27)) (justify {lbl_just})) (uuid "{lbl_uuid}"))'
                )

        sch_lines.append('  )') # Close symbol instance

    # Append all wires and net labels
    sch_lines.extend(wires_and_labels)
    sch_lines.append(')') # Close kicad_sch

    with open(sch_path, "w", encoding="utf-8") as f:
        f.write("\n".join(sch_lines) + "\n")
    print(f"[KiCad Schematic File] -> {sch_path}")

def assign_component_positions(parts):
    """
    Assigns logical X, Y schematic coordinates for all components
    inside their respective functional subsystem boxes.
    """
    positions = {}
    
    # Subsystem buckets
    pmu_parts = []
    mcu_parts = []
    audio_parts = []
    imu_parts = []
    storage_parts = []
    ui_parts = []

    for p in parts:
        ref = str(p.ref)
        val = str(p.value)
        
        if "ESP32" in val or "WROOM" in val or ref in ["U4", "SW2", "SW3"] or "RESET" in val or "BOOT" in val or ref in ["R10", "R11", "C10", "C11", "C12"]:
            mcu_parts.append(p)
        elif "INMP" in val or "MIC" in val or "FB" in ref or "Ferrite" in val or ref in ["MK1", "MK2", "FB1", "C6", "C7", "C8", "C9"]:
            audio_parts.append(p)
        elif "LSM" in val or "IMU" in val or ref in ["U5", "R12", "R13", "C13", "C14", "C15"]:
            imu_parts.append(p)
        elif "W25Q" in val or "Flash" in val or ref in ["U6", "R14", "R15", "R16", "C16"]:
            storage_parts.append(p)
        elif "LED" in val or "TestPoint" in str(getattr(p, 'name', '')) or ref.startswith("TP") or ref in ["D4", "D5", "R17", "R18"]:
            ui_parts.append(p)
        else:
            pmu_parts.append(p)

    # Layout PMU Block (X: 30 - 190, Y: 35 - 135)
    layout_grid(pmu_parts, positions, start_x=35, start_y=40, cols=4, dx=42, dy=28)

    # Layout MCU Block (X: 230 - 390, Y: 35 - 135)
    layout_grid(mcu_parts, positions, start_x=230, start_y=45, cols=3, dx=55, dy=32)

    # Layout Audio Block (X: 30 - 130, Y: 170 - 265)
    layout_grid(audio_parts, positions, start_x=35, start_y=175, cols=3, dx=36, dy=28)

    # Layout IMU Block (X: 160 - 225, Y: 170 - 265)
    layout_grid(imu_parts, positions, start_x=160, start_y=175, cols=2, dx=36, dy=28)

    # Layout Storage Block (X: 255 - 315, Y: 170 - 265)
    layout_grid(storage_parts, positions, start_x=255, start_y=175, cols=2, dx=36, dy=28)

    # Layout UI Block (X: 345 - 395, Y: 170 - 265)
    layout_grid(ui_parts, positions, start_x=345, start_y=175, cols=2, dx=26, dy=22)

    return positions

def layout_grid(part_list, pos_dict, start_x, start_y, cols, dx, dy):
    for i, p in enumerate(part_list):
        c = i % cols
        r = i // cols
        pos_dict[p] = (start_x + (c * dx), start_y + (r * dy))
