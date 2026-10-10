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

### A. Factory MIDI Protocol Matrix
All messages transmit on **MIDI Channel 1** (`0xB0` CCs, `0x90` Notes):

- **Faders 1–8:** `CC 19, 23, 27, 31, 49, 53, 57, 61`
- **Master Fader:** `CC 62`
- **Rotary Knobs (8x3 grid):**
  - Row 1 (Top): `CC 16, 20, 24, 28, 46, 50, 54, 58`
  - Row 2 (Middle): `CC 17, 21, 25, 29, 47, 51, 55, 59`
  - Row 3 (Bottom): `CC 18, 22, 26, 30, 48, 52, 56, 60`
- **Button Matrix (8x3 grid):**
  - Row 1 (Mute): `Notes 1, 4, 7, 10, 13, 16, 19, 22` (Internal amber LEDs)
  - Row 2 (Solo): `Notes 2, 5, 8, 11, 14, 17, 20, 23`
  - Row 3 (Rec Arm): `Notes 3, 6, 9, 12, 15, 18, 21, 24` (Internal amber LEDs)

### B. Defensive Normalization & Collision Guarding
- Normalize incoming CC values `[0, 127]` to float range `[0.0, 1.0]`. Apply exponential moving average (EMA) smoothing if jitter is present.
- Ensure CC numbers assigned to the MIDImix do not conflict with Launchpad perimeter CCs (e.g., Launchpad perimeter uses CCs 89, 79, 69, 59, 49, 39, 29, 19).

### C. Hardware Link Receiver Bypass Pattern
When mapping a physical button (e.g. Note 19) to toggle the master MIDI connection flag (`midiEnabled`):
Never drop all incoming messages unconditionally when `midiEnabled == false`. Always inspect and whitelist the hardware link toggle message first so physical controllers can re-enable the link:
```java
if (!midiEnabled) {
  if (message instanceof ShortMessage) {
    ShortMessage sm = (ShortMessage) message;
    if (sm.getCommand() == ShortMessage.NOTE_ON && sm.getData1() == LINK_NOTE && sm.getData2() > 0) {
      handleLinkToggle(sm);
    }
  }
  return;
}
```

### D. Bidirectional UI-Hardware Telemetry for Discrete Controls
When mapping hardware knobs, stepped rotaries, or buttons to discrete parameters (such as waveforms, consonant scales, visual palettes, root keys, or octave shifts):
1. **Named Widget Handles**: Never instantiate discrete GUI widgets (`RadioGroup`, `Dropdown`, `Toggle`) anonymously inside section builders if physical hardware can mutate their values. Retain accessible global or instance handles.
2. **Programmatic Setters with Callback Suppression**: Ensure widget classes expose non-triggering update methods (e.g. `setIndex(idx, false)` or `set(state, false)`). This allows MIDI callbacks to update onscreen states cleanly without creating recursive action invocation loops.
3. **Synchronize on Hardware Events**: Always call `setWidgetIfPresent()` inside both continuous CC handlers (when stepped knobs change values) and button toggle handlers (`handleMidimixButton()`).

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
- [ ] Are all discrete parameters modulated by MIDI hardware linked to their corresponding onscreen UI widgets (`RadioGroup`, `Dropdown`, `Toggle`)?
- [ ] Do UI widget setters accept a `notify` flag to suppress recursive callback triggering during external hardware updates?
- [ ] Are MIDI receiver callbacks free of any direct OpenGL / FBO drawing calls?
- [ ] Has `./tests/run_tests.sh` passed `MoldMidiControllerTest` (including the 500-message fuzz test)?
