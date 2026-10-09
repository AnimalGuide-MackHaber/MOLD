// =============================================================================
// Midi.pde - Hardware MIDI Controller Integration (Launchpad Mini & Akai MIDImix)
// =============================================================================

// Smooth LED state and transition tracking
int[] padDirtyChannels = new int[64];
float[] smoothBiomass = new float[64];
float[] smoothFoodRatio = new float[64];
boolean lpTopSidePressed = false;
boolean lpSecSidePressed = false;

// Launchpad Mode: lpUserMode = true (factory User Mode / Custom Mode 3 Drum Rack 36..99); false = Programmer Mode (11..88)
boolean lpUseRgbSysex = false;
boolean lpUserMode = true;

// User Mode (Drum Rack 4-Quadrant) note calculation for pad (col, row)
int getLaunchpadUserNote(int col, int row) {
  int quadX = col / 4;          // 0 = left, 1 = right
  int quadY = row / 4;          // 0 = top, 1 = bottom
  int subX  = col % 4;          // 0..3
  int subY  = 3 - (row % 4);    // 0..3 (inverted: 0 is bottom row of quadrant)
  
  int baseNote;
  if (quadX == 0 && quadY == 1) baseNote = 36;      // Quadrant 1 (Bottom-Left)
  else if (quadX == 0 && quadY == 0) baseNote = 52; // Quadrant 3 (Top-Left)
  else if (quadX == 1 && quadY == 1) baseNote = 68; // Quadrant 2 (Bottom-Right)
  else baseNote = 84;                               // Quadrant 4 (Top-Right)
  
  return baseNote + (subY * 4) + subX;
}

// User Mode (Drum Rack 4-Quadrant) decoding: note (36..99) -> [col, row]
int[] decodeLaunchpadUserNote(int note) {
  int index = note - 36;
  int quad = index / 16;
  int sub = index % 16;
  int subRow = sub / 4;
  int subCol = sub % 4;

  int col = (quad >= 2 ? 4 : 0) + subCol;
  int row = (quad % 2 == 0 ? 7 : 3) - subRow;
  return new int[]{col, row};
}

// Continuous 7-bit RGB pad states for silky smooth temporal transitions
float[] currentPadR = new float[64];
float[] currentPadG = new float[64];
float[] currentPadB = new float[64];
byte[] lastSentPadR = new byte[64];
byte[] lastSentPadG = new byte[64];
byte[] lastSentPadB = new byte[64];

// Ripple effect on food drop
class PadRipple {
  int originCol;
  int originRow;
  float worldX;
  float worldY;
  long birthTime;
  float durationMs = 900.0f; // fluid ~0.9s ripple
  float maxRadius = 11.5f;   // covers full 8x8 grid diagonally (sqrt(7^2+7^2)=9.9) with smooth exit

  PadRipple(int c, int r, float wx, float wy) {
    originCol = c;
    originRow = r;
    worldX = wx;
    worldY = wy;
    birthTime = millis();
  }

  float progress(long now) {
    return (now - birthTime) / durationMs;
  }
}

java.util.concurrent.CopyOnWriteArrayList<PadRipple> padRipples = new java.util.concurrent.CopyOnWriteArrayList<PadRipple>();

void triggerPadRipple(int col, int row, float wx, float wy) {
  padRipples.add(new PadRipple(col, row, wx, wy));
}

// Continuous RGB colormap evaluation matching the active shader palette
void evaluateBiomassGradient(float mass, float threshold, int palIdx, float[] outRgb) {
  float u = constrain((mass - threshold) / (threshold * 7.0f), 0.0f, 1.0f);
  // Perceptual response curve
  float up = pow(u, 0.75f);

  if (up <= 0.001f) {
    outRgb[0] = 0; outRgb[1] = 0; outRgb[2] = 0;
    return;
  }

  if (palIdx == 1) { // Mono
    // 0.0: (12, 12, 14) -> 0.25: (22, 22, 26) -> 0.5: (47, 47, 52) -> 0.75: (87, 87, 92) -> 1.0: (122, 122, 125)
    float r = lerp(12.0f, 122.0f, up);
    outRgb[0] = r; outRgb[1] = r; outRgb[2] = r;
  } else if (palIdx == 2) { // Cyan
    // 0.0: (2, 26, 37) -> 0.5: (17, 105, 119) -> 1.0: (103, 125, 127)
    if (up < 0.5f) {
      float f = up * 2.0f;
      outRgb[0] = lerp(2.0f, 17.0f, f);
      outRgb[1] = lerp(26.0f, 105.0f, f);
      outRgb[2] = lerp(37.0f, 119.0f, f);
    } else {
      float f = (up - 0.5f) * 2.0f;
      outRgb[0] = lerp(17.0f, 103.0f, f);
      outRgb[1] = lerp(105.0f, 125.0f, f);
      outRgb[2] = lerp(119.0f, 127.0f, f);
    }
  } else { // Yellow (Zorn)
    // 0.0: (12, 6, 1) -> 0.25: (58, 32, 4) -> 0.5: (80, 49, 3) -> 0.75: (117, 90, 4) -> 1.0: (127, 120, 69)
    if (up < 0.33f) {
      float f = up / 0.33f;
      outRgb[0] = lerp(12.0f, 65.0f, f);
      outRgb[1] = lerp(6.0f, 38.0f, f);
      outRgb[2] = lerp(1.0f, 4.0f, f);
    } else if (up < 0.66f) {
      float f = (up - 0.33f) / 0.33f;
      outRgb[0] = lerp(65.0f, 117.0f, f);
      outRgb[1] = lerp(38.0f, 90.0f, f);
      outRgb[2] = lerp(4.0f, 6.0f, f);
    } else {
      float f = (up - 0.66f) / 0.34f;
      outRgb[0] = lerp(117.0f, 127.0f, f);
      outRgb[1] = lerp(90.0f, 120.0f, f);
      outRgb[2] = lerp(6.0f, 69.0f, f);
    }
  }
}

// Find active food nodule at grid cell (col, row)
FoodNodule findFoodNoduleAt(int col, int row) {
  for (FoodNodule fn : foodNodes) {
    if (fn.gridCol == col && fn.gridRow == row) return fn;
  }
  return null;
}

// Prune expired ripples and compute radial ripple wave crests across 64 pads
void updateRipples(long now, float[] rippleIntensities) {
  java.util.ArrayList<PadRipple> expiredRipples = new java.util.ArrayList<PadRipple>();
  for (PadRipple pr : padRipples) {
    if (pr.progress(now) >= 1.0f) {
      expiredRipples.add(pr);
    }
  }
  padRipples.removeAll(expiredRipples);

  for (PadRipple pr : padRipples) {
    float tau = pr.progress(now);
    if (tau < 0.0f || tau >= 1.0f) continue;
    float rWave = pr.maxRadius * tau;
    float amp = max(0.0f, 1.0f - tau * 0.65f);
    float sigma = max(0.35f, lpRippleWidth * 0.38f);
    float twoSigmaSq = 2.0f * sigma * sigma;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        int idx = r * 8 + c;
        float d = dist(c, r, pr.originCol, pr.originRow);
        float delta = abs(d - rWave);
        float crest = amp * exp(-(delta * delta) / twoSigmaSq);
        
        // Initial core drop flash on origin pad
        if (c == pr.originCol && r == pr.originRow && tau < 0.25f) {
          float flash = pow(1.0f - (tau / 0.25f), 1.5f);
          crest = max(crest, flash);
        }
        rippleIntensities[idx] = min(1.0f, rippleIntensities[idx] + crest);
      }
    }
  }
}

// Stream continuous 7-bit RGB gradients to Launchpad via SysEx Command 03h Type 3
void sendLaunchpadRgbSysex(long now, float[] rippleIntensities) {
  float[] targetR = new float[64];
  float[] targetG = new float[64];
  float[] targetB = new float[64];
  float[] moldRgb = new float[3];

  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      int idx = r * 8 + c;
      FoodNodule cellFood = findFoodNoduleAt(c, r);
      boolean hasFood = (cellFood != null && cellFood.nutrients > 0);
      boolean isEating = hasFood && (cellFood.consumptionActivity > 0.05f);

      if (lpShowSlime) {
        smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18f;
        float mass = smoothBiomass[idx];
        float t = max(10.0f, ledMassThreshold);
        evaluateBiomassGradient(mass, t, paletteIdx, moldRgb);
        targetR[idx] = moldRgb[0];
        targetG[idx] = moldRgb[1];
        targetB[idx] = moldRgb[2];
      } else {
        targetR[idx] = 0; targetG[idx] = 0; targetB[idx] = 0;
      }

      if (hasFood && lpShowFood && !isEating) {
        float breath = 0.85f + 0.15f * sin(now * 0.005f + (r + c) * 0.5f);
        targetR[idx] = max(targetR[idx], 0.0f);
        targetG[idx] = max(targetG[idx], 110.0f * breath);
        targetB[idx] = max(targetB[idx], 127.0f * breath);
      }

      if (isEating && lpShowEating) {
        float targetRatio = cellFood.nutrients / cellFood.initialCapacity;
        smoothFoodRatio[idx] += (targetRatio - smoothFoodRatio[idx]) * 0.25f;
        float fr = smoothFoodRatio[idx];
        float feedPulse = 0.85f + 0.15f * sin(now * 0.012f);
        float eatR = lerp(60.0f, 127.0f, fr) * feedPulse;
        float eatG = 0.0f;
        float eatB = lerp(110.0f, 75.0f, fr) * feedPulse;
        float act = constrain(cellFood.consumptionActivity, 0.0f, 1.0f);
        targetR[idx] = lerp(targetR[idx], eatR, act);
        targetG[idx] = lerp(targetG[idx], eatG, act);
        targetB[idx] = lerp(targetB[idx], eatB, act);
      }

      float rip = rippleIntensities[idx];
      if (rip > 0.001f) {
        float rRip = (rip > 0.6f) ? lerp(0.0f, 127.0f, (rip - 0.6f) / 0.4f) : 0.0f;
        targetR[idx] = lerp(targetR[idx], rRip, rip);
        targetG[idx] = lerp(targetG[idx], 127.0f, rip);
        targetB[idx] = lerp(targetB[idx], 127.0f, rip);
      }

      currentPadR[idx] += (targetR[idx] - currentPadR[idx]) * 0.28f;
      currentPadG[idx] += (targetG[idx] - currentPadG[idx]) * 0.28f;
      currentPadB[idx] += (targetB[idx] - currentPadB[idx]) * 0.28f;
    }
  }

  java.util.ArrayList<Integer> dirtyIndices = new java.util.ArrayList<Integer>();
  for (int i = 0; i < 64; i++) {
    byte qR = (byte) constrain(round(currentPadR[i]), 0, 127);
    byte qG = (byte) constrain(round(currentPadG[i]), 0, 127);
    byte qB = (byte) constrain(round(currentPadB[i]), 0, 127);
    if (qR != lastSentPadR[i] || qG != lastSentPadG[i] || qB != lastSentPadB[i]) {
      dirtyIndices.add(i);
    }
  }

  if (!dirtyIndices.isEmpty()) {
    int CHUNK_SIZE = 50; 
    for (int i = 0; i < dirtyIndices.size(); i += CHUNK_SIZE) {
      int chunkCount = Math.min(CHUNK_SIZE, dirtyIndices.size() - i);
      byte[] sysexData = new byte[7 + chunkCount * 5 + 1];
      sysexData[0] = (byte) 0xF0;
      sysexData[1] = (byte) 0x00;
      sysexData[2] = (byte) 0x20;
      sysexData[3] = (byte) 0x29;
      sysexData[4] = (byte) 0x02;
      sysexData[5] = midiHandler.launchpadProductId; // 0x0D
      sysexData[6] = (byte) 0x03; // Command 03h = LED Lighting

      int offset = 7;
      for (int k = 0; k < chunkCount; k++) {
        int idx = dirtyIndices.get(i + k);
        int r = idx / 8;
        int c = idx % 8;
        int ledRow = (8 - r) * 10;
        int ledIndex = ledRow + (c + 1); // 11..88 in Programmer Mode
        byte qR = (byte) constrain(round(currentPadR[idx]), 0, 127);
        byte qG = (byte) constrain(round(currentPadG[idx]), 0, 127);
        byte qB = (byte) constrain(round(currentPadB[idx]), 0, 127);
        lastSentPadR[idx] = qR;
        lastSentPadG[idx] = qG;
        lastSentPadB[idx] = qB;
        sysexData[offset++] = (byte) 0x03;
        sysexData[offset++] = (byte) ledIndex;
        sysexData[offset++] = qR;
        sysexData[offset++] = qG;
        sysexData[offset++] = qB;
      }
      sysexData[offset] = (byte) 0xF7;
      midiHandler.sendLpSysex(sysexData);
    }
  }
}

// Primary Channel-Based MIDI Streaming (Static Ch 1, Flashing Ch 2, Pulsing Ch 3 with 128-color palette)
void sendLaunchpadPaletteNotes(float[] rippleIntensities) {
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      int idx = r * 8 + c;
      int progNote = (8 - r) * 10 + (c + 1);
      int userNote = getLaunchpadUserNote(c, r);
      int note = lpUserMode ? userNote : progNote;

      FoodNodule cellFood = findFoodNoduleAt(c, r);
      int targetChan = 1; // 1 = Static, 2 = Flashing, 3 = Pulsing
      int targetVel = 0;  // Palette entry (0 = off)

      boolean hasFood = (cellFood != null && cellFood.nutrients > 0);
      boolean isEating = hasFood && (cellFood.consumptionActivity > 0.05f);

      // Base mold layer: multi-step continuous palette gradient reflecting living biomass
      if (lpShowSlime) {
        smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18f;
        float mass = smoothBiomass[idx];
        float t = max(10.0f, ledMassThreshold);

        if (mass >= t * 0.7f) {
          if (paletteIdx == 2) { // Cyan theme
            if (mass >= t * 6.0f)       { targetChan = 1; targetVel = 3; }  // Bright White core
            else if (mass >= t * 4.0f)  { targetChan = 1; targetVel = 78; } // Aqua Cyan
            else if (mass >= t * 2.5f)  { targetChan = 1; targetVel = 37; } // Electric Cyan
            else if (mass >= t * 1.5f)  { targetChan = 1; targetVel = 38; } // Cerulean
            else if (mass >= t * 1.0f)  { targetChan = 1; targetVel = 39; } // Deep Cerulean
            else                        { targetChan = 3; targetVel = 39; } // Pulsing Deep Cerulean edge
          } else if (paletteIdx == 1) { // Mono theme
            if (mass >= t * 6.0f)       { targetChan = 1; targetVel = 3; }  // Bright White core
            else if (mass >= t * 3.5f)  { targetChan = 1; targetVel = 2; }  // Medium White
            else if (mass >= t * 1.5f)  { targetChan = 1; targetVel = 1; }  // Dim Cool White
            else                        { targetChan = 3; targetVel = 1; }  // Pulsing edge
          } else { // Yellow / Zorn theme (default)
            if (mass >= t * 8.0f)       { targetChan = 1; targetVel = 12; } // Pale Lemon Yellow
            else if (mass >= t * 5.0f)  { targetChan = 1; targetVel = 13; } // Brilliant Yellow
            else if (mass >= t * 3.2f)  { targetChan = 1; targetVel = 14; } // Mid Mustard
            else if (mass >= t * 2.2f)  { targetChan = 1; targetVel = 15; } // Dark Ochre
            else if (mass >= t * 1.5f)  { targetChan = 1; targetVel = 62; } // Warm Mustard Gold
            else if (mass >= t * 1.0f)  { targetChan = 1; targetVel = 84; } // Luminous Amber
            else                        { targetChan = 3; targetVel = 11; } // Pulsing Amber Edge
          }
        }
      }

      // Idle Food layer: Electric Cyan breathing pulse
      if (hasFood && lpShowFood && !isEating) {
        targetChan = 3; // Pulsing
        targetVel = 37; // Electric Cyan
      }

      // Eating layer: Vivid Magenta -> Purple degradation gradient
      if (isEating && lpShowEating) {
        float fr = cellFood.nutrients / cellFood.initialCapacity;
        smoothFoodRatio[idx] += (fr - smoothFoodRatio[idx]) * 0.25f;
        float rFr = smoothFoodRatio[idx];
        targetChan = 3; // Pulsing
        if (rFr > 0.65f) targetVel = 53;      // Vivid Magenta
        else if (rFr > 0.35f) targetVel = 54; // Deep Magenta
        else if (rFr > 0.15f) targetVel = 55; // Purple
        else targetVel = 52;                  // Soft Orchid / Royal Purple
      }

      // Ripple wavefront overlay: expanding wave on pad drops
      float rip = rippleIntensities[idx];
      if (rip > 0.08f) {
        targetChan = 1; // Static bright (cuts through pulsing background)
        if (rip > 0.55f) targetVel = 3;       // Radiant White crest
        else if (rip > 0.32f) targetVel = 37; // Electric Cyan
        else if (rip > 0.18f) targetVel = 78; // Aqua Cyan
        else targetVel = 29;                  // Soft Seafoam tail
      }

      if (padDirtyStates[idx] != (byte) targetVel || padDirtyChannels[idx] != targetChan) {
        padDirtyStates[idx] = (byte) targetVel;
        padDirtyChannels[idx] = targetChan;
        midiHandler.sendLpPadNote(targetChan, note, targetVel);
      }
    }
  }
}

void flushLaunchpadLeds() {
  if (!midiEnabled || midiHandler == null || !midiHandler.isLpReady()) return;

  long now = millis();
  if (now - lastMidiLedUpdate < 33) return; // ~30 Hz rate limiting
  lastMidiLedUpdate = now;

  float[] rippleIntensities = new float[64];
  updateRipples(now, rippleIntensities);

  if (lpUseRgbSysex) {
    sendLaunchpadRgbSysex(now, rippleIntensities);
  }

  sendLaunchpadPaletteNotes(rippleIntensities);
}

class MidiHandler implements Receiver {
  // Launchpad devices
  MidiDevice lpInputDevice;
  MidiDevice lpOutputDevice;
  Transmitter lpTransmitter;
  volatile Receiver lpReceiver;
  int lpInSel = 0;
  int lpOutSel = 0;

  // MIDImix devices
  MidiDevice mmInputDevice;
  MidiDevice mmOutputDevice;
  Transmitter mmTransmitter;
  volatile Receiver mmReceiver;
  int mmInSel = 0;
  int mmOutSel = 0;

  // Backwards compatibility aliases
  int inSel = 0;
  int outSel = 0;
  volatile boolean ready = false;
  boolean inputIsMidimix = false;
  boolean outputIsMidimix = false;
  byte launchpadProductId = 0x0D;

  ArrayList<MidiDevice.Info> inInfos = new ArrayList<MidiDevice.Info>();
  ArrayList<MidiDevice.Info> outInfos = new ArrayList<MidiDevice.Info>();
  String[] inNames = {"(none)"};
  String[] outNames = {"(none)"};

  void scanDevices() {
    inInfos.clear();
    outInfos.clear();
    try {
      for (MidiDevice.Info info : MidiSystem.getMidiDeviceInfo()) {
        MidiDevice dev = MidiSystem.getMidiDevice(info);
        if (dev instanceof Sequencer || dev instanceof Synthesizer) continue;
        if (dev.getMaxTransmitters() != 0) inInfos.add(info);
        if (dev.getMaxReceivers() != 0) outInfos.add(info);
      }
    } catch (Exception e) {
      println("MIDI Scan Notice: " + e.getMessage());
    }
    inNames = buildNames(inInfos);
    outNames = buildNames(outInfos);
    lpInSel = (lpInputDevice != null) ? inInfos.indexOf(lpInputDevice.getDeviceInfo()) + 1 : 0;
    lpOutSel = (lpOutputDevice != null) ? outInfos.indexOf(lpOutputDevice.getDeviceInfo()) + 1 : 0;
    mmInSel = (mmInputDevice != null) ? inInfos.indexOf(mmInputDevice.getDeviceInfo()) + 1 : 0;
    mmOutSel = (mmOutputDevice != null) ? outInfos.indexOf(mmOutputDevice.getDeviceInfo()) + 1 : 0;
    inSel = lpInSel > 0 ? lpInSel : mmInSel;
    outSel = lpOutSel > 0 ? lpOutSel : mmOutSel;
    ready = isReady();
  }

  String[] buildNames(ArrayList<MidiDevice.Info> infos) {
    String[] names = new String[infos.size() + 1];
    names[0] = "(none)";
    for (int i = 0; i < infos.size(); i++) names[i + 1] = infos.get(i).getName();
    return names;
  }

  int scoreLaunchpadDevice(MidiDevice.Info info) {
    String n = (info.getName() + " " + info.getDescription()).toLowerCase();
    if (!(n.contains("launchpad") || n.contains("lpmk3") || n.contains("lpmini"))) return 0;
    int s = 2;
    // Handle macOS 31-char name truncation where "MIDI" becomes "MI" and "DAW" becomes "DA"
    if (n.contains("midi") || n.endsWith(" mi")) s += 10;
    if (n.contains("daw") || n.endsWith(" da")) s -= 10;
    return s;
  }

  int scoreMidimixDevice(MidiDevice.Info info) {
    String n = (info.getName() + " " + info.getDescription()).toLowerCase();
    if (n.contains("midimix")) return 10;
    return 0;
  }

  int bestDevice(ArrayList<MidiDevice.Info> infos, boolean isMidimix) {
    int best = -1, bestScore = 0;
    for (int i = 0; i < infos.size(); i++) {
      int s = isMidimix ? scoreMidimixDevice(infos.get(i)) : scoreLaunchpadDevice(infos.get(i));
      if (s > bestScore) { bestScore = s; best = i; }
    }
    return best + 1; // 0 = none
  }

  void initDevices() {
    scanDevices();
    openLpInput(bestDevice(inInfos, false));
    openLpOutput(bestDevice(outInfos, false));
    openMmInput(bestDevice(inInfos, true));
    openMmOutput(bestDevice(outInfos, true));
  }

  void openLpInput(int sel) {
    try {
      if (lpTransmitter != null) lpTransmitter.close();
      if (lpInputDevice != null) lpInputDevice.close();
    } catch (Exception e) {}
    lpTransmitter = null;
    lpInputDevice = null;
    lpInSel = 0;
    if (sel <= 0 || sel > inInfos.size()) return;
    try {
      MidiDevice.Info info = inInfos.get(sel - 1);
      lpInputDevice = MidiSystem.getMidiDevice(info);
      lpInputDevice.open();
      lpTransmitter = lpInputDevice.getTransmitter();
      lpTransmitter.setReceiver(new LaunchpadReceiver());
      lpInSel = sel;
      inSel = sel;

      // Auto-connect output for Launchpad if not already connected
      if (lpOutSel == 0 || lpReceiver == null) {
        for (int i = 0; i < outInfos.size(); i++) {
          String outN = (outInfos.get(i).getName() + " " + outInfos.get(i).getDescription()).toLowerCase();
          boolean isDaw = outN.contains("daw") || outN.endsWith(" da");
          if ((outN.contains("launchpad") || outN.contains("lpmk3") || outN.contains("lpmini")) && !isDaw) {
            openLpOutput(i + 1);
            if (midiOutDropdown != null) midiOutDropdown.selected = i + 1;
            break;
          }
        }
      }
    } catch (Exception e) {
      println("Launchpad Input Open Err: " + e.getMessage());
      lpInputDevice = null;
    }
  }

  void openLpOutput(int sel) {
    if (midiEnabled && isLpReady()) exitProgrammerMode();
    try {
      if (lpReceiver != null) lpReceiver.close();
      if (lpOutputDevice != null) lpOutputDevice.close();
    } catch (Exception e) {}
    lpReceiver = null;
    lpOutputDevice = null;
    lpOutSel = 0;
    if (sel > 0 && sel <= outInfos.size()) {
      try {
        MidiDevice.Info info = outInfos.get(sel - 1);
        lpOutputDevice = MidiSystem.getMidiDevice(info);
        lpOutputDevice.open();
        lpReceiver = lpOutputDevice.getReceiver();
        lpOutSel = sel;
        outSel = sel;
      } catch (Exception e) {
        println("Launchpad Output Open Err: " + e.getMessage());
        lpOutputDevice = null;
      }
    }
    ready = isReady();
    if (midiEnabled && isLpReady()) enterLpProgrammerMode();
  }

  void openMmInput(int sel) {
    try {
      if (mmTransmitter != null) mmTransmitter.close();
      if (mmInputDevice != null) mmInputDevice.close();
    } catch (Exception e) {}
    mmTransmitter = null;
    mmInputDevice = null;
    mmInSel = 0;
    if (sel <= 0 || sel > inInfos.size()) return;
    try {
      MidiDevice.Info info = inInfos.get(sel - 1);
      mmInputDevice = MidiSystem.getMidiDevice(info);
      mmInputDevice.open();
      mmTransmitter = mmInputDevice.getTransmitter();
      mmTransmitter.setReceiver(new MidimixReceiver());
      mmInSel = sel;

      // Auto-connect output for MIDImix if not already connected
      if (mmOutSel == 0 || mmReceiver == null) {
        for (int i = 0; i < outInfos.size(); i++) {
          String outN = (outInfos.get(i).getName() + " " + outInfos.get(i).getDescription()).toLowerCase();
          if (outN.contains("midimix")) {
            openMmOutput(i + 1);
            if (midimixOutDropdown != null) midimixOutDropdown.selected = i + 1;
            break;
          }
        }
      }
    } catch (Exception e) {
      println("MIDImix Input Open Err: " + e.getMessage());
      mmInputDevice = null;
    }
  }

  void openMmOutput(int sel) {
    try {
      if (mmReceiver != null) mmReceiver.close();
      if (mmOutputDevice != null) mmOutputDevice.close();
    } catch (Exception e) {}
    mmReceiver = null;
    mmOutputDevice = null;
    mmOutSel = 0;
    if (sel > 0 && sel <= outInfos.size()) {
      try {
        MidiDevice.Info info = outInfos.get(sel - 1);
        mmOutputDevice = MidiSystem.getMidiDevice(info);
        mmOutputDevice.open();
        mmReceiver = mmOutputDevice.getReceiver();
        mmOutSel = sel;
      } catch (Exception e) {
        println("MIDImix Output Open Err: " + e.getMessage());
        mmOutputDevice = null;
      }
    }
    ready = isReady();
    if (midiEnabled && isMmReady()) syncMidiMixLeds();
  }

  // Generic openInput / openOutput for backwards compatibility
  void openInput(int sel) { openLpInput(sel); }
  void openOutput(int sel) { openLpOutput(sel); }

  boolean isReady() {
    return isLpReady() || isMmReady();
  }

  boolean isLpReady() {
    return lpReceiver != null;
  }

  boolean isMmReady() {
    return mmReceiver != null;
  }

  void enterProgrammerMode() {
    if (isLpReady()) enterLpProgrammerMode();
    if (isMmReady()) syncMidiMixLeds();
  }

  void enterLpProgrammerMode() {
    if (!isLpReady()) return;
    // 1. Switch to Programmer mode layout (0Eh 01h and 00h 7Fh)
    byte[] enterProg = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x0E, 0x01, (byte)0xF7};
    sendLpSysex(enterProg);
    byte[] selectLayout = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x00, 0x7F, (byte)0xF7};
    sendLpSysex(selectLayout);

    // 2. Set LED brightness to maximum (08h 7Fh)
    byte[] setBrightness = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x08, 0x7F, (byte)0xF7};
    sendLpSysex(setBrightness);

    // 3. Suppress internal button LED feedback, enable host external feedback (0Ah 00h 01h)
    byte[] setFeedback = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x0A, 0x00, 0x01, (byte)0xF7};
    sendLpSysex(setFeedback);

    for (int i = 0; i < 64; i++) {
      padDirtyStates[i] = (byte) 255;
      padDirtyChannels[i] = -1;
      lastSentPadR[i] = (byte) -1;
      lastSentPadG[i] = (byte) -1;
      lastSentPadB[i] = (byte) -1;
    }
    syncLpSideLeds();
  }

  void exitProgrammerMode() {
    // 1. Restore Live Mode (0Eh 00h) and Standalone Mode (10h 00h) so physical Setup button is unlocked
    byte[] exitProg = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x0E, 0x00, (byte)0xF7};
    sendLpSysex(exitProg);
    byte[] setStandalone = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, launchpadProductId, 0x10, 0x00, (byte)0xF7};
    sendLpSysex(setStandalone);

    sendLpCc(1, 89, 0);
    sendLpCc(1, 79, 0);
    sendLpCc(1, 39, 0);
    sendLpCc(1, 29, 0);
    sendLpCc(1, 19, 0);
  }

  void syncLpSideLeds() {
    if (!isLpReady()) return;
    // Top side button: Re-inoculate (Soft Yellow / Bright Yellow)
    sendLpCc(1, 89, lpTopSidePressed ? 13 : 15);
    // 2nd side button: Clear food (Soft Red / Bright Red)
    sendLpCc(1, 79, lpSecSidePressed ? 5 : 7);
    // Bottom 3 side buttons: LED display layer toggles (On/Off)
    sendLpCc(1, 39, lpShowSlime ? 13 : 0);   // LED Mold layer (Yellow)
    sendLpCc(1, 29, lpShowFood ? 37 : 0);    // LED Food layer (Cyan)
    sendLpCc(1, 19, lpShowEating ? 53 : 0);  // LED Eating layer (Magenta)
  }

  void syncMidiMixLeds() {
    if (!isMmReady()) return;
    if (pauseToggle != null) sendMmPadColor(1, pauseToggle.state ? 127 : 0);
    if (audioToggle != null) sendMmPadColor(4, audioToggle.state ? 127 : 0);
    if (fullScreenToggle != null) sendMmPadColor(7, fullScreenToggle.state ? 127 : 0);
    if (gridOverlayToggle != null) sendMmPadColor(10, gridOverlayToggle.state ? 127 : 0);
    if (reverbToggle != null) sendMmPadColor(13, reverbToggle.state ? 127 : 0);
    if (bioModToggle != null) sendMmPadColor(16, bioModToggle.state ? 127 : 0);
  }

  void sendLpSysex(byte[] data) {
    Receiver r = lpReceiver;
    if (!ready && !isLpReady() || r == null) return;
    try {
      SysexMessage msg = new SysexMessage();
      try {
        msg.setMessage(data, data.length);
      } catch (Exception eInner) {
        msg.setMessage(0xF0, data, data.length);
      }
      r.send(msg, -1);
    } catch (Exception e) {
      System.err.println("SysEx Send Error (" + data.length + " bytes): " + e.getMessage());
      e.printStackTrace();
    }
  }

  void sendLpPadNote(int channel, int note, int velocity) {
    Receiver r = lpReceiver;
    if (r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      int ch = constrain(channel - 1, 0, 15);
      msg.setMessage(ShortMessage.NOTE_ON, ch, note, constrain(velocity, 0, 127));
      r.send(msg, -1);
    } catch (Exception e) {}
  }

  void sendLpCc(int channel, int cc, int value) {
    Receiver r = lpReceiver;
    if (r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      int ch = constrain(channel - 1, 0, 15);
      msg.setMessage(ShortMessage.CONTROL_CHANGE, ch, cc, constrain(value, 0, 127));
      r.send(msg, -1);
    } catch (Exception e) {}
  }

  void sendMmPadColor(int note, int velocity) {
    Receiver r = mmReceiver;
    if (r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      msg.setMessage(ShortMessage.NOTE_ON, 0, note, constrain(velocity, 0, 127));
      r.send(msg, -1);
    } catch (Exception e) {}
  }

  void sendPadNote(int channel, int note, int velocity) {
    sendLpPadNote(channel, note, velocity);
  }

  void sendPadColor(int note, int velocity) {
    sendMmPadColor(note, velocity);
  }

  class LaunchpadReceiver implements Receiver {
    public void send(MidiMessage message, long timeStamp) {
      if (!midiEnabled) return;
      if (message instanceof ShortMessage) handleLaunchpad((ShortMessage) message);
    }
    public void close() {}
  }

  class MidimixReceiver implements Receiver {
    public void send(MidiMessage message, long timeStamp) {
      if (!midiEnabled) return;
      if (message instanceof ShortMessage) handleMidimix((ShortMessage) message);
    }
    public void close() {}
  }

  // Fallback receiver implementation
  public void send(MidiMessage message, long timeStamp) {
    if (!midiEnabled) return;
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      handleLaunchpad(sm);
      handleMidimix(sm);
    }
  }

  private void handleLaunchpad(ShortMessage sm) {
    int cmd = sm.getCommand();
    int d1 = sm.getData1();
    int d2 = sm.getData2();

    if (cmd == ShortMessage.NOTE_ON && d2 > 0) {
      handleLaunchpadNote(d1, d2);
    } else if (cmd == ShortMessage.CONTROL_CHANGE) {
      handleLaunchpadCc(d1, d2);
    }
  }

  void handleLaunchpadNote(int note, int velocity) {
    int row = -1;
    int col = -1;

    // Auto-detect Programmer vs User mode:
    if (note < 36 && note >= 11) {
      lpUserMode = false;
    } else if (note > 88 && note <= 99) {
      lpUserMode = true;
    } else if (note >= 36 && note <= 88) {
      int c10 = note % 10;
      if (c10 == 9 || c10 == 0) {
        lpUserMode = true;
      }
    }

    if (lpUserMode) {
      if (note >= 36 && note <= 99) {
        int[] cr = decodeLaunchpadUserNote(note);
        col = cr[0];
        row = cr[1];
      }
    } else {
      int progRow = note / 10;
      int progCol = note % 10;
      if (progRow >= 1 && progRow <= 8 && progCol >= 1 && progCol <= 8) {
        row = 8 - progRow;
        col = progCol - 1;
      }
    }

    if (row >= 0 && row < 8 && col >= 0 && col < 8) {
      float cellW = float(SIM_W) / GRID_DIM;
      float cellH = float(SIM_H) / GRID_DIM;
      float x = col * cellW + random(8, cellW - 8);
      float y = row * cellH + random(8, cellH - 8);
      float r = random(8.0f, 24.0f);
      addFoodNodule(x, y, r, r * r * 2.0f);
      triggerPadRipple(col, row, x, y);
    }
  }

  void handleLaunchpadCc(int cc, int value) {
    // Launchpad perimeter side buttons (Scene Launch column: CC 89, 79, 69, 59, 49, 39, 29, 19)
    if (value > 0) {
      // Press
      if (cc == 89) {
        lpTopSidePressed = true;
        reinoculate();
        sendLpCc(1, 89, 13); // Flash brilliant yellow
      } else if (cc == 79) {
        lpSecSidePressed = true;
        clearAllFood();
        sendLpCc(1, 79, 5); // Flash brilliant vermilion red
      } else if (cc == 39) {
        if (lpShowSlimeToggle != null) lpShowSlimeToggle.set(!lpShowSlimeToggle.state, true);
        else { lpShowSlime = !lpShowSlime; syncLpSideLeds(); }
      } else if (cc == 29) {
        if (lpShowFoodToggle != null) lpShowFoodToggle.set(!lpShowFoodToggle.state, true);
        else { lpShowFood = !lpShowFood; syncLpSideLeds(); }
      } else if (cc == 19) {
        if (lpShowEatingToggle != null) lpShowEatingToggle.set(!lpShowEatingToggle.state, true);
        else { lpShowEating = !lpShowEating; syncLpSideLeds(); }
      }
    } else {
      // Release (value == 0)
      if (cc == 89) {
        lpTopSidePressed = false;
        sendLpCc(1, 89, 15); // Return to soft yellow idle glow
      } else if (cc == 79) {
        lpSecSidePressed = false;
        sendLpCc(1, 79, 7); // Return to soft red idle glow
      }
    }
  }

  private void handleMidimix(ShortMessage sm) {
    int cmd = sm.getCommand();
    int d1 = sm.getData1();
    int d2 = sm.getData2();

    if (cmd == ShortMessage.NOTE_ON && d2 > 0) {
      handleMidimixButton(d1, true);
    } else if (cmd == ShortMessage.NOTE_OFF || (cmd == ShortMessage.NOTE_ON && d2 == 0)) {
      handleMidimixButton(d1, false);
    } else if (cmd == ShortMessage.CONTROL_CHANGE) {
      handleMidimixKnobOrFader(d1, d2 / 127.0f);
    }
  }

  void setSliderIfPresent(Slider s, float val) {
    if (s != null) s.setValue(val, true);
  }

  void togglePadIfPresent(Toggle t, int note) {
    if (t != null) {
      t.set(!t.state, true);
      sendPadColor(note, t.state ? 127 : 0);
    }
  }

  void handleMidimixButton(int note, boolean pressed) {
    if (pressed) {
      // Mute Row 1-6 Toggles
      if (note == 1) togglePadIfPresent(pauseToggle, 1);
      else if (note == 4) togglePadIfPresent(audioToggle, 4);
      else if (note == 7) togglePadIfPresent(fullScreenToggle, 7);
      else if (note == 10) togglePadIfPresent(gridOverlayToggle, 10);
      else if (note == 13) togglePadIfPresent(reverbToggle, 13);
      else if (note == 16) togglePadIfPresent(bioModToggle, 16);
      // Rec Arm Row 1-5 Momentary Actions
      else if (note == 3) { scatterInitialFood(4); sendPadColor(3, 127); }
      else if (note == 6) { clearAllFood(); sendPadColor(6, 127); }
      else if (note == 9) { reinoculate(); sendPadColor(9, 127); }
      else if (note == 12) { rescanMidi(); sendPadColor(12, 127); }
      else if (note == 15) { reverbSeed = System.nanoTime(); triggerIrRegenerationAsync(); sendPadColor(15, 127); }
    } else {
      // Turn off momentary LEDs on button release
      if (note == 3 || note == 6 || note == 9 || note == 12 || note == 15) {
        sendPadColor(note, 0);
      }
    }
  }

  void handleMidimixKnobOrFader(int cc, float val) {
    // Faders 1-8 -> Audio Controls
    if (cc == 19) setSliderIfPresent(filterSensSlider, lerp(0.2f, 3.0f, val));
    else if (cc == 23) setSliderIfPresent(filterQSlider, lerp(0.5f, 18.0f, val));
    else if (cc == 27) setSliderIfPresent(vcaSensSlider, lerp(0.2f, 3.0f, val));
    else if (cc == 28) setSliderIfPresent(reverbWetSlider, lerp(0.0f, 1.0f, val));
    else if (cc == 29) setSliderIfPresent(reverbDrySlider, lerp(0.0f, 1.0f, val));
    else if (cc == 30) setSliderIfPresent(reverbT60Slider, lerp(0.5f, 8.0f, val));
    else if (cc == 31) setSliderIfPresent(reverbDampSlider, lerp(0.05f, 0.95f, val));
    else if (cc == 33) setSliderIfPresent(reverbPreSlider, lerp(0.005f, 0.060f, val));
    // Master Fader -> Simulation Speed
    else if (cc == 11) setSliderIfPresent(simSpeedSlider, lerp(0.1f, 30.0f, val));
    // Track 1 Rotary Knobs -> Bioenergetics
    else if (cc == 16) setSliderIfPresent(sensorDistSlider, lerp(6.0f, 160.0f, val));
    else if (cc == 20) setSliderIfPresent(bmrSlider, lerp(0.001f, 0.050f, val));
    else if (cc == 24) setSliderIfPresent(locoCostSlider, lerp(0.002f, 0.080f, val));
    // Track 2 Rotary Knobs -> Visuals & Targets
    else if (cc == 17) setSliderIfPresent(visualSharpnessSlider, val);
    else if (cc == 21) setSliderIfPresent(agentCountSlider, lerp(1000f, 64000f, val));
    else if (cc == 25) setSliderIfPresent(visualBlurSlider, lerp(0.0f, 8.0f, val));
    // Track 3 Rotary Knobs -> Harmonizer & LED Sensitivity
    else if (cc == 18) {
      int newOct = round(lerp(0f, 2f, val));
      if (newOct != octaveShiftIdx) {
        octaveShiftIdx = newOct;
        retuneAllNodules();
      }
    }
    else if (cc == 22) setSliderIfPresent(ledThresholdSlider, lerp(20.0f, 1000.0f, val));
    else if (cc == 26) setSliderIfPresent(reverbBioModSlider, lerp(0.0f, 4.0f, val));
  }

  public void close() {}

  void shutdown() {
    exitProgrammerMode();
    openLpInput(0);
    openLpOutput(0);
    openMmInput(0);
    openMmOutput(0);
    ready = false;
  }
}
