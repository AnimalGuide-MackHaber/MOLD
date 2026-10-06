// =============================================================================
// Controls.pde - UI Construction, Callbacks, and Mouse/Keyboard Input Handlers
// =============================================================================

void buildUI() {
  ui = new UIPanel(sidebarX, sidebarY() + 52, sidebarW, sidebarY() + sidebarH - 4);

  // 1. Global Transport & Action Strip
  simSpeedSlider = new Slider("SIMULATION SPEED", 0.05f, 2.00f, 0.05f, simSpeed, 2, "x", v -> simSpeed = v);
  pauseToggle = new Toggle("PAUSE", "RESUME", isPaused, UI_RED, v -> isPaused = v);
  audioToggle = new Toggle("AUDIO: OFF", "AUDIO: ON", audioEnabled, UI_GREEN, v -> audioEnabled = v);
  scatterOatsBtn = new Button("Scatter Oats", UI_TEXT, () -> scatterInitialFood(4));
  clearFoodBtn = new Button("Clear Food", 0xFFF87171, () -> clearAllFood());
  reinoculateBtn = new Button("Re-Inoculate Mold (Keep Food)", UI_YELLOW, () -> reinoculate());
  fullScreenToggle = new Toggle("FULL SCREEN: OFF [F]", "FULL SCREEN: ON [ESC/F]", isFullScreen, UI_CYAN, v -> toggleFullScreen());
  
  ui.add(new Section("TRANSPORT", false,
    simSpeedSlider,
    new Row(pauseToggle, audioToggle),
    new Row(scatterOatsBtn, clearFoodBtn),
    reinoculateBtn,
    fullScreenToggle
  ));

  // 2. Hardware MIDI Integration (Launchpad / MIDImix)
  midiInDropdown = new Dropdown("MIDI INPUT PORT", midiHandler.inNames, midiHandler.inSel, i -> midiHandler.openInput(i));
  midiOutDropdown = new Dropdown("MIDI OUTPUT PORT", midiHandler.outNames, midiHandler.outSel, i -> midiHandler.openOutput(i));
  hwLinkToggle = new Toggle("ENABLE HARDWARE LINK", "HARDWARE LINK: ACTIVE", midiEnabled, UI_CYAN, v -> setMidiEnabled(v));
  rescanMidiBtn = new Button("Rescan MIDI Devices", UI_TEXT, () -> rescanMidi());
  
  ui.add(new Section("HARDWARE MIDI LINK", true,
    hwLinkToggle,
    midiInDropdown,
    midiOutDropdown,
    rescanMidiBtn
  ));

  // 3. Harmonizer & Scale Matrix
  gridOverlayToggle = new Toggle("SHOW 8x8 FREQ OVERLAY: OFF", "SHOW 8x8 FREQ OVERLAY: ON", showGridOverlay, UI_YELLOW, v -> showGridOverlay = v);
  ui.add(new Section("HARMONIZER & SCALE MATRIX", false,
    new Dropdown("ROOT KEY", NOTE_NAMES, keyRootIndex, i -> { keyRootIndex = i; retuneAllNodules(); }),
    new Dropdown("CONSONANT SCALE", SCALE_NAMES, currentScaleIdx, i -> { currentScaleIdx = i; retuneAllNodules(); }),
    new RadioGroup("OSCILLATOR WAVEFORM", WAVE_NAMES, waveformIdx, UI_CYAN, i -> waveformIdx = i),
    gridOverlayToggle
  ));

  // 4. Dynamic LPF & Adjacent VCA
  filterSensSlider = new Slider("FILTER CUTOFF SENSITIVITY", 0.2f, 3.0f, 0.1f, filterSens, 1, "x", v -> filterSens = v);
  filterQSlider = new Slider("FILTER RESONANCE (Q)", 0.5f, 18.0f, 0.5f, filterQ, 1, "", v -> filterQ = v);
  vcaSensSlider = new Slider("ADJACENT MASS VCA GAIN", 0.2f, 3.0f, 0.1f, vcaSensitivity, 1, "x", v -> vcaSensitivity = v);
  
  ui.add(new Section("DYNAMIC LPF & ADJACENT VCA", false,
    filterSensSlider,
    filterQSlider,
    vcaSensSlider
  ));

  // 5. Velvet Noise Algorithmic Convolver Reverb
  reverbWetSlider = new Slider("REVERB WET MIX", 0.0f, 1.0f, 0.02f, reverbWet, 2, "", v -> reverbWet = v);
  reverbDrySlider = new Slider("REVERB DRY MIX", 0.0f, 1.0f, 0.02f, reverbDry, 2, "", v -> reverbDry = v);
  reverbT60Slider = new Slider("DECAY TIME (T60)", 0.5f, 8.0f, 0.1f, reverbT60, 1, "s", v -> { reverbT60 = v; triggerIrRegenerationAsync(); });
  reverbDampSlider = new Slider("HIGH DAMPING (ALPHA)", 0.05f, 0.95f, 0.05f, reverbHighDamping, 2, "", v -> { reverbHighDamping = v; triggerIrRegenerationAsync(); });
  reverbPreSlider = new Slider("PRE-DELAY", 0.005f, 0.060f, 0.005f, reverbPreDelay, 3, "s", v -> { reverbPreDelay = v; triggerIrRegenerationAsync(); });
  reverbToggle = new Toggle("REVERB: OFF", "REVERB: ON", reverbEnabled, UI_GREEN, v -> reverbEnabled = v);
  bioModToggle = new Toggle("BIO-MOD: OFF", "BIO-MOD: ON", autoModulateReverb, UI_CYAN, v -> autoModulateReverb = v);
  regenIrBtn = new Button("Regenerate IR Seed", UI_YELLOW, () -> {
    reverbSeed = System.nanoTime();
    triggerIrRegenerationAsync();
  });

  ui.add(new Section("VELVET CONVOLVER REVERB", false,
    new Row(reverbToggle, bioModToggle),
    reverbWetSlider,
    reverbDrySlider,
    reverbT60Slider,
    reverbDampSlider,
    reverbPreSlider,
    regenIrBtn
  ));

  // 6. Bioenergetics & Tendril Reach
  sensorDistSlider = new Slider("TENDRIL REACH (SENSOR DIST)", 6.0f, 45.0f, 1.0f, sensorDist, 0, "px", v -> sensorDist = v);
  bmrSlider = new Slider("BASAL METABOLIC RATE (BMR)", 0.001f, 0.050f, 0.001f, bmr, 3, "", v -> bmr = v);
  locoCostSlider = new Slider("EXPLORATION LOCO COST", 0.002f, 0.080f, 0.001f, locomotionCost, 3, "", v -> locomotionCost = v);
  
  ui.add(new Section("BIOENERGETICS & TENDRIL REACH", true,
    sensorDistSlider,
    bmrSlider,
    locoCostSlider
  ));

  // 7. Color Palette & Visuals
  ui.add(new Section("COLOR PALETTE & VISUALS", false,
    new RadioGroup("VISUAL THEME", PALETTE_NAMES, paletteIdx, UI_YELLOW, i -> paletteIdx = i)
  ));

  ui.layout();
}

void setMidiEnabled(boolean v) {
  midiEnabled = v;
  if (v) midiHandler.enterProgrammerMode();
  else midiHandler.exitProgrammerMode();
}

void rescanMidi() {
  midiHandler.scanDevices();
  midiInDropdown.setOptions(midiHandler.inNames, midiHandler.inSel);
  midiOutDropdown.setOptions(midiHandler.outNames, midiHandler.outSel);
}

void clearAllFood() {
  // Removing nodules from the list silences their voices on the next audio buffer
  foodNodes.clear();
}

// Wipe the colony + trail field and re-seed the starting blob; food nodules are kept as-is
void reinoculate() {
  speedAccumulator = 0.0f;
  prevColonyEnergy = 0;
  for (int i = 0; i < cellBiomass.length; i++) cellBiomass[i] = 0;
  for (FoodNodule fn : foodNodes) {
    fn.grazingBuffer = 0.0f;
    fn.isBeingEaten = false; // VCA glides to 0 until the new colony reaches it
  }
  lastMitosisBiomassThreshold = 8000.0f;
  reverbSeed = System.nanoTime();
  triggerIrRegenerationAsync();
  seedCentralInoculate(); // resets trailMap/nextTrailMap and spawns INITIAL_AGENTS at center
}

// Handling mouse interaction for canvas and GUI
void mousePressed() {
  if (isFullScreen) {
    // Check if exit full-screen banner clicked
    if (mouseX >= width - 150 && mouseX <= width - 12 && mouseY >= 12 && mouseY <= 36) {
      toggleFullScreen();
      return;
    }
  } else {
    if (ui.press(mouseX, mouseY)) return;
  }

  // Canvas click to drop oat nodule
  if (mouseX >= canvasX && mouseX <= canvasX + canvasS && mouseY >= canvasY && mouseY <= canvasY + canvasS) {
    float simX = ((mouseX - canvasX) / (float) canvasS) * SIM_W;
    float simY = ((mouseY - canvasY) / (float) canvasS) * SIM_H;
    addFoodNodule(simX, simY, 16.0f, 500.0f);
  }
}

void mouseDragged() {
  if (!isFullScreen) {
    ui.drag(mouseX, mouseY);
  }
}

void mouseReleased() {
  if (!isFullScreen) {
    ui.release();
  }
}

// Keyboard shortcuts (Full-Screen toggle via F or ESC)
void keyPressed() {
  if (key == 'f' || key == 'F') {
    toggleFullScreen();
  } else if (key == 27) { // ESC key
    if (isFullScreen) {
      key = 0; // Prevent sketch from abruptly terminating on ESC
      toggleFullScreen();
    }
  }
}
