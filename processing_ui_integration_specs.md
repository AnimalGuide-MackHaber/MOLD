# Physarum Polycephalum Sonification Engine
## Comprehensive UI & Parameter Specifications Document
**Target Environment:** Processing 3/4 (Java)
**Recommended UI Library for Implementation:** `ControlP5`

This document outlines the exact parameters, ranges, default values, and functional mappings of the Web App's User Interface. The goal is to port these controls into the native Processing (`.pde`) environment.

---

## 1. Global Transport & Action Strip
These controls govern the master state of the simulation and sit outside the main collapsible menus.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Simulation Speed** | Slider | `float` | `0.40f` | **Range:** `0.05f` to `2.00f`. **Step:** `0.05f`. Acts as a multiplier for how many simulation steps are processed per `draw()` frame. Values < 1.0 utilize a fractional accumulator. |
| **Pause / Resume** | Toggle/Button | `boolean` | `false` | Toggles the execution of `stepSimulation()` inside the `draw()` loop. Rendering still occurs while paused. |
| **Clear Food** | Button | `Action` | N/A | Triggers a loop that calls `.destroy()` on all existing `FoodNodule` objects (stopping their audio voices) and clears the `foodSources` array. |
| **Scatter Oats** | Button | `Action` | N/A | Spawns 4 random `FoodNodule` objects at random coordinates within the grid. |
| **Audio ON/OFF** | Toggle | `boolean` | `false` | Toggles the master audio engine. In Processing, this should start/stop the `SourceDataLine` thread or mute the master PCM output buffer. |

---

## 2. Launchpad Mini [MK3] MIDI Integration
Controls for the hardware interface. In Processing, this hooks into the `javax.sound.midi` subsystem.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Enable Hardware Link** | Toggle | `boolean` | `false` | When `true`, sends the Programmer Mode SysEx `[F0, 00, 20, 29, 02, 0D, 0E, 01, F7]`. When `false`, sends Live Mode SysEx `[F0, 00, 20, 29, 02, 0D, 0E, 00, F7]`. |
| **MIDI Input Port** | Dropdown | `String`/`int` | `null` | Populates with available MIDI Transmitters. Binds the `Receiver` to listen for Note On events (Pads 11-88) to spawn food. |
| **MIDI Output Port** | Dropdown | `String`/`int` | `null` | Populates with available MIDI Receivers. Used to send Note On messages (Velocity 0-127) to update LED colors at ~22Hz. |

---

## 3. Harmonizer & Scale Matrix
Controls the musical logic mapping the 8x8 grid to frequencies.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Root Key** | Dropdown | `int` | `9` (A) | **Options:** 0 (C) to 11 (B). Sets the fundamental pitch class. Recalculates all active oscillator frequencies immediately upon change. |
| **Consonant Scale** | Dropdown | `String` / `int` | `major_pentatonic` | **Options:** `major_pentatonic`, `minor_pentatonic`, `lydian`, `dorian`, `hirajoshi`, `just_intonation`. Maps the 8 columns to specific scale degrees/ratios. |
| **Oscillator Waveform** | Radio Group | `String` / `int` | `triangle` | **Options:** `triangle`, `sine`, `sawtooth`, `square`. Updates the wave shape generation in the audio synthesis thread. |
| **Show 8x8 Freq Overlay** | Toggle | `boolean` | `false` | When true, renders the 8x8 grid lines, Hz values, and cell highlighting over the canvas. |

---

## 4. Dynamic LPF & Adjacent VCA
Controls the audio synthesis parameters driven by the slime mold's biological state.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Filter Cutoff Sensitivity** | Slider | `float` | `1.2f` | **Range:** `0.2f` to `3.0f`. **Step:** `0.1f`. Multiplies the depth of the low-pass filter sweep. Formula: `TargetHz = BaseHz + (MassRatio * MaxHz * Sensitivity)`. |
| **Filter Resonance (Q)** | Slider | `float` | `4.5f` | **Range:** `0.5f` to `18.0f`. **Step:** `0.5f`. Sets the resonance peak parameter of the Biquad filter algorithm. |
| **Adjacent Mass VCA Gain** | Slider | `float` | `1.0f` | **Range:** `0.2f` to `3.0f`. **Step:** `0.1f`. Sensitivity multiplier for the Moore neighborhood. Formula: `VCALevel = min(1.0, AdjacentBiomassSum * VCASensitivity)`. |

---

## 5. Bioenergetics & Tendril Reach
Controls the physical rules and metabolic costs of the slime mold agents.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Tendril Reach (Sensor Dist)**| Slider | `float` | `16.0f`| **Range:** `6.0f` to `45.0f`. **Step:** `1.0f`. Pixel distance at which agents sample the chemoattractant trail (Left, Forward, Right). |
| **Basal Metabolic Rate (BMR)**| Slider | `float` | `0.0008f`| **Range:** `0.0001f` to `0.0030f`. **Step:** `0.0001f`. The exact amount of energy deducted from every single agent per simulation step. |
| **Exploration Loco Cost** | Slider | `float` | `0.0015f`| **Range:** `0.0002f` to `0.0050f`. **Step:** `0.0001f`. Additional energy cost applied to agents dynamically. |

*(Note for AI implementation: The web app hides some static config parameters like `mitosisThreshold`, `decayFactor`, `diffuseRate`, and `turnAngle` from the UI to save space. They should remain as final floats/constants in the Processing sketch unless explicitly requested by the user).*

---

## 6. Color Palette & Visuals
Controls the rendering colors mapped to the continuum field.

| Control Label | UI Type | Variable Type | Default | Action / Functional Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **Visual Theme** | Radio Group | `String` / `int` | `yellow` | **Options:** `yellow` (Yellow Mold), `mono` (Grayscale), `cyan` (Bio Cyan). Swaps the 4-tier pixel color mapping (Void, Atrophying Edge, Solid Sheet, Canary Core) during the pixel buffer rendering loop. |

---

## Implementation Notes for AI Agents
*   **UI Layout:** In Processing, reserve a vertical strip on the right side of the canvas (e.g., `width = 760 + 300`, where the rightmost 300px are dedicated to the `ControlP5` interface).
*   **Performance Warning:** Processing UI elements should **not** trigger continuous recreation of audio objects. For example, changing the `Root Key` dropdown should simply trigger a loop iterating over `foodSources` to update their target frequency variables using `Math.pow()`, rather than tearing down the audio thread.