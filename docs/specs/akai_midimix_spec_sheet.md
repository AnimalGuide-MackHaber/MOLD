# Akai MIDImix MIDI Specification Sheet
> **Target Audience:** AI Coding Agents / Developers
> **Protocol:** Standard MIDI Over USB
> **Global Default Channel:** MIDI Channel 1 (0x00 index-based)

---

## 1. System Overview & Behavior
* **Input / Output:** The Akai MIDImix functions as an input controller and an output receiver.
* **Control States:** Knobs and faders emit Continuous Controller (CC) messages. Buttons emit raw MIDI Note messages.
* **LED Feedback Policy:** The hardware features **no internal local LED toggling**. When a button is physically pressed, its light state remains unaltered unless the host software sends an explicit matching MIDI feedback message back to the unit.
* **LED Capabilities:** Single-color (amber/red) LEDs exist only behind the **Mute** (Row 1) and **Rec Arm** (Row 2) buttons. The *Solo* and *Send All* buttons do not possess physical LEDs.

---

## 2. LED Control Protocol (MIDI Output to Hardware)
To mutate the state of any supported button LED, send an identical **Note On** message back to the device on **MIDI Channel 1**:

* **LED ON:** `Note On` message, Velocity range `[1, 127]` (typically use `127` / `0x7F`)
* **LED OFF:** `Note On` message, Velocity `0` (`0x00`)
* *Developer Note:* Standard MIDI `Note Off` (`0x80` status byte) commands are ignored by the hardware for LED state modification. You must explicitly use `Note On` (`0x90`) with a `0` velocity.

---

## 3. Comprehensive Mapping Reference (Data Arrays)

### 3.1 Rotary Knobs (Continuous Controllers)
* **Message Type:** MIDI CC (`0xB0` on Channel 1)
* **Value Range:** `[0, 127]`

| Channel Strip (1-Indexed) | Top Row (CC #) | Middle Row (CC #) | Bottom Row (CC #) |
|:---|:---|:---|:---|
| Track 1 | 16 (`0x10`) | 20 (`0x14`) | 24 (`0x18`) |
| Track 2 | 17 (`0x11`) | 21 (`0x15`) | 25 (`0x19`) |
| Track 3 | 18 (`0x12`) | 22 (`0x16`) | 26 (`0x1A`) |
| Track 4 | 19 (`0x13`) | 23 (`0x17`) | 27 (`0x1B`) |
| Track 5 | 12 (`0x0C`) | 14 (`0x0E`) | 46 (`0x2E`) |
| Track 6 | 13 (`0x0D`) | 15 (`0x0F`) | 47 (`0x2F`) |
| Track 7 | 14 (`0x0E`) | 44 (`0x2C`) | 48 (`0x30`) |
| Track 8 | 15 (`0x0F`) | 45 (`0x2D`) | 49 (`0x31`) |

### 3.2 Faders (Continuous Controllers)
* **Message Type:** MIDI CC (`0xB0` on Channel 1)
* **Value Range:** `[0, 127]`

| Fader Component | Decimal CC | Hex CC |
|:---|:---|:---|
| Fader Track 1 | 19 | `0x13` |
| Fader Track 2 | 23 | `0x17` |
| Fader Track 3 | 27 | `0x1B` |
| Fader Track 4 | 28 | `0x1C` |
| Fader Track 5 | 29 | `0x1D` |
| Fader Track 6 | 30 | `0x1E` |
| Fader Track 7 | 31 | `0x1F` |
| Fader Track 8 | 33 | `0x21` |
| Master Fader | 11 | `0x0B` |

### 3.3 Buttons & Accompanying LEDs
* **Message Type (Input & Output):** Note On / Note Off (`0x90` / `0x80` status bytes for incoming data)
* **Value Range:** `[0, 127]` (Note velocities)

| Track Strip | Mute Button Note (Row 1) | Mute Note (Hex) | Rec Arm Button Note (Row 2) | Rec Arm Note (Hex) | Has LED? |
|:---|:---|:---|:---|:---|:---|
| Track 1 | 1 (C#-1) | `0x01` | 3 (D#-1) | `0x03` | Yes |
| Track 2 | 4 (E-1) | `0x04` | 6 (F#-1) | `0x06` | Yes |
| Track 3 | 7 (G-1) | `0x07` | 9 (A-1) | `0x09` | Yes |
| Track 4 | 10 (A#-1) | `0x0A` | 12 (B-1) | `0x0C` | Yes |
| Track 5 | 13 (C0) | `0x0D` | 15 (D#0) | `0x0F` | Yes |
| Track 6 | 16 (E0) | `0x10` | 18 (F#0) | `0x12` | Yes |
| Track 7 | 19 (G0) | `0x13` | 21 (A0) | `0x15` | Yes |
| Track 8 | 22 (A#0) | `0x16` | 24 (B0) | `0x18` | Yes |

*Correction Note on Track 8:* 
* Mute Track 8 default note value is **22 (`0x16`)**
* Rec Arm Track 8 default note value is **24 (`0x18`)**

Let's output the corrected precise lookup map below.

---

## 4. Normalized Data Layout for JSON/Dictionary Parsing

```json
{
  "device": "Akai MIDImix",
  "default_midi_channel_zero_indexed": 0,
  "controls": {
    "knobs": {
      "row_top":    [16, 17, 18, 19, 12, 13, 14, 15],
      "row_middle": [20, 21, 22, 23, 14, 15, 44, 45],
      "row_bottom": [24, 25, 26, 27, 46, 47, 48, 49]
    },
    "faders": {
      "channels": [19, 23, 27, 28, 29, 30, 31, 33],
      "master": 11
    },
    "buttons": {
      "mute_row_notes": [1, 4, 7, 10, 13, 16, 19, 22],
      "rec_arm_notes":  [3, 6, 9, 12, 15, 18, 21, 24],
      "utility": {
        "bank_left": 25,
        "bank_right": 26,
        "solo_mode": 27,
        "send_all_cc": 82
      }
    }
  },
  "led_protocol": {
    "status_byte_hex": "0x90",
    "velocity_on_max": 127,
    "velocity_off": 0,
    "addressable_arrays": ["mute_row_notes", "rec_arm_notes"]
  }
}
```
