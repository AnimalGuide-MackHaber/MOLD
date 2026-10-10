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

| Channel Strip (1-Indexed) | Top Row (Row 1) | Middle Row (Row 2) | Bottom Row (Row 3) |
|:---|:---|:---|:---|
| Track 1 | 16 (`0x10`) | 17 (`0x11`) | 18 (`0x12`) |
| Track 2 | 20 (`0x14`) | 21 (`0x15`) | 22 (`0x16`) |
| Track 3 | 24 (`0x18`) | 25 (`0x19`) | 26 (`0x1A`) |
| Track 4 | 28 (`0x1C`) | 29 (`0x1D`) | 30 (`0x1E`) |
| Track 5 | 46 (`0x2E`) | 47 (`0x2F`) | 48 (`0x30`) |
| Track 6 | 50 (`0x32`) | 51 (`0x33`) | 52 (`0x34`) |
| Track 7 | 54 (`0x36`) | 55 (`0x37`) | 56 (`0x38`) |
| Track 8 | 58 (`0x3A`) | 59 (`0x3B`) | 60 (`0x3C`) |

### 3.2 Faders (Continuous Controllers)
* **Message Type:** MIDI CC (`0xB0` on Channel 1)
* **Value Range:** `[0, 127]`

| Fader Component | Decimal CC | Hex CC |
|:---|:---|:---|
| Fader Track 1 | 19 | `0x13` |
| Fader Track 2 | 23 | `0x17` |
| Fader Track 3 | 27 | `0x1B` |
| Fader Track 4 | 31 | `0x1F` |
| Fader Track 5 | 49 | `0x31` |
| Fader Track 6 | 53 | `0x35` |
| Fader Track 7 | 57 | `0x39` |
| Fader Track 8 | 61 | `0x3D` |
| Master Fader  | 62 | `0x3E` |

### 3.3 Buttons & Accompanying LEDs
* **Message Type (Input & Output):** Note On / Note Off (`0x90` / `0x80` status bytes for incoming data)
* **Value Range:** `[0, 127]` (Note velocities)

| Track Strip | Mute (Row 1) | Solo (Row 2) | Rec Arm (Row 3) | Has LED? |
|:---|:---|:---|:---|:---|
| Track 1 | Note 1 (`0x01`) | Note 2 (`0x02`) | Note 3 (`0x03`) | Mute / Rec Arm |
| Track 2 | Note 4 (`0x04`) | Note 5 (`0x05`) | Note 6 (`0x06`) | Mute / Rec Arm |
| Track 3 | Note 7 (`0x07`) | Note 8 (`0x08`) | Note 9 (`0x09`) | Mute / Rec Arm |
| Track 4 | Note 10 (`0x0A`) | Note 11 (`0x0B`) | Note 12 (`0x0C`) | Mute / Rec Arm |
| Track 5 | Note 13 (`0x0D`) | Note 14 (`0x0E`) | Note 15 (`0x0F`) | Mute / Rec Arm |
| Track 6 | Note 16 (`0x10`) | Note 17 (`0x11`) | Note 18 (`0x12`) | Mute / Rec Arm |
| Track 7 | Note 19 (`0x13`) | Note 20 (`0x14`) | Note 21 (`0x15`) | Mute / Rec Arm |
| Track 8 | Note 22 (`0x16`) | Note 23 (`0x17`) | Note 24 (`0x18`) | Mute / Rec Arm |

---

## 4. Normalized Data Layout for JSON/Dictionary Parsing

```json
{
  "device": "Akai MIDImix",
  "default_midi_channel_zero_indexed": 0,
  "controls": {
    "knobs": {
      "row_top":    [16, 20, 24, 28, 46, 50, 54, 58],
      "row_middle": [17, 21, 25, 29, 47, 51, 55, 59],
      "row_bottom": [18, 22, 26, 30, 48, 52, 56, 60]
    },
    "faders": {
      "channels": [19, 23, 27, 31, 49, 53, 57, 61],
      "master": 62
    },
    "buttons": {
      "mute_row_notes":    [1, 4, 7, 10, 13, 16, 19, 22],
      "solo_row_notes":    [2, 5, 8, 11, 14, 17, 20, 23],
      "rec_arm_row_notes": [3, 6, 9, 12, 15, 18, 21, 24]
    }
  },
  "led_protocol": {
    "status_byte_hex": "0x90",
    "velocity_on_max": 127,
    "velocity_off": 0,
    "addressable_arrays": ["mute_row_notes", "rec_arm_row_notes"]
  }
}
```
