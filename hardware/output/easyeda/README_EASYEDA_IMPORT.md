# EasyEDA Online Editor Import Guide

This folder contains all files formatted for **EasyEDA Standard** and **EasyEDA Pro** (https://easyeda.com/editor).

---

## Method 1: 1-Click Import into EasyEDA (Recommended)

1. Open your browser and navigate to **[https://easyeda.com/editor](https://easyeda.com/editor)**.
2. In the top navigation menu, click **File $\rightarrow$ Import $\rightarrow$ KiCad...** (or on the Start Page click **"Import KiCad"**).
3. Select the prepared zip file:
   👉 **`xiao_voice_recorder_easyeda_import.zip`**
4. Click **Import**.
5. EasyEDA will automatically extract the schematic, all 40 components, footprints, and net connections!

---

## Method 2: EasyEDA Pro Project Import

1. In EasyEDA Pro, go to **File $\rightarrow$ Import $\rightarrow$ KiCad Project**.
2. Select either `xiao_voice_recorder_easyeda_import.zip` or the files from the `kicad/` directory (`.kicad_pro` + `.kicad_sch`).
3. Click **Import & Convert**.

---

## Included Files in this Directory

* **`xiao_voice_recorder_easyeda_import.zip`**: Complete compressed KiCad project archive for 1-click EasyEDA web import.
* **`xiao_voice_recorder_easyeda.json`**: Structured JSON schematic & netlist.
* **`xiao_voice_recorder.epro`**: EasyEDA Pro project descriptor.
* **`xiao_voice_recorder_jlcpcb_bom.csv`**: SMT-Ready Bill of Materials containing pre-assigned **LCSC Part Numbers (C-Numbers)** for direct 1-click JLCPCB PCB manufacturing and SMT assembly!
