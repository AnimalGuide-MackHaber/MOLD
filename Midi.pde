// =============================================================================
// Midi.pde - Hardware MIDI Controller Integration (Launchpad Mini & Akai MIDImix)
// =============================================================================

// Smooth LED state and transition tracking
int[] padDirtyChannels = new int[64];
float[] smoothBiomass = new float[64];
float[] smoothFoodRatio = new float[64];
boolean lpTopSidePressed = false;
boolean lpSecSidePressed = false;

// Launchpad Mode: lpUserMode = true (factory User Mode / Drum Rack 36..99); false = Programmer Mode (11..88)
boolean lpUseRgbSysex = false;
boolean lpUserMode = true;

// Continuous 7-bit RGB pad states for silky smooth temporal transitions
float[] currentPadR = new float[64];
float[] currentPadG = new float[64];
float[] currentPadB = new float[64];
byte[] lastSentPadR = new byte[64];
byte[] lastSentPadG = new byte[64];
byte[] lastSentPadB = new byte[64];

// Palette tiers for bio-telemetry LED standard
final int[] ZORN_VELS = {12, 13, 14, 15, 62, 84, 11};
final float[] ZORN_MULTS = {8.0f, 5.0f, 3.2f, 2.2f, 1.5f, 1.0f, 0.7f};
final int[] CYAN_VELS = {3, 78, 37, 38, 39, 39};
final float[] CYAN_MULTS = {6.0f, 4.0f, 2.5f, 1.5f, 1.0f, 0.7f};
final int[] MONO_VELS = {3, 2, 1, 1};
final float[] MONO_MULTS = {6.0f, 3.5f, 1.5f, 0.7f};

final float[][] ZORN_STOPS = {
  {0.00f, 12f, 6f, 1f}, {0.33f, 65f, 38f, 4f},
  {0.66f, 117f, 90f, 6f}, {1.00f, 127f, 120f, 69f}
};

// User Mode (Drum Rack 4-Quadrant) note calculation for pad (col, row)
int getLaunchpadUserNote(int col, int row) {
  int quadX = col / 4, quadY = row / 4;
  int subX  = col % 4, subY  = 3 - (row % 4);
  int baseNote = (quadX == 0) ? (quadY == 1 ? 36 : 52) : (quadY == 1 ? 68 : 84);
  return baseNote + (subY * 4) + subX;
}

// User Mode (Drum Rack 4-Quadrant) decoding: note (36..99) -> [col, row]
int[] decodeLaunchpadUserNote(int note) {
  int index = note - 36;
  int quad = index / 16, sub = index % 16;
  int col = (quad >= 2 ? 4 : 0) + (sub % 4);
  int row = (quad % 2 == 0 ? 7 : 3) - (sub / 4);
  return new int[]{col, row};
}

// Ripple effect on food drop
class PadRipple {
  int originCol, originRow;
  float worldX, worldY;
  long birthTime;
  float durationMs = 900.0f, maxRadius = 11.5f;

  PadRipple(int c, int r, float wx, float wy) {
    originCol = c; originRow = r; worldX = wx; worldY = wy;
    birthTime = millis();
  }

  float progress(long now) { return (now - birthTime) / durationMs; }
}

java.util.concurrent.CopyOnWriteArrayList<PadRipple> padRipples = new java.util.concurrent.CopyOnWriteArrayList<PadRipple>();

void triggerPadRipple(int col, int row, float wx, float wy) {
  padRipples.add(new PadRipple(col, row, wx, wy));
}

// Continuous RGB colormap evaluation matching active shader palette
void evaluateBiomassGradient(float mass, float threshold, int palIdx, float[] outRgb) {
  float u = constrain((mass - threshold) / (threshold * 7.0f), 0.0f, 1.0f);
  float up = pow(u, 0.75f);
  if (up <= 0.001f) {
    outRgb[0] = 0; outRgb[1] = 0; outRgb[2] = 0;
    return;
  }

  if (palIdx == 1) { // Mono
    float r = lerp(12.0f, 122.0f, up);
    outRgb[0] = r; outRgb[1] = r; outRgb[2] = r;
  } else if (palIdx == 2) { // Cyan
    float f = (up < 0.5f) ? up * 2.0f : (up - 0.5f) * 2.0f;
    float r0 = (up < 0.5f) ? 2.0f : 17.0f,  r1 = (up < 0.5f) ? 17.0f : 103.0f;
    float g0 = (up < 0.5f) ? 26.0f : 105.0f, g1 = (up < 0.5f) ? 105.0f : 125.0f;
    float b0 = (up < 0.5f) ? 37.0f : 119.0f, b1 = (up < 0.5f) ? 119.0f : 127.0f;
    outRgb[0] = lerp(r0, r1, f); outRgb[1] = lerp(g0, g1, f); outRgb[2] = lerp(b0, b1, f);
  } else { // Yellow (Zorn)
    int i = (up < 0.33f) ? 0 : (up < 0.66f ? 1 : 2);
    float f = (up - ZORN_STOPS[i][0]) / (ZORN_STOPS[i + 1][0] - ZORN_STOPS[i][0]);
    outRgb[0] = lerp(ZORN_STOPS[i][1], ZORN_STOPS[i + 1][1], f);
    outRgb[1] = lerp(ZORN_STOPS[i][2], ZORN_STOPS[i + 1][2], f);
    outRgb[2] = lerp(ZORN_STOPS[i][3], ZORN_STOPS[i + 1][3], f);
  }
}

FoodNodule findFoodNoduleAt(int col, int row) {
  for (FoodNodule fn : foodNodes) {
    if (fn.gridCol == col && fn.gridRow == row) return fn;
  }
  return null;
}

void updateRipples(long now, float[] rippleIntensities) {
  java.util.ArrayList<PadRipple> expired = new java.util.ArrayList<PadRipple>();
  for (PadRipple pr : padRipples) {
    if (pr.progress(now) >= 1.0f) expired.add(pr);
  }
  padRipples.removeAll(expired);

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
        float delta = abs(dist(c, r, pr.originCol, pr.originRow) - rWave);
        float crest = amp * exp(-(delta * delta) / twoSigmaSq);
        if (c == pr.originCol && r == pr.originRow && tau < 0.25f) {
          crest = max(crest, pow(1.0f - (tau / 0.25f), 1.5f));
        }
        rippleIntensities[idx] = min(1.0f, rippleIntensities[idx] + crest);
      }
    }
  }
}

// Stream continuous 7-bit RGB gradients to Launchpad via SysEx Command 03h Type 3
void sendLaunchpadRgbSysex(long now, float[] rippleIntensities) {
  float[] moldRgb = new float[3];

  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      int idx = r * 8 + c;
      FoodNodule cellFood = findFoodNoduleAt(c, r);
      boolean hasFood = (cellFood != null && cellFood.nutrients > 0);
      boolean isEating = hasFood && (cellFood.consumptionActivity > 0.05f);

      float tR = 0, tG = 0, tB = 0;
      if (lpShowSlime) {
        smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18f;
        evaluateBiomassGradient(smoothBiomass[idx], max(10.0f, ledMassThreshold), paletteIdx, moldRgb);
        tR = moldRgb[0]; tG = moldRgb[1]; tB = moldRgb[2];
      }

      if (hasFood && lpShowFood && !isEating) {
        float breath = 0.85f + 0.15f * sin(now * 0.005f + (r + c) * 0.5f);
        tG = max(tG, 110.0f * breath);
        tB = max(tB, 127.0f * breath);
      }

      if (isEating && lpShowEating) {
        float fr = cellFood.nutrients / cellFood.initialCapacity;
        smoothFoodRatio[idx] += (fr - smoothFoodRatio[idx]) * 0.25f;
        float feedPulse = 0.85f + 0.15f * sin(now * 0.012f);
        float act = constrain(cellFood.consumptionActivity, 0.0f, 1.0f);
        tR = lerp(tR, lerp(60.0f, 127.0f, smoothFoodRatio[idx]) * feedPulse, act);
        tG = lerp(tG, 0.0f, act);
        tB = lerp(tB, lerp(110.0f, 75.0f, smoothFoodRatio[idx]) * feedPulse, act);
      }

      float rip = rippleIntensities[idx];
      if (rip > 0.001f) {
        float rRip = (rip > 0.6f) ? lerp(0.0f, 127.0f, (rip - 0.6f) / 0.4f) : 0.0f;
        tR = lerp(tR, rRip, rip);
        tG = lerp(tG, 127.0f, rip);
        tB = lerp(tB, 127.0f, rip);
      }

      currentPadR[idx] += (tR - currentPadR[idx]) * 0.28f;
      currentPadG[idx] += (tG - currentPadG[idx]) * 0.28f;
      currentPadB[idx] += (tB - currentPadB[idx]) * 0.28f;
    }
  }

  java.util.ArrayList<Integer> dirty = new java.util.ArrayList<Integer>();
  for (int i = 0; i < 64; i++) {
    byte qR = (byte) constrain(round(currentPadR[i]), 0, 127);
    byte qG = (byte) constrain(round(currentPadG[i]), 0, 127);
    byte qB = (byte) constrain(round(currentPadB[i]), 0, 127);
    if (qR != lastSentPadR[i] || qG != lastSentPadG[i] || qB != lastSentPadB[i]) dirty.add(i);
  }

  if (!dirty.isEmpty()) {
    int CHUNK_SIZE = 50;
    for (int i = 0; i < dirty.size(); i += CHUNK_SIZE) {
      int chunkCount = Math.min(CHUNK_SIZE, dirty.size() - i);
      byte[] sysexData = new byte[7 + chunkCount * 5 + 1];
      sysexData[0] = (byte) 0xF0; sysexData[1] = 0x00; sysexData[2] = 0x20;
      sysexData[3] = 0x29; sysexData[4] = 0x02;
      sysexData[5] = midiHandler.launchpadProductId; // 0x0D
      sysexData[6] = (byte) 0x03; // Command 03h = LED Lighting

      int offset = 7;
      for (int k = 0; k < chunkCount; k++) {
        int idx = dirty.get(i + k);
        int ledIndex = (8 - (idx / 8)) * 10 + (idx % 8 + 1); // 11..88
        byte qR = (byte) constrain(round(currentPadR[idx]), 0, 127);
        byte qG = (byte) constrain(round(currentPadG[idx]), 0, 127);
        byte qB = (byte) constrain(round(currentPadB[idx]), 0, 127);
        lastSentPadR[idx] = qR; lastSentPadG[idx] = qG; lastSentPadB[idx] = qB;
        sysexData[offset++] = (byte) 0x03;
        sysexData[offset++] = (byte) ledIndex;
        sysexData[offset++] = qR; sysexData[offset++] = qG; sysexData[offset++] = qB;
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
      int note = lpUserMode ? getLaunchpadUserNote(c, r) : ((8 - r) * 10 + (c + 1));
      FoodNodule cellFood = findFoodNoduleAt(c, r);
      int targetChan = 1, targetVel = 0;

      boolean hasFood = (cellFood != null && cellFood.nutrients > 0);
      boolean isEating = hasFood && (cellFood.consumptionActivity > 0.05f);

      // Base mold layer: continuous palette gradient reflecting living biomass
      if (lpShowSlime) {
        smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18f;
        float mass = smoothBiomass[idx], t = max(10.0f, ledMassThreshold);
        if (mass >= t * 0.7f) {
          int[] vels = (paletteIdx == 2) ? CYAN_VELS : (paletteIdx == 1 ? MONO_VELS : ZORN_VELS);
          float[] mults = (paletteIdx == 2) ? CYAN_MULTS : (paletteIdx == 1 ? MONO_MULTS : ZORN_MULTS);
          float pulseThresh = (paletteIdx == 1) ? 1.5f : 1.0f;
          targetChan = (mass < t * pulseThresh) ? 3 : 1;
          for (int k = 0; k < mults.length; k++) {
            if (mass >= t * mults[k]) { targetVel = vels[k]; break; }
          }
        }
      }

      // Idle Food layer: Electric Cyan breathing pulse
      if (hasFood && lpShowFood && !isEating) {
        targetChan = 3; targetVel = 37;
      }

      // Eating layer: Vivid Magenta -> Purple degradation gradient
      if (isEating && lpShowEating) {
        float fr = cellFood.nutrients / cellFood.initialCapacity;
        smoothFoodRatio[idx] += (fr - smoothFoodRatio[idx]) * 0.25f;
        float rFr = smoothFoodRatio[idx];
        targetChan = 3;
        targetVel = (rFr > 0.65f) ? 53 : ((rFr > 0.35f) ? 54 : ((rFr > 0.15f) ? 55 : 52));
      }

      // Ripple wavefront overlay
      float rip = rippleIntensities[idx];
      if (rip > 0.08f) {
        targetChan = 1;
        targetVel = (rip > 0.55f) ? 3 : ((rip > 0.32f) ? 37 : ((rip > 0.18f) ? 78 : 29));
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
  if (now - lastMidiLedUpdate < 33) return; // ~30 Hz rate limit
  lastMidiLedUpdate = now;

  float[] rippleIntensities = new float[64];
  updateRipples(now, rippleIntensities);

  if (lpUseRgbSysex) sendLaunchpadRgbSysex(now, rippleIntensities);
  sendLaunchpadPaletteNotes(rippleIntensities);
}

class MidiHandler implements Receiver {
  // Reusable MIDI device connection manager
  class Port {
    MidiDevice dev;
    Transmitter tx;
    Receiver rx;
    int sel = 0;

    void close() {
      try { if (tx != null) tx.close(); } catch (Exception e) {}
      try { if (rx != null) rx.close(); } catch (Exception e) {}
      try { if (dev != null) dev.close(); } catch (Exception e) {}
      tx = null; rx = null; dev = null; sel = 0;
    }

    boolean openIn(int s, Receiver r, String name) {
      close();
      if (s <= 0 || s > inInfos.size()) return false;
      try {
        dev = MidiSystem.getMidiDevice(inInfos.get(s - 1));
        dev.open();
        tx = dev.getTransmitter();
        tx.setReceiver(r);
        sel = s;
        return true;
      } catch (Exception e) {
        println(name + " Input Open Err: " + e.getMessage());
        close();
        return false;
      }
    }

    boolean openOut(int s, String name) {
      close();
      if (s <= 0 || s > outInfos.size()) return false;
      try {
        dev = MidiSystem.getMidiDevice(outInfos.get(s - 1));
        dev.open();
        rx = dev.getReceiver();
        sel = s;
        return true;
      } catch (Exception e) {
        println(name + " Output Open Err: " + e.getMessage());
        close();
        return false;
      }
    }
  }

  Port lpIn = new Port(), lpOut = new Port();
  Port mmIn = new Port(), mmOut = new Port();

  // Public device handles & selections (preserved for test compatibility)
  MidiDevice lpInputDevice, lpOutputDevice;
  Transmitter lpTransmitter;
  volatile Receiver lpReceiver;
  int lpInSel = 0, lpOutSel = 0;

  MidiDevice mmInputDevice, mmOutputDevice;
  Transmitter mmTransmitter;
  volatile Receiver mmReceiver;
  int mmInSel = 0, mmOutSel = 0;

  int inSel = 0, outSel = 0;
  volatile boolean ready = false;
  boolean inputIsMidimix = false;
  boolean outputIsMidimix = false;
  byte launchpadProductId = 0x0D;

  ArrayList<MidiDevice.Info> inInfos = new ArrayList<MidiDevice.Info>();
  ArrayList<MidiDevice.Info> outInfos = new ArrayList<MidiDevice.Info>();
  String[] inNames = {"(none)"};
  String[] outNames = {"(none)"};

  void scanDevices() {
    inInfos.clear(); outInfos.clear();
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
    if (n.contains("midi") || n.endsWith(" mi")) s += 10;
    if (n.contains("daw") || n.endsWith(" da")) s -= 10;
    return s;
  }

  int scoreMidimixDevice(MidiDevice.Info info) {
    return (info.getName() + " " + info.getDescription()).toLowerCase().contains("midimix") ? 10 : 0;
  }

  int bestDevice(ArrayList<MidiDevice.Info> infos, boolean isMidimix) {
    int best = -1, bestScore = 0;
    for (int i = 0; i < infos.size(); i++) {
      int s = isMidimix ? scoreMidimixDevice(infos.get(i)) : scoreLaunchpadDevice(infos.get(i));
      if (s > bestScore) { bestScore = s; best = i; }
    }
    return best + 1;
  }

  void initDevices() {
    scanDevices();
    openLpInput(bestDevice(inInfos, false));
    openLpOutput(bestDevice(outInfos, false));
    openMmInput(bestDevice(inInfos, true));
    openMmOutput(bestDevice(outInfos, true));
  }

  int findAutoOut(String keyword, boolean excludeDaw) {
    for (int i = 0; i < outInfos.size(); i++) {
      String outN = (outInfos.get(i).getName() + " " + outInfos.get(i).getDescription()).toLowerCase();
      boolean isDaw = outN.contains("daw") || outN.endsWith(" da");
      if (outN.contains(keyword) && (!excludeDaw || !isDaw)) return i + 1;
    }
    return 0;
  }

  void openLpInput(int sel) {
    lpIn.openIn(sel, new LaunchpadReceiver(), "Launchpad");
    lpInputDevice = lpIn.dev; lpTransmitter = lpIn.tx; lpInSel = lpIn.sel; inSel = lpInSel;
    if ((lpOutSel == 0 || lpReceiver == null) && lpIn.dev != null) {
      int auto = findAutoOut("launchpad", true);
      if (auto > 0) {
        openLpOutput(auto);
        if (midiOutDropdown != null) midiOutDropdown.selected = auto;
      }
    }
  }

  void openLpOutput(int sel) {
    if (midiEnabled && isLpReady()) exitProgrammerMode();
    lpOut.openOut(sel, "Launchpad");
    lpOutputDevice = lpOut.dev; lpReceiver = lpOut.rx; lpOutSel = lpOut.sel; outSel = lpOutSel;
    ready = isReady();
    if (midiEnabled && isLpReady()) enterLpProgrammerMode();
  }

  void openMmInput(int sel) {
    mmIn.openIn(sel, new MidimixReceiver(), "MIDImix");
    mmInputDevice = mmIn.dev; mmTransmitter = mmIn.tx; mmInSel = mmIn.sel;
    if ((mmOutSel == 0 || mmReceiver == null) && mmIn.dev != null) {
      int auto = findAutoOut("midimix", false);
      if (auto > 0) {
        openMmOutput(auto);
        if (midimixOutDropdown != null) midimixOutDropdown.selected = auto;
      }
    }
  }

  void openMmOutput(int sel) {
    mmOut.openOut(sel, "MIDImix");
    mmOutputDevice = mmOut.dev; mmReceiver = mmOut.rx; mmOutSel = mmOut.sel;
    ready = isReady();
    if (midiEnabled && isMmReady()) syncMidiMixLeds();
  }

  void openInput(int sel)  { openLpInput(sel); }
  void openOutput(int sel) { openLpOutput(sel); }

  boolean isReady()   { return isLpReady() || isMmReady(); }
  boolean isLpReady() { return lpReceiver != null; }
  boolean isMmReady() { return mmReceiver != null; }

  void enterProgrammerMode() {
    if (isLpReady()) enterLpProgrammerMode();
    if (isMmReady()) syncMidiMixLeds();
  }

  void sendLpCmd(byte... payload) {
    byte[] data = new byte[7 + payload.length + 1];
    data[0] = (byte)0xF0; data[1] = 0x00; data[2] = 0x20; data[3] = 0x29; data[4] = 0x02;
    data[5] = launchpadProductId;
    System.arraycopy(payload, 0, data, 6, payload.length);
    data[data.length - 1] = (byte)0xF7;
    sendLpSysex(data);
  }

  void enterLpProgrammerMode() {
    if (!isLpReady()) return;
    sendLpCmd((byte)0x0E, (byte)0x01);             // Programmer mode layout
    sendLpCmd((byte)0x00, (byte)0x7F);             // Select layout
    sendLpCmd((byte)0x08, (byte)0x7F);             // Max LED brightness
    sendLpCmd((byte)0x0A, (byte)0x00, (byte)0x01); // External LED feedback
    resetPadDirtyCaches();
    syncLpSideLeds();
  }

  void exitProgrammerMode() {
    sendLpCmd((byte)0x0E, (byte)0x00); // Live mode
    sendLpCmd((byte)0x10, (byte)0x00); // Standalone mode
    for (int cc : new int[]{89, 79, 39, 29, 19}) sendLpCc(1, cc, 0);
  }

  void syncLpSideLeds() {
    if (!isLpReady()) return;
    sendLpCc(1, 89, lpTopSidePressed ? 13 : 15);
    sendLpCc(1, 79, lpSecSidePressed ? 5 : 7);
    sendLpCc(1, 39, lpShowSlime ? 13 : 0);
    sendLpCc(1, 29, lpShowFood ? 37 : 0);
    sendLpCc(1, 19, lpShowEating ? 53 : 0);
  }

  Toggle getMuteToggle(int col) {
    Toggle[] t = {pauseToggle, audioToggle, fullScreenToggle, gridOverlayToggle, reverbToggle, bioModToggle, hwLinkToggle, lpUserModeToggle};
    return (col >= 0 && col < t.length) ? t[col] : null;
  }

  Toggle getSoloToggle(int col) {
    Toggle[] t = {lpShowSlimeToggle, lpShowFoodToggle, lpShowEatingToggle, lpRgbModeToggle};
    return (col >= 0 && col < t.length) ? t[col] : null;
  }

  void syncMidiMixLeds() {
    if (!isMmReady()) return;
    for (int col = 0; col < 8; col++) {
      Toggle mt = getMuteToggle(col);
      if (mt != null) sendMmPadColor(1 + col * 3, mt.state ? 127 : 0);
      Toggle st = getSoloToggle(col);
      if (st != null) sendMmPadColor(2 + col * 3, st.state ? 127 : 0);
    }
  }

  void sendLpSysex(byte[] data) {
    Receiver r = lpReceiver;
    if (!ready && !isLpReady() || r == null) return;
    try {
      SysexMessage msg = new SysexMessage();
      try { msg.setMessage(data, data.length); }
      catch (Exception eInner) { msg.setMessage(0xF0, data, data.length); }
      r.send(msg, -1);
    } catch (Exception e) {
      System.err.println("SysEx Send Error (" + data.length + " bytes): " + e.getMessage());
    }
  }

  void sendLpPadNote(int channel, int note, int velocity) {
    Receiver r = lpReceiver;
    if (r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      msg.setMessage(ShortMessage.NOTE_ON, constrain(channel - 1, 0, 15), note, constrain(velocity, 0, 127));
      r.send(msg, -1);
    } catch (Exception e) {}
  }

  void sendLpCc(int channel, int cc, int value) {
    Receiver r = lpReceiver;
    if (r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      msg.setMessage(ShortMessage.CONTROL_CHANGE, constrain(channel - 1, 0, 15), cc, constrain(value, 0, 127));
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

  void sendPadNote(int channel, int note, int velocity) { sendLpPadNote(channel, note, velocity); }
  void sendPadColor(int note, int velocity)             { sendMmPadColor(note, velocity); }

  class LaunchpadReceiver implements Receiver {
    public void send(MidiMessage message, long timeStamp) {
      if (!midiEnabled) return;
      if (message instanceof ShortMessage) handleLaunchpad((ShortMessage) message);
    }
    public void close() {}
  }

  class MidimixReceiver implements Receiver {
    public void send(MidiMessage message, long timeStamp) {
      if (!midiEnabled) {
        if (message instanceof ShortMessage) {
          ShortMessage sm = (ShortMessage) message;
          if (sm.getCommand() == ShortMessage.NOTE_ON && sm.getData1() == 19 && sm.getData2() > 0) {
            handleMidimix(sm);
          }
        }
        return;
      }
      if (message instanceof ShortMessage) handleMidimix((ShortMessage) message);
    }
    public void close() {}
  }

  public void send(MidiMessage message, long timeStamp) {
    if (!midiEnabled) return;
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      handleLaunchpad(sm);
      handleMidimix(sm);
    }
  }

  private void handleLaunchpad(ShortMessage sm) {
    int cmd = sm.getCommand(), d1 = sm.getData1(), d2 = sm.getData2();
    if (cmd == ShortMessage.NOTE_ON && d2 > 0) handleLaunchpadNote(d1, d2);
    else if (cmd == ShortMessage.CONTROL_CHANGE) handleLaunchpadCc(d1, d2);
  }

  void handleLaunchpadNote(int note, int velocity) {
    int row = -1, col = -1;

    // Auto-detect Programmer vs User mode:
    if (note < 36 && note >= 11) lpUserMode = false;
    else if (note > 88 && note <= 99) lpUserMode = true;
    else if (note >= 36 && note <= 88) {
      int c10 = note % 10;
      if (c10 == 9 || c10 == 0) lpUserMode = true;
    }

    if (lpUserMode) {
      if (note >= 36 && note <= 99) {
        int[] cr = decodeLaunchpadUserNote(note);
        col = cr[0]; row = cr[1];
      }
    } else {
      int progRow = note / 10, progCol = note % 10;
      if (progRow >= 1 && progRow <= 8 && progCol >= 1 && progCol <= 8) {
        row = 8 - progRow; col = progCol - 1;
      }
    }

    if (row >= 0 && row < 8 && col >= 0 && col < 8) {
      float cellW = float(SIM_W) / GRID_DIM, cellH = float(SIM_H) / GRID_DIM;
      float x = col * cellW + random(8, cellW - 8);
      float y = row * cellH + random(8, cellH - 8);
      float r = random(8.0f, 24.0f);
      addFoodNodule(x, y, r, r * r * 2.0f);
      triggerPadRipple(col, row, x, y);
    }
  }

  void handleLaunchpadCc(int cc, int value) {
    if (value > 0) {
      if (cc == 89) {
        lpTopSidePressed = true;
        reinoculate();
        sendLpCc(1, 89, 13);
      } else if (cc == 79) {
        lpSecSidePressed = true;
        clearAllFood();
        sendLpCc(1, 79, 5);
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
      if (cc == 89) {
        lpTopSidePressed = false;
        sendLpCc(1, 89, 15);
      } else if (cc == 79) {
        lpSecSidePressed = false;
        sendLpCc(1, 79, 7);
      }
    }
  }

  private void handleMidimix(ShortMessage sm) {
    int cmd = sm.getCommand(), d1 = sm.getData1(), d2 = sm.getData2();
    if (cmd == ShortMessage.NOTE_ON && d2 > 0) handleMidimixButton(d1, true);
    else if (cmd == ShortMessage.NOTE_OFF || (cmd == ShortMessage.NOTE_ON && d2 == 0)) handleMidimixButton(d1, false);
    else if (cmd == ShortMessage.CONTROL_CHANGE) handleMidimixKnobOrFader(d1, d2 / 127.0f);
  }

  void setSliderIfPresent(Slider s, float val)   { if (s != null) s.setValue(val, true); }
  void setRadioIfPresent(RadioGroup rg, int idx) { if (rg != null) rg.setIndex(idx, false); }
  void setDropdownIfPresent(Dropdown d, int idx) { if (d != null) d.setIndex(idx, false); }
  void togglePadIfPresent(Toggle t, int note) {
    if (t != null) {
      t.set(!t.state, true);
      sendPadColor(note, t.state ? 127 : 0);
    }
  }

  void executeSoloModal(int col) {
    if (col == 4) {
      waveformIdx = (waveformIdx + 1) % 4;
      setRadioIfPresent(waveformRadio, waveformIdx);
    } else if (col == 5) {
      paletteIdx = (paletteIdx + 1) % 3;
      setRadioIfPresent(paletteRadio, paletteIdx);
      resetPadDirtyCaches();
    } else if (col == 6) {
      octaveShiftIdx = (octaveShiftIdx + 1) % 3;
      setRadioIfPresent(octaveRadio, octaveShiftIdx);
      retuneAllNodules();
    } else if (col == 7) {
      currentScaleIdx = (currentScaleIdx + 1) % 6;
      setDropdownIfPresent(scaleDropdown, currentScaleIdx);
      retuneAllNodules();
    }
  }

  void executeRecArmAction(int col) {
    switch (col) {
      case 0: scatterInitialFood(4); break;
      case 1: clearAllFood(); break;
      case 2: reinoculate(); break;
      case 3: rescanMidi(); break;
      case 4: reverbSeed = System.nanoTime(); triggerIrRegenerationAsync(); break;
      case 5: rescanAudioDevices(); break;
      case 6: scatterInitialFood(1); break;
      case 7: retuneAllNodules(); break;
    }
  }

  void handleMidimixButton(int note, boolean pressed) {
    if (note < 1 || note > 24) return;
    int col = (note - 1) / 3, row = (note - 1) % 3;

    if (pressed) {
      if (row == 0) {
        togglePadIfPresent(getMuteToggle(col), note);
      } else if (row == 1) {
        if (col < 4) togglePadIfPresent(getSoloToggle(col), note);
        else { executeSoloModal(col); sendPadColor(note, 127); }
      } else if (row == 2) {
        executeRecArmAction(col);
        sendPadColor(note, 127);
      }
    } else {
      if (row == 2 || (row == 1 && col >= 4)) {
        sendPadColor(note, 0);
      }
    }
  }

  FloatCallback[] ccHandlers;

  void bindSlider(Slider s, float min, float max, int... ccs) {
    FloatCallback h = v -> setSliderIfPresent(s, lerp(min, max, v));
    for (int cc : ccs) ccHandlers[cc] = h;
  }

  void bindReverbParam(Slider s, float min, float max, FloatCallback setter, int... ccs) {
    FloatCallback h = v -> {
      float val = lerp(min, max, v);
      setter.on(val);
      setSliderIfPresent(s, val);
    };
    for (int cc : ccs) ccHandlers[cc] = h;
  }

  void bindStepped(int maxIdx, IntCallback setter, int... ccs) {
    FloatCallback h = v -> setter.on(constrain(round(lerp(0f, maxIdx, v)), 0, maxIdx));
    for (int cc : ccs) ccHandlers[cc] = h;
  }

  void initCcHandlers() {
    ccHandlers = new FloatCallback[128];

    // Core continuous channel sliders & mirror rotary knobs
    bindSlider(filterSensSlider, 0.2f, 3.0f, 19, 50);
    bindSlider(filterQSlider, 0.5f, 18.0f, 23, 51);
    bindSlider(vcaSensSlider, 0.2f, 3.0f, 27, 52);
    bindSlider(simSpeedSlider, 0.1f, 30.0f, 62, 11, 60);

    // Reverb channel sliders & mirror rotary knobs
    bindReverbParam(reverbWetSlider, 0.0f, 1.0f, v -> { baseReverbWet = v; reverbWet = v; }, 31, 54);
    bindReverbParam(reverbDrySlider, 0.0f, 1.0f, v -> { baseReverbDry = v; reverbDry = v; }, 49, 55);
    bindReverbParam(reverbT60Slider, 0.5f, 8.0f, v -> { baseReverbT60 = v; reverbT60 = v; }, 53, 56);
    bindReverbParam(reverbDampSlider, 0.05f, 0.95f, v -> { baseReverbHighDamping = v; reverbHighDamping = v; }, 57, 58);
    bindReverbParam(reverbPreSlider, 0.005f, 0.060f, v -> { baseReverbPreDelay = v; reverbPreDelay = v; }, 61, 33, 59);

    // Rotary Knobs: Bioenergetics, Visuals & Audio Macros
    bindSlider(sensorDistSlider, 6.0f, 160.0f, 16);
    bindSlider(bmrSlider, 0.001f, 0.050f, 20);
    bindSlider(locoCostSlider, 0.002f, 0.080f, 24);
    bindSlider(binauralDepthSlider, 0.0f, 2.0f, 28);
    bindSlider(visualSharpnessSlider, 0.0f, 1.0f, 17);
    bindSlider(agentCountSlider, 1000f, 64000f, 21);
    bindSlider(visualBlurSlider, 0.0f, 8.0f, 25);
    bindSlider(lpRippleWidthSlider, 1.0f, 5.0f, 29);
    bindSlider(ledThresholdSlider, 20.0f, 1000.0f, 22);
    bindSlider(reverbBioModSlider, 0.0f, 4.0f, 26);

    // Stepped Modal Rotaries
    bindStepped(2, p -> { if (p != paletteIdx) { paletteIdx = p; setRadioIfPresent(paletteRadio, p); resetPadDirtyCaches(); } }, 46);
    bindStepped(5, s -> { if (s != currentScaleIdx) { currentScaleIdx = s; setDropdownIfPresent(scaleDropdown, s); retuneAllNodules(); } }, 47);
    bindStepped(2, o -> { if (o != octaveShiftIdx) { octaveShiftIdx = o; setRadioIfPresent(octaveRadio, o); retuneAllNodules(); } }, 18);
    bindStepped(3, w -> { if (w != waveformIdx) { waveformIdx = w; setRadioIfPresent(waveformRadio, w); } }, 30);
    bindStepped(11, k -> { if (k != keyRootIndex) { keyRootIndex = k; setDropdownIfPresent(rootKeyDropdown, k); retuneAllNodules(); } }, 48);
  }

  void handleMidimixKnobOrFader(int cc, float val) {
    if (ccHandlers == null) initCcHandlers();
    if (cc >= 0 && cc < ccHandlers.length && ccHandlers[cc] != null) {
      ccHandlers[cc].on(val);
    }
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
