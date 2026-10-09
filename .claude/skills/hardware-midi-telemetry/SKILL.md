---
name: hardware-midi-telemetry
description: >-
  Use this skill when integrating hardware MIDI controllers (Novation Launchpad Mini MK3,
  Akai MIDImix), bi-directional LED telemetry, SysEx protocol messaging, or interactive physical grids.
---

# Hardware MIDI Controller Integration, Protocols & LED Telemetry

This skill details the hardware protocols, bi-directional telemetry, color science, and architecture needed to integrate physical MIDI controllers like the **Novation Launchpad Mini [MK3]** and **Akai MIDImix** into real-time applications.

---

## 1. Multi-Device MIDI Architecture

When supporting multiple physical controllers simultaneously:
1. **Decoupled Controller Handles**:
   Maintain separate `MidiDevice`, `Transmitter`, and `Receiver` pipelines for each physical unit. Never multiplex devices onto a single shared port index.
2. **Dedicated UI Routing**:
   Provide separate dropdown selectors for each device's input and output ports in the settings UI.
3. **Isolated LED Streams**:
   High-frequency LED refresh streams (such as 64-pad Launchpad grids) must be strictly isolated to their target device's receiver. Flooding an unrelated MIDI device with high-density note or CC data can stall its input buffer.

---

## 2. Novation Launchpad Mini [MK3] Protocol

### A. Grid vs Perimeter Addressing
The Launchpad Mini MK3 separates the 8x8 playable grid from the perimeter function buttons:

* **8x8 Grid Pads**:
  - **Programmer Mode**: Notes `11–88` (row tens digit `1..8`, column units digit `1..8`).
  - **Custom Mode 3 / Drum Rack Mode**: Notes `36–99` sequentially across columns and rows.
* **Perimeter Scene Launch Buttons (Right Column)**:
  - Transmit and receive `CONTROL_CHANGE` on **Channel 1** (`0xB0`).
  - Top-to-bottom CC mapping:
    - Row 7 (Top): **CC 89** (e.g., Reinoculate colony)
    - Row 6: **CC 79** (e.g., Clear food nodes)
    - Row 5: **CC 69**
    - Row 4: **CC 59**
    - Row 3: **CC 49**
    - Row 2: **CC 39** (e.g., Toggle Slime layer)
    - Row 1: **CC 29** (e.g., Toggle Food layer)
    - Row 0 (Bottom): **CC 19** (e.g., Toggle Eating layer)

### B. Bi-Directional CC Feedback
To illuminate perimeter button LEDs:
Send a Channel 1 `CONTROL_CHANGE` message with the CC number and the desired velocity/palette code (`0–127`):
```java
ShortMessage msg = new ShortMessage();
msg.setMessage(ShortMessage.CONTROL_CHANGE, 0, ccNumber, colorCode);
launchpadReceiver.send(msg, -1);
```

### C. Batch SysEx RGB Lighting (Command 03h)
For smooth multi-color gradients and radial ripple animations:
* Standard Novation MK3 SysEx header: `F0 00 20 29 02 0D 03`
* Packet format: `0x03` specifies 24-bit RGB lighting mode.
* Each entry: `0x00` (pad specifier), `pad_id`, `red (0..127)`, `green (0..127)`, `blue (0..127)`.
* Packet terminates with `F7`.

---

## 3. Trilateral Color Domain Telemetry Standard

### The Translucent Pad Diffusion Problem
Translucent silicone pads and light guide reflections easily blend similar warm hues (yellow, orange, amber, red). Mapping separate simulation layers to adjacent warm colors creates severe optical ambiguity for the performer.

### The Trilateral Standard
Strictly divide simulation domains into distinct, non-overlapping color spectra:

Semantic Layer | Color Spectrum | Palette Codes | Rationale
:--- | :--- | :--- | :---
**Colony / Organism** | Yellow / Golden / Warm Ochre | `12–15`, `62`, `84` | High visibility biological presence.
**Nutrient / Food Nodules** | Electric Cyan / Turquoise | `37`, `78` | Crisp optical contrast against colony yellow.
**Consumption Activity** | Vivid Magenta $\to$ Purple | `53`, `54`, `55`, `52` | Distinct non-linear degradation when feeding.

### Hardware Toggle Indicators
LED indicator buttons on physical toggles must match the exact spectrum of the layer they control:
* Mold layer toggle indicator $\to$ Yellow (`13`)
* Food layer toggle indicator $\to$ Cyan (`37`)
* Eating layer toggle indicator $\to$ Magenta (`53`)

---

## 4. Akai MIDImix Integration

1. **Mapping Layout**:
   - 24 rotary potentiometers (3 per channel across 8 channels).
   - 9 linear faders (8 channel faders + 1 master fader).
   - 24 momentary/latch buttons (Mute, Rec Arm, Bank Left/Right).
2. **Defensive Normalization**:
   Normalize incoming CC values `[0, 127]` to float range `[0.0, 1.0]`. Apply exponential moving average (EMA) smoothing if jitter is present.
3. **Collision Guarding**:
   Ensure CC numbers assigned to the MIDImix do not conflict with Launchpad perimeter CCs (e.g., Launchpad perimeter uses CCs 89, 79, 69, 59, 49, 39, 29, 19).

---

## 5. MIDI Fuzz & Error Resilience

When receiving MIDI:
* Asynchronous data streams may occasionally drop status bytes or deliver fragmented packets.
* Ensure MIDI parsers gracefully ignore running status mismatches and corrupted messages without throwing uncaught runtime exceptions.
* Always test the MIDI receiver against random fuzz inputs.

---

## 6. Verification Checklist

Before committing MIDI code:
- [ ] Are Launchpad grid notes and perimeter CCs mapped to correct channel and numbers?
- [ ] Are perimeter buttons driven via Channel 1 CC messages (`0xB0`)?
- [ ] Does LED telemetry follow the Trilateral Color Standard (Yellow / Cyan / Magenta)?
- [ ] Are MIDI receiver callbacks free of any direct OpenGL / FBO drawing calls?
- [ ] Has `./tests/run_tests.sh` passed `MoldMidiControllerTest` (including the 500-message fuzz test)?
