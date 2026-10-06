// =============================================================================
// Midi.pde - Hardware MIDI Controller Integration (Launchpad Mini & Akai MIDImix)
// =============================================================================

// Flushing Launchpad RGB LEDs via MIDI note velocity
void flushLaunchpadLeds() {
  if (!midiEnabled || !midiHandler.isReady()) return;
  // If output is specifically a MIDImix, don't blast 64 Launchpad pad notes
  if (midiHandler.outputIsMidimix) return;

  long now = millis();
  if (now - lastMidiLedUpdate < 45) return;
  lastMidiLedUpdate = now;

  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      int idx = r * 8 + c;
      int note = (8 - r) * 10 + (c + 1);

      FoodNodule cellFood = null;
      for (FoodNodule fn : foodNodes) {
        if (fn.gridCol == c && fn.gridRow == r) {
          cellFood = fn;
          break;
        }
      }

      int colorVel = 0;
      if (cellFood != null && cellFood.nutrients > 0) {
        float ratio = cellFood.nutrients / cellFood.initialCapacity;
        
        // Food color transitions from Red (full) to Yellow (empty), flashes White if not eaten
        if (cellFood.consumptionActivity > 0.05f) {
          if (ratio > 0.65f) colorVel = 5;       // Red
          else if (ratio > 0.35f) colorVel = 9;  // Orange
          else colorVel = 13;                    // Yellow
        } else {
          colorVel = 3;                          // White (idle)
        }
      } else {
        float mass = cellBiomass[idx];
        if (mass > 450.0f) colorVel = 13;      // Bright Yellow
        else if (mass > 200.0f) colorVel = 15; // Dim Yellow
        else if (mass > 80.0f) colorVel = 62;  // Warm Ochre
        else if (mass > 25.0f) colorVel = 84;  // Faint Amber
        else colorVel = 0;                     // Off
      }

      if (padDirtyStates[idx] != (byte) colorVel) {
        padDirtyStates[idx] = (byte) colorVel;
        midiHandler.sendPadColor(note, colorVel);
      }
    }
  }
}

class MidiHandler implements Receiver {
  MidiDevice inputDevice;
  MidiDevice outputDevice;
  Transmitter inTransmitter;
  volatile Receiver outReceiver;
  volatile boolean ready = false;
  boolean inputIsMidimix = false;
  boolean outputIsMidimix = false;

  // Dropdown models: index 0 is "(none)", device index = sel - 1
  ArrayList<MidiDevice.Info> inInfos = new ArrayList<MidiDevice.Info>();
  ArrayList<MidiDevice.Info> outInfos = new ArrayList<MidiDevice.Info>();
  String[] inNames = {"(none)"};
  String[] outNames = {"(none)"};
  int inSel = 0;
  int outSel = 0;

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
    inSel = (inputDevice != null) ? inInfos.indexOf(inputDevice.getDeviceInfo()) + 1 : 0;
    outSel = (outputDevice != null) ? outInfos.indexOf(outputDevice.getDeviceInfo()) + 1 : 0;
  }

  String[] buildNames(ArrayList<MidiDevice.Info> infos) {
    String[] names = new String[infos.size() + 1];
    names[0] = "(none)";
    for (int i = 0; i < infos.size(); i++) names[i + 1] = infos.get(i).getName();
    return names;
  }

  // Prefer the MIDImix or Launchpad port
  int scoreMidiDevice(MidiDevice.Info info) {
    String n = (info.getName() + " " + info.getDescription()).toLowerCase();
    if (n.contains("midimix")) return 10;
    if (!(n.contains("launchpad") || n.contains("lpmk3") || n.contains("lpmini"))) return 0;
    int s = 2;
    if (n.contains("midi")) s += 1;
    if (n.contains("daw")) s -= 1;
    return s;
  }

  int bestMidiDevice(ArrayList<MidiDevice.Info> infos) {
    int best = -1, bestScore = 0;
    for (int i = 0; i < infos.size(); i++) {
      int s = scoreMidiDevice(infos.get(i));
      if (s > bestScore) { bestScore = s; best = i; }
    }
    return best + 1; // 0 = none
  }

  void initDevices() {
    scanDevices();
    openInput(bestMidiDevice(inInfos));
    openOutput(bestMidiDevice(outInfos));
  }

  void openInput(int sel) {
    try {
      if (inTransmitter != null) inTransmitter.close();
      if (inputDevice != null) inputDevice.close();
    } catch (Exception e) {}
    inTransmitter = null;
    inputDevice = null;
    inSel = 0;
    inputIsMidimix = false;
    if (sel <= 0 || sel > inInfos.size()) return;
    try {
      MidiDevice.Info info = inInfos.get(sel - 1);
      inputDevice = MidiSystem.getMidiDevice(info);
      inputDevice.open();
      inTransmitter = inputDevice.getTransmitter();
      inTransmitter.setReceiver(this);
      inSel = sel;
      inputIsMidimix = (info.getName() + " " + info.getDescription()).toLowerCase().contains("midimix");
    } catch (Exception e) {
      println("MIDI Input Open Err: " + e.getMessage());
      inputDevice = null;
    }
  }

  void openOutput(int sel) {
    boolean linked = midiEnabled && ready;
    if (linked) exitProgrammerMode();
    ready = false;
    try {
      if (outReceiver != null) outReceiver.close();
      if (outputDevice != null) outputDevice.close();
    } catch (Exception e) {}
    outReceiver = null;
    outputDevice = null;
    outSel = 0;
    outputIsMidimix = false;
    if (sel > 0 && sel <= outInfos.size()) {
      try {
        MidiDevice.Info info = outInfos.get(sel - 1);
        outputDevice = MidiSystem.getMidiDevice(info);
        outputDevice.open();
        outReceiver = outputDevice.getReceiver();
        outSel = sel;
        outputIsMidimix = (info.getName() + " " + info.getDescription()).toLowerCase().contains("midimix");
      } catch (Exception e) {
        println("MIDI Output Open Err: " + e.getMessage());
        outputDevice = null;
      }
    }
    ready = (outReceiver != null);
    if (midiEnabled) enterProgrammerMode();
  }

  boolean isReady() {
    return ready;
  }

  void enterProgrammerMode() {
    if (!ready || outReceiver == null) return;
    if (!outputIsMidimix) {
      try {
        byte[] sysex = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, (byte)0xF7};
        SysexMessage msg = new SysexMessage(sysex, sysex.length);
        outReceiver.send(msg, -1);
        for (int i = 0; i < 64; i++) padDirtyStates[i] = (byte) 255;
      } catch (Exception e) {
        println("SysEx Send Err: " + e.getMessage());
      }
    } else {
      syncMidiMixLeds();
    }
  }

  void syncMidiMixLeds() {
    if (pauseToggle != null) sendPadColor(1, pauseToggle.state ? 127 : 0);
    if (audioToggle != null) sendPadColor(4, audioToggle.state ? 127 : 0);
    if (fullScreenToggle != null) sendPadColor(7, fullScreenToggle.state ? 127 : 0);
    if (gridOverlayToggle != null) sendPadColor(10, gridOverlayToggle.state ? 127 : 0);
    if (reverbToggle != null) sendPadColor(13, reverbToggle.state ? 127 : 0);
    if (bioModToggle != null) sendPadColor(16, bioModToggle.state ? 127 : 0);
  }

  void exitProgrammerMode() {
    if (!ready || outReceiver == null) return;
    if (!outputIsMidimix) {
      try {
        byte[] sysex = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00, (byte)0xF7};
        SysexMessage msg = new SysexMessage(sysex, sysex.length);
        outReceiver.send(msg, -1);
      } catch (Exception e) {}
    }
  }

  void sendPadColor(int note, int velocity) {
    Receiver r = outReceiver;
    if (!ready || r == null) return;
    try {
      ShortMessage msg = new ShortMessage();
      msg.setMessage(ShortMessage.NOTE_ON, 0, note, velocity);
      r.send(msg, -1);
    } catch (Exception e) {}
  }

  public void send(MidiMessage message, long timeStamp) {
    if (!midiEnabled) return;
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      if (inputIsMidimix) {
        handleMidimix(sm);
      } else {
        handleLaunchpad(sm);
      }
    }
  }

  private void handleLaunchpad(ShortMessage sm) {
    if (sm.getCommand() == ShortMessage.NOTE_ON && sm.getData2() > 0) {
      int note = sm.getData1();
      int r10 = note / 10;
      int c10 = note % 10;
      if (r10 >= 1 && r10 <= 8 && c10 >= 1 && c10 <= 8) {
        int row = 8 - r10;
        int col = c10 - 1;
        float cellW = float(SIM_W) / GRID_DIM;
        float cellH = float(SIM_H) / GRID_DIM;
        float x = col * cellW + random(8, cellW - 8);
        float y = row * cellH + random(8, cellH - 8);
        addFoodNodule(x, y, 16.0f, 500.0f);
      }
    }
  }

  private void handleMidimix(ShortMessage sm) {
    int cmd = sm.getCommand();
    int d1 = sm.getData1();
    int d2 = sm.getData2();

    if (cmd == ShortMessage.NOTE_ON && d2 > 0) {
      // Toggles (Mute Row 1-6)
      if (d1 == 1) { if (pauseToggle != null) { pauseToggle.set(!pauseToggle.state, true); sendPadColor(1, pauseToggle.state ? 127 : 0); } }
      else if (d1 == 4) { if (audioToggle != null) { audioToggle.set(!audioToggle.state, true); sendPadColor(4, audioToggle.state ? 127 : 0); } }
      else if (d1 == 7) { if (fullScreenToggle != null) { fullScreenToggle.set(!fullScreenToggle.state, true); sendPadColor(7, fullScreenToggle.state ? 127 : 0); } }
      else if (d1 == 10) { if (gridOverlayToggle != null) { gridOverlayToggle.set(!gridOverlayToggle.state, true); sendPadColor(10, gridOverlayToggle.state ? 127 : 0); } }
      else if (d1 == 13) { if (reverbToggle != null) { reverbToggle.set(!reverbToggle.state, true); sendPadColor(13, reverbToggle.state ? 127 : 0); } }
      else if (d1 == 16) { if (bioModToggle != null) { bioModToggle.set(!bioModToggle.state, true); sendPadColor(16, bioModToggle.state ? 127 : 0); } }
      
      // Actions (Rec Arm Row 1-5)
      else if (d1 == 3) { scatterInitialFood(4); sendPadColor(3, 127); }
      else if (d1 == 6) { clearAllFood(); sendPadColor(6, 127); }
      else if (d1 == 9) { reinoculate(); sendPadColor(9, 127); }
      else if (d1 == 12) { rescanMidi(); sendPadColor(12, 127); }
      else if (d1 == 15) { reverbSeed = System.nanoTime(); triggerIrRegenerationAsync(); sendPadColor(15, 127); }
    }
    else if (cmd == ShortMessage.NOTE_OFF || (cmd == ShortMessage.NOTE_ON && d2 == 0)) {
      // Turn off momentary LEDs on button release
      if (d1 == 3 || d1 == 6 || d1 == 9 || d1 == 12 || d1 == 15) {
        sendPadColor(d1, 0);
      }
    }
    else if (cmd == ShortMessage.CONTROL_CHANGE) {
      float val = d2 / 127.0f;
      
      // Faders 1-8 -> Audio Controls
      if (d1 == 19) { if(filterSensSlider!=null) filterSensSlider.setValue(lerp(0.2f, 3.0f, val), true); }
      else if (d1 == 23) { if(filterQSlider!=null) filterQSlider.setValue(lerp(0.5f, 18.0f, val), true); }
      else if (d1 == 27) { if(vcaSensSlider!=null) vcaSensSlider.setValue(lerp(0.2f, 3.0f, val), true); }
      else if (d1 == 28) { if(reverbWetSlider!=null) reverbWetSlider.setValue(lerp(0.0f, 1.0f, val), true); }
      else if (d1 == 29) { if(reverbDrySlider!=null) reverbDrySlider.setValue(lerp(0.0f, 1.0f, val), true); }
      else if (d1 == 30) { if(reverbT60Slider!=null) reverbT60Slider.setValue(lerp(0.5f, 8.0f, val), true); }
      else if (d1 == 31) { if(reverbDampSlider!=null) reverbDampSlider.setValue(lerp(0.05f, 0.95f, val), true); }
      else if (d1 == 33) { if(reverbPreSlider!=null) reverbPreSlider.setValue(lerp(0.005f, 0.060f, val), true); }
      
      // Master Fader -> Simulation Speed
      else if (d1 == 11) { if(simSpeedSlider!=null) simSpeedSlider.setValue(lerp(0.05f, 2.00f, val), true); }
      
      // Track 1 Rotary Knobs -> Bioenergetics
      else if (d1 == 16) { if(sensorDistSlider!=null) sensorDistSlider.setValue(lerp(6.0f, 45.0f, val), true); }
      else if (d1 == 20) { if(bmrSlider!=null) bmrSlider.setValue(lerp(0.001f, 0.050f, val), true); }
      else if (d1 == 24) { if(locoCostSlider!=null) locoCostSlider.setValue(lerp(0.002f, 0.080f, val), true); }
    }
  }

  public void close() {}

  void shutdown() {
    exitProgrammerMode();
    openInput(0);
    try {
      if (outReceiver != null) outReceiver.close();
      if (outputDevice != null) outputDevice.close();
    } catch (Exception e) {}
    ready = false;
  }
}
