// =============================================================================
// Controls.pde - UI Construction, Callbacks, and Mouse/Keyboard Input Handlers
// =============================================================================

// ---- Reusable Widget Builders ----

Toggle createLedToggle(String label, boolean initial, int col, BoolCallback onToggle) {
  return new Toggle("LED " + label + ": OFF", "LED " + label + ": ON", initial, col, v -> {
    onToggle.on(v);
    if (midiHandler != null) {
      midiHandler.syncLpSideLeds();
      midiHandler.syncMidiMixLeds();
    }
  });
}

Toggle createLpModeToggle(String offLbl, String onLbl, boolean initial, BoolCallback onToggle) {
  return new Toggle(offLbl, onLbl, initial, UI_CYAN, v -> {
    onToggle.on(v);
    resetPadDirtyCaches();
    if (midiHandler != null) midiHandler.syncMidiMixLeds();
  });
}

Slider createReverbIrSlider(String label, float minV, float maxV, float step, float initVal, int decimals, String suffix, FloatCallback onVal) {
  return new Slider(label, minV, maxV, step, initVal, decimals, suffix, v -> {
    onVal.on(v);
    if (!autoModulateReverb || reverbBioModDepth <= 0.001f) triggerIrRegenerationAsync();
  });
}

void resetPadDirtyCaches() {
  if (midiHandler != null) {
    for (int i = 0; i < 64; i++) {
      padDirtyStates[i] = (byte) 255;
      padDirtyChannels[i] = -1;
      lastSentPadR[i] = (byte) -1;
      lastSentPadG[i] = (byte) -1;
      lastSentPadB[i] = (byte) -1;
    }
  }
}

// ---- UI Section Builders ----

Section buildTransportSection() {
  simSpeedSlider = new Slider("SIMULATION SPEED", 0.1f, 30.0f, 0.1f, simSpeed, 1, "x", v -> simSpeed = v);
  agentCountSlider = new Slider("TARGET AGENT COUNT", 1000f, 64000f, 100f, targetAgentCount, 0, "", v -> targetAgentCount = (int) v);
  pauseToggle = new Toggle("PAUSE", "RESUME", isPaused, UI_RED, v -> isPaused = v);
  audioToggle = new Toggle("AUDIO: OFF", "AUDIO: ON", audioEnabled, UI_GREEN, v -> audioEnabled = v);
  audioDeviceDropdown = new Dropdown("AUDIO INTERFACE", (audioEngine != null ? audioEngine.deviceNames : new String[]{"Default Audio Device"}), (audioEngine != null ? audioEngine.selectedDeviceIdx : 0), i -> {
    if (audioEngine != null) audioEngine.setAudioDevice(i);
  });
  rescanAudioBtn = new Button("Rescan Audio Devices", UI_TEXT, () -> rescanAudioDevices());
  scatterOatsBtn = new Button("Scatter Oats", UI_TEXT, () -> scatterInitialFood(4));
  clearFoodBtn = new Button("Clear Food", 0xFFF87171, () -> clearAllFood());
  reinoculateBtn = new Button("Re-Inoculate Mold (Keep Food)", UI_YELLOW, () -> reinoculate());
  fullScreenToggle = new Toggle("THEATER VIEW: OFF [F]", "THEATER VIEW: ON [F]", isFullScreen, UI_CYAN, v -> toggleFullScreen());

  return new Section("TRANSPORT", false,
    simSpeedSlider,
    agentCountSlider,
    new Row(pauseToggle, audioToggle),
    audioDeviceDropdown,
    rescanAudioBtn,
    new Row(scatterOatsBtn, clearFoodBtn),
    reinoculateBtn,
    fullScreenToggle
  );
}

Section buildMidiSection() {
  midiInDropdown = new Dropdown("LAUNCHPAD IN", midiHandler.inNames, midiHandler.lpInSel, i -> midiHandler.openLpInput(i));
  midiOutDropdown = new Dropdown("LAUNCHPAD OUT", midiHandler.outNames, midiHandler.lpOutSel, i -> midiHandler.openLpOutput(i));
  midimixInDropdown = new Dropdown("MIDIMIX IN", midiHandler.inNames, midiHandler.mmInSel, i -> midiHandler.openMmInput(i));
  midimixOutDropdown = new Dropdown("MIDIMIX OUT", midiHandler.outNames, midiHandler.mmOutSel, i -> midiHandler.openMmOutput(i));
  hwLinkToggle = new Toggle("ENABLE HARDWARE LINK", "HARDWARE LINK: ACTIVE", midiEnabled, UI_CYAN, v -> setMidiEnabled(v));
  ledThresholdSlider = new Slider("LAUNCHPAD LED SENSITIVITY", 20.0f, 1000.0f, 10.0f, ledMassThreshold, 0, "", v -> ledMassThreshold = v);
  lpRippleWidthSlider = new Slider("RIPPLE WIDTH (LAUNCHPAD)", 1.0f, 5.0f, 0.5f, lpRippleWidth, 1, " px", v -> lpRippleWidth = v);

  lpShowSlimeToggle = createLedToggle("MOLD", lpShowSlime, UI_YELLOW, v -> lpShowSlime = v);
  lpShowFoodToggle = createLedToggle("FOOD", lpShowFood, UI_CYAN, v -> lpShowFood = v);
  lpShowEatingToggle = createLedToggle("EAT", lpShowEating, UI_MAGENTA, v -> lpShowEating = v);

  lpRgbModeToggle = createLpModeToggle("LP LED: PALETTE", "LP LED: RGB GRADIENT", lpUseRgbSysex, v -> lpUseRgbSysex = v);
  lpUserModeToggle = createLpModeToggle("LP: PROGRAMMER", "LP: USER MODE", lpUserMode, v -> lpUserMode = v);
  rescanMidiBtn = new Button("Rescan MIDI Devices", UI_TEXT, () -> rescanMidi());

  return new Section("HARDWARE MIDI LINK (LAUNCHPAD & MIDIMIX)", true,
    hwLinkToggle,
    midiInDropdown,
    midiOutDropdown,
    midimixInDropdown,
    midimixOutDropdown,
    ledThresholdSlider,
    lpRippleWidthSlider,
    new Row(lpShowSlimeToggle, lpShowFoodToggle, lpShowEatingToggle),
    new Row(lpRgbModeToggle, lpUserModeToggle),
    rescanMidiBtn
  );
}

Section buildHarmonySection() {
  gridOverlayToggle = new Toggle("SHOW 8x8 FREQ OVERLAY: OFF", "SHOW 8x8 FREQ OVERLAY: ON", showGridOverlay, UI_YELLOW, v -> showGridOverlay = v);
  bellAcousticsToggle = new Toggle("VOICE: SYNTH OSC", "VOICE: BELL ACOUSTICS", bellAcousticsMode, UI_YELLOW, v -> bellAcousticsMode = v);
  bellQSlider = new Slider("BELL DECAY / RESONANCE (Q)", 500.0f, 5000.0f, 100.0f, bellQ, 0, "", v -> bellQ = v);
  bellSustainSlider = new Slider("FEEDING BELL SUSTAIN", 0.2f, 2.0f, 0.1f, bellSustainLevel, 1, "x", v -> bellSustainLevel = v);
  bellStrikeSlider = new Slider("CLAPPER STRIKE IMPACT", 0.0f, 2.0f, 0.1f, bellStrikeIntensity, 1, "x", v -> bellStrikeIntensity = v);

  rootKeyDropdown = new Dropdown("ROOT KEY", NOTE_NAMES, keyRootIndex, i -> { keyRootIndex = i; retuneAllNodules(); });
  scaleDropdown = new Dropdown("CONSONANT SCALE", SCALE_NAMES, currentScaleIdx, i -> { currentScaleIdx = i; retuneAllNodules(); });
  octaveRadio = new RadioGroup("OCTAVE SHIFT", OCTAVE_NAMES, octaveShiftIdx, UI_CYAN, i -> { octaveShiftIdx = i; retuneAllNodules(); });
  waveformRadio = new RadioGroup("SYNTH OSC WAVEFORM", WAVE_NAMES, waveformIdx, UI_CYAN, i -> waveformIdx = i);

  return new Section("HARMONIZER & BELL ACOUSTICS", true,
    rootKeyDropdown,
    scaleDropdown,
    octaveRadio,
    bellAcousticsToggle,
    bellQSlider,
    bellSustainSlider,
    bellStrikeSlider,
    waveformRadio,
    gridOverlayToggle
  );
}

Section buildFilterSection() {
  filterSensSlider = new Slider("FILTER CUTOFF SENSITIVITY", 0.2f, 3.0f, 0.1f, filterSens, 1, "x", v -> filterSens = v);
  filterQSlider = new Slider("FILTER RESONANCE (Q)", 0.5f, 18.0f, 0.5f, filterQ, 1, "", v -> filterQ = v);
  vcaSensSlider = new Slider("ADJACENT MASS VCA GAIN", 0.2f, 3.0f, 0.1f, vcaSensitivity, 1, "x", v -> vcaSensitivity = v);
  binauralDepthSlider = new Slider("3D BINAURAL INTENSITY", 0.0f, 2.0f, 0.1f, binauralDepth, 1, "x", v -> binauralDepth = v);

  return new Section("DYNAMIC LPF & 3D BINAURAL", true,
    filterSensSlider,
    filterQSlider,
    vcaSensSlider,
    binauralDepthSlider
  );
}

Section buildReverbSection() {
  reverbBioModSlider = new Slider("MOLD BIO-MOD DEPTH", 0.0f, 4.0f, 0.1f, reverbBioModDepth, 1, "x", v -> reverbBioModDepth = v);
  reverbWetSlider = new Slider("REVERB WET MIX", 0.0f, 1.0f, 0.02f, baseReverbWet, 2, "", v -> {
    baseReverbWet = v;
    if (!autoModulateReverb || reverbBioModDepth <= 0.001f) reverbWet = v;
  });
  reverbDrySlider = new Slider("REVERB DRY MIX", 0.0f, 1.0f, 0.02f, baseReverbDry, 2, "", v -> {
    baseReverbDry = v;
    if (!autoModulateReverb || reverbBioModDepth <= 0.001f) reverbDry = v;
  });
  reverbT60Slider = createReverbIrSlider("DECAY TIME (T60)", 0.5f, 8.0f, 0.1f, baseReverbT60, 1, "s", v -> { baseReverbT60 = v; reverbT60 = v; });
  reverbDampSlider = createReverbIrSlider("HIGH DAMPING (ALPHA)", 0.05f, 0.95f, 0.05f, baseReverbHighDamping, 2, "", v -> { baseReverbHighDamping = v; reverbHighDamping = v; });
  reverbPreSlider = createReverbIrSlider("PRE-DELAY", 0.005f, 0.060f, 0.005f, baseReverbPreDelay, 3, "s", v -> { baseReverbPreDelay = v; reverbPreDelay = v; });
  reverbToggle = new Toggle("REVERB: OFF", "REVERB: ON", reverbEnabled, UI_GREEN, v -> reverbEnabled = v);
  bioModToggle = new Toggle("BIO-MOD: OFF", "BIO-MOD: ON", autoModulateReverb, UI_CYAN, v -> {
    autoModulateReverb = v;
    if (!v) {
      reverbWet = baseReverbWet;
      reverbDry = baseReverbDry;
      reverbT60 = baseReverbT60;
      reverbHighDamping = baseReverbHighDamping;
      reverbPreDelay = baseReverbPreDelay;
      syncReverbUiSliders();
      triggerIrRegenerationAsync();
    }
  });
  regenIrBtn = new Button("Regenerate IR Seed", UI_YELLOW, () -> {
    reverbSeed = System.nanoTime();
    triggerIrRegenerationAsync();
  });

  return new Section("VELVET CONVOLVER REVERB", true,
    new Row(reverbToggle, bioModToggle),
    reverbBioModSlider,
    reverbWetSlider,
    reverbDrySlider,
    reverbT60Slider,
    reverbDampSlider,
    reverbPreSlider,
    regenIrBtn
  );
}

Section buildBioenergeticsSection() {
  sensorDistSlider = new Slider("TENDRIL REACH (SENSOR DIST)", 6.0f, 160.0f, 1.0f, sensorDist, 0, "px", v -> sensorDist = v);
  bmrSlider = new Slider("BASAL METABOLIC RATE (BMR)", 0.001f, 0.050f, 0.001f, bmr, 3, "", v -> bmr = v);
  locoCostSlider = new Slider("EXPLORATION LOCO COST", 0.002f, 0.080f, 0.001f, locomotionCost, 3, "", v -> locomotionCost = v);

  return new Section("BIOENERGETICS & TENDRIL REACH", true,
    sensorDistSlider,
    bmrSlider,
    locoCostSlider
  );
}

Section buildVisualsSection() {
  paletteRadio = new RadioGroup("VISUAL THEME", PALETTE_NAMES, paletteIdx, UI_YELLOW, i -> paletteIdx = i);
  gradientColorsSlider = new Slider("MASS GRADIENT COLORS", 1.0f, 8.0f, 1.0f, gradientColorCount, 0, "", v -> gradientColorCount = round(v));
  visualSharpnessSlider = new Slider("GRADIENT / SHARP (ON-OFF)", 0.0f, 1.0f, 0.01f, visualSharpness, 2, "", v -> visualSharpness = v);
  visualBlurSlider = new Slider("MOTION BLUR TRAILS", 0.0f, 8.0f, 0.1f, visualBlur, 1, "px", v -> visualBlur = v);

  return new Section("COLOR PALETTE & VISUALS", true,
    paletteRadio,
    gradientColorsSlider,
    visualSharpnessSlider,
    visualBlurSlider
  );
}

void buildUI() {
  ui = new UIPanel(sidebarX, sidebarY() + 52, sidebarW, sidebarY() + sidebarH - 4);

  ui.add(buildTransportSection());
  ui.add(buildMidiSection());
  ui.add(buildHarmonySection());
  ui.add(buildFilterSection());
  ui.add(buildReverbSection());
  ui.add(buildBioenergeticsSection());
  ui.add(buildVisualsSection());

  ui.layout();
}

void setMidiEnabled(boolean v) {
  midiEnabled = v;
  if (hwLinkToggle != null) hwLinkToggle.state = v;
  if (v) midiHandler.enterProgrammerMode();
  else midiHandler.exitProgrammerMode();
  if (midiHandler != null) midiHandler.syncMidiMixLeds();
}

void rescanMidi() {
  midiHandler.scanDevices();
  if (midiInDropdown != null) midiInDropdown.setOptions(midiHandler.inNames, midiHandler.lpInSel);
  if (midiOutDropdown != null) midiOutDropdown.setOptions(midiHandler.outNames, midiHandler.lpOutSel);
  if (midimixInDropdown != null) midimixInDropdown.setOptions(midiHandler.inNames, midiHandler.mmInSel);
  if (midimixOutDropdown != null) midimixOutDropdown.setOptions(midiHandler.outNames, midiHandler.mmOutSel);
}

void rescanAudioDevices() {
  if (audioEngine != null) {
    audioEngine.scanAudioDevices();
    if (audioDeviceDropdown != null) {
      audioDeviceDropdown.setOptions(audioEngine.deviceNames, audioEngine.selectedDeviceIdx);
    }
  }
}

void clearAllFood() {
  foodNodes.clear();
}

// Wipe colony + trail field and re-seed central blob; food nodules kept as-is
synchronized void reinoculate() {
  speedAccumulator = 0.0f;
  prevColonyEnergy = 0;
  for (int i = 0; i < cellBiomass.length; i++) cellBiomass[i] = 0;
  for (FoodNodule fn : foodNodes) {
    fn.grazingBuffer = 0.0f;
    fn.isBeingEaten = false;
    fn.wasBeingEaten = false;
  }
  lastMitosisBiomassThreshold = 8000.0f;
  reverbSeed = System.nanoTime();
  triggerIrRegenerationAsync();
  seedCentralInoculate();
  pendingReinoculateFboClear = true;
}

// Handle canvas click to place food nodule
void handleCanvasClick(float mx, float my) {
  if (mx >= canvasX && mx <= canvasX + canvasS && my >= canvasY && my <= canvasY + canvasS) {
    float simX = ((mx - canvasX) / (float) canvasS) * SIM_W;
    float simY = ((my - canvasY) / (float) canvasS) * SIM_H;
    float r = random(8.0f, 24.0f);
    addFoodNodule(simX, simY, r, r * r * 2.0f);
    int col = worldToGridCol(simX);
    int row = worldToGridRow(simY);
    triggerPadRipple(col, row, simX, simY);
  }
}

void mousePressed() {
  if (!isFullScreen && ui.press(mouseX, mouseY)) return;
  handleCanvasClick(mouseX, mouseY);
}

void mouseDragged() {
  if (!isFullScreen) ui.drag(mouseX, mouseY);
}

void mouseReleased() {
  if (!isFullScreen) ui.release();
}

// Keyboard shortcuts (Full-Screen toggle via F or ESC)
void keyPressed() {
  if (key == 'f' || key == 'F') {
    toggleFullScreen();
  } else if (key == 27) { // ESC key
    if (isFullScreen) {
      key = 0; // Prevent termination on ESC
      toggleFullScreen();
    }
  }
}
