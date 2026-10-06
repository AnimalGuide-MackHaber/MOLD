/* STREAMING_CHUNK:Configuring imports and core simulation dimensions */
import javax.sound.sampled.*;
import javax.sound.midi.*;
import java.util.ArrayList;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// =============================================================================
// PHYSARUM POLYCEPHALUM 8x8 HARMONIC SYNTHESIZER & LAUNCHPAD CONTROLLER
// Processing Sketch (.pde) - Self-Contained with Zero External Library Dependencies
// Real-time Sound Synthesis (javax.sound.sampled) & Hardware MIDI (javax.sound.midi)
// UI widgets live in the UI.pde tab (ControlP5 replacement).
// =============================================================================

final int SIM_W = 420;
final int SIM_H = 420;
final int GRID_DIM = 8;
final int MAX_AGENTS = 25000;
final int INITIAL_AGENTS = 8000;
final int MAX_NEWBORNS = 1000;

// Screen layout: Dynamic calculation based on window size and full-screen state
boolean isFullScreen = false;
float canvasX = 20;
float canvasY = 20;
float canvasS = 720;
float sidebarX = 760;
float sidebarW = 288;
float sidebarH = 720;
int lastWinW = 0;
int lastWinH = 0;

/* STREAMING_CHUNK:Defining bioenergetic and sonic parameters */
// Simulation Dynamics & Bioenergetics
float simSpeed = 0.40f;
float speedAccumulator = 0.0f;
volatile boolean isPaused = false;
float sensorDist = 16.0f;
float sensorAngle = 35.0f * (PI / 180.0f);
final float turnAngle = 22.0f * (PI / 180.0f);
final float trailDecay = 0.965f;
final float trailDiffuse = 0.45f;
final float depositAmount = 14.0f;
float bmr = 0.010f;
float locomotionCost = 0.018f;
final float mitosisThreshold = 75.0f;
final float assimilationYield = 8.0f;
final float grazingRate = 0.015f;
final float passiveDecayRate = 0.015f;

/* STREAMING_CHUNK:Declaring musical tuning matrices and scales */
int keyRootIndex = 9; // 0=C, 9=A
int baseOctave = 2;
int currentScaleIdx = 0;
volatile int waveformIdx = 0; // 0=triangle, 1=sine, 2=sawtooth, 3=square
float filterSens = 1.2f;
float filterQ = 4.5f;
float filterBaseHz = 80.0f;
float filterMaxHz = 3200.0f;
float vcaSensitivity = 1.0f;
float vcaGateThreshold = 120.0f;
boolean showGridOverlay = false;
int paletteIdx = 0; // 0=yellow, 1=mono, 2=cyan

final String[] NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
final String[] SCALE_NAMES = {"Major Pentatonic", "Minor Pentatonic", "Lydian Mode", "Dorian Mode", "Hirajoshi", "Just Intonation"};
final String[] WAVE_NAMES = {"TRI", "SINE", "SAW", "SQR"};
final String[] PALETTE_NAMES = {"YELLOW", "MONO", "CYAN"};
final int[][] SCALE_SEMITONES = {
  {0, 2, 4, 7, 9, 12, 14, 16},       // Major Pentatonic
  {0, 3, 5, 7, 10, 12, 15, 17},      // Minor Pentatonic
  {0, 2, 4, 6, 7, 9, 11, 12},        // Lydian
  {0, 2, 3, 5, 7, 9, 10, 12},        // Dorian
  {0, 2, 3, 7, 8, 12, 14, 15}        // Hirajoshi
};
final float[] JUST_RATIOS = {1.0f, 9.0f/8.0f, 5.0f/4.0f, 11.0f/8.0f, 3.0f/2.0f, 13.0f/8.0f, 7.0f/4.0f, 2.0f};

/* STREAMING_CHUNK:Allocating memory buffers for cellular slime mold */
float[] trailMap;
float[] nextTrailMap;
float[] agentX;
float[] agentY;
float[] agentHeading;
float[] agentEnergy;
int activeAgentCount = 0;

// Pre-allocated mitosis staging buffers (avoids per-step GC churn)
float[] newX = new float[MAX_NEWBORNS];
float[] newY = new float[MAX_NEWBORNS];
float[] newHeading = new float[MAX_NEWBORNS];
float[] newEnergy = new float[MAX_NEWBORNS];

float[] cellBiomass = new float[GRID_DIM * GRID_DIM];
HarmonicData[] cellHarmonics = new HarmonicData[GRID_DIM * GRID_DIM];
CopyOnWriteArrayList<FoodNodule> foodNodes = new CopyOnWriteArrayList<FoodNodule>();

PImage offscreenFrame;
float prevColonyEnergy = 0;

// Subsystems
AudioEngine audioEngine;
volatile boolean audioEnabled = false;

// Velvet-Noise Algorithmic Convolver Reverb
volatile boolean reverbEnabled = true;
volatile boolean autoModulateReverb = true;
volatile float reverbWet = 0.50f;
volatile float reverbDry = 0.80f;
volatile float reverbT60 = 3.5f;
volatile float reverbHighDamping = 0.45f;
volatile float reverbPreDelay = 0.015f;
long reverbSeed = 1337L;
float lastMitosisBiomassThreshold = 8000.0f;
ExecutorService irExecutor = Executors.newSingleThreadExecutor();

Slider simSpeedSlider;
Slider filterSensSlider;
Slider filterQSlider;
Slider vcaSensSlider;
Slider sensorDistSlider;
Slider bmrSlider;
Slider locoCostSlider;

Slider reverbWetSlider;
Slider reverbDrySlider;
Slider reverbT60Slider;
Slider reverbDampSlider;
Slider reverbPreSlider;

Toggle pauseToggle;
Toggle audioToggle;
Toggle fullScreenToggle;
Toggle hwLinkToggle;
Toggle gridOverlayToggle;
Toggle reverbToggle;
Toggle bioModToggle;

Button scatterOatsBtn;
Button clearFoodBtn;
Button reinoculateBtn;
Button rescanMidiBtn;
Button regenIrBtn;

MidiHandler midiHandler;
volatile boolean midiEnabled = false;
long lastMidiLedUpdate = 0;
byte[] padDirtyStates = new byte[64];

// UI
UIPanel ui;
Dropdown midiInDropdown;
Dropdown midiOutDropdown;

// Toggle full screen mode and recalculate view bounds
void toggleFullScreen() {
  isFullScreen = !isFullScreen;
  recalculateLayout();
}

void recalculateLayout() {
  if (isFullScreen) {
    // Fill the window with the simulation canvas while preserving 1:1 aspect ratio
    float margin = 16;
    float availW = width - margin * 2;
    float availH = height - margin * 2;
    canvasS = min(availW, availH);
    canvasX = (width - canvasS) / 2.0f;
    canvasY = (height - canvasS) / 2.0f;
    sidebarW = 288;
    sidebarX = width - sidebarW - 16;
    sidebarH = height - 32;
  } else {
    sidebarW = 288;
    float margin = 20;
    float gap = 20;
    float availW = width - sidebarW - margin * 2 - gap;
    float availH = height - margin * 2 - 20; // 20px bottom hint
    canvasS = max(200.0f, min(availW, availH));
    canvasX = margin;
    canvasY = margin;
    sidebarX = canvasX + canvasS + gap;
    sidebarH = canvasS;
  }
  if (ui != null) {
    ui.updateBounds(sidebarX, sidebarY() + 52, sidebarW, sidebarY() + sidebarH - 4);
  }
}

float sidebarY() {
  return isFullScreen ? 16 : canvasY;
}

/* STREAMING_CHUNK:Initializing Processing setup and graphics buffers */
void setup() {
  size(1060, 760);
  surface.setTitle("Physarum Polycephalum 8x8 Sonification Matrix");
  surface.setResizable(true);
  frameRate(60);
  noSmooth();

  offscreenFrame = createImage(SIM_W, SIM_H, ARGB);
  trailMap = new float[SIM_W * SIM_H];
  nextTrailMap = new float[SIM_W * SIM_H];
  agentX = new float[MAX_AGENTS];
  agentY = new float[MAX_AGENTS];
  agentHeading = new float[MAX_AGENTS];
  agentEnergy = new float[MAX_AGENTS];

  for (int i = 0; i < 64; i++) padDirtyStates[i] = (byte) 255;

  rebuildHarmonicCache();
  seedCentralInoculate();
  scatterInitialFood(5);

  audioEngine = new AudioEngine();
  audioEngine.start();

  midiHandler = new MidiHandler();
  midiHandler.initDevices();

  recalculateLayout();
  buildUI();
}

/* STREAMING_CHUNK:Building the control panel (spec sections 1-6) */
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

void triggerIrRegenerationAsync() {
  final float sr = 44100.0f;
  final float t60 = reverbT60;
  final float d0 = 2000.0f;
  final float dMax = 10000.0f;
  final float damp = reverbHighDamping;
  final float pre = reverbPreDelay;
  final long s = reverbSeed;

  irExecutor.submit(() -> {
    try {
      VelvetImpulseGenerator.StereoIR newIr = VelvetImpulseGenerator.generate(
        sr, t60, d0, dMax, damp, pre, s
      );
      if (audioEngine != null && audioEngine.convolver != null) {
        audioEngine.convolver.loadImpulseResponse(newIr.left, newIr.right);
      }
    } catch (Exception e) {
      println("Async IR Generation Error: " + e.getMessage());
    }
  });
}

/* STREAMING_CHUNK:Seeding initial central colony blob */
void seedCentralInoculate() {
  activeAgentCount = INITIAL_AGENTS;
  float cx = SIM_W * 0.5f;
  float cy = SIM_H * 0.5f;
  float radius = 24.0f;

  for (int i = 0; i < SIM_W * SIM_H; i++) {
    trailMap[i] = 0;
    nextTrailMap[i] = 0;
  }

  for (int i = 0; i < activeAgentCount; i++) {
    float angle = random(TWO_PI);
    float r = sqrt(random(1.0f)) * radius;
    agentX[i] = cx + cos(angle) * r;
    agentY[i] = cy + sin(angle) * r;
    agentHeading[i] = angle + random(-0.25f, 0.25f);
    agentEnergy[i] = 50.0f * random(0.8f, 1.2f);

    int idx = int(agentY[i]) * SIM_W + int(agentX[i]);
    if (idx >= 0 && idx < trailMap.length) {
      trailMap[idx] = min(255.0f, trailMap[idx] + 35.0f);
    }
  }
}

/* STREAMING_CHUNK:Scattering randomized initial food reserves */
void scatterInitialFood(int count) {
  for (int i = 0; i < count; i++) {
    float x = random(40, SIM_W - 40);
    float y = random(40, SIM_H - 40);
    addFoodNodule(x, y, 16.0f, 550.0f);
  }
}

/* STREAMING_CHUNK:Computing pitch and tuning per 8x8 grid cell */
HarmonicData getCellHarmonics(int col, int row) {
  int invertedRow = (GRID_DIM - 1) - row;
  int octaveShift = invertedRow / 2;
  int oct = baseOctave + octaveShift;
  float subOffset = (invertedRow % 2 == 1) ? 1.5f : 1.0f;

  float freq = 110.0f;
  String label = "";

  if (currentScaleIdx < 5) {
    int[] degrees = SCALE_SEMITONES[currentScaleIdx];
    int semitone = degrees[col % degrees.length];
    int totalSemitone = (oct * 12) + keyRootIndex + semitone;
    freq = 440.0f * pow(2.0f, (totalSemitone - 57) / 12.0f) * subOffset;
    label = NOTE_NAMES[(keyRootIndex + semitone) % 12] + oct;
  } else {
    float baseF = 55.0f * pow(2.0f, oct - 1) * pow(2.0f, keyRootIndex / 12.0f);
    freq = baseF * JUST_RATIOS[col % JUST_RATIOS.length] * subOffset;
    label = round(freq) + "Hz";
  }

  HarmonicData hd = new HarmonicData();
  hd.freq = freq;
  hd.label = label;
  hd.hz = round(freq);
  return hd;
}

class HarmonicData {
  float freq;
  String label;
  int hz;
}

// Precompute all 64 cell pitches (called on key/scale change only)
void rebuildHarmonicCache() {
  for (int r = 0; r < GRID_DIM; r++) {
    for (int c = 0; c < GRID_DIM; c++) {
      cellHarmonics[r * GRID_DIM + c] = getCellHarmonics(c, r);
    }
  }
}

// Root Key / Scale change: update target frequencies in place, never touch the audio thread
void retuneAllNodules() {
  rebuildHarmonicCache();
  for (FoodNodule fn : foodNodes) fn.applyHarmonics();
}

/* STREAMING_CHUNK:Implementing food nodule entity and voice state */
class FoodNodule {
  float x, y;
  int gridCol, gridRow;
  float initialCapacity;
  float nutrients;
  float maxRadius;
  float radius;
  volatile float frequency;
  String label;
  int hz;
  float grazingBuffer = 0.0f;
  boolean isBeingEaten = false;
  float consumptionActivity = 0.0f; // Smooth transition for visual feedback
  volatile float vcaGain = 0.0f;
  float lpfCutoff = 80.0f;
  BiquadFilter filter;
  float phase = 0.0f;

  FoodNodule(float px, float py, float r, float cap) {
    x = px;
    y = py;
    maxRadius = r;
    radius = r;
    initialCapacity = cap;
    nutrients = cap;
    gridCol = constrain(int((x / SIM_W) * GRID_DIM), 0, GRID_DIM - 1);
    gridRow = constrain(int((y / SIM_H) * GRID_DIM), 0, GRID_DIM - 1);

    applyHarmonics();
    filter = new BiquadFilter();
  }

  void applyHarmonics() {
    HarmonicData hd = cellHarmonics[gridRow * GRID_DIM + gridCol];
    frequency = hd.freq;
    label = hd.label;
    hz = hd.hz;
  }

  void updateAudioParameters(float adjacentMass) {
    float ratio = max(0.0f, nutrients / initialCapacity);
    radius = max(2.5f, maxRadius * pow(ratio, 0.65f));

    // Dynamic Filter Sweep: drops from 3200Hz down to 80Hz as nodule is consumed
    lpfCutoff = filterBaseHz + (filterMaxHz - filterBaseHz) * pow(ratio, 1.8f * filterSens);
    filter.setLowPass(lpfCutoff, filterQ, 44100.0f);

    // Moore Neighborhood VCA Modulation (8 adjacent cells)
    // 1.25 internal scale keeps the spec's 1.0x default equal to the original voicing
    float effectiveMass = max(0.0f, adjacentMass - vcaGateThreshold);
    float drive = (effectiveMass * vcaSensitivity * 1.25f) / 1000.0f;
    float targetVca = (isBeingEaten) ? (float) Math.tanh(drive) : 0.0f;
    vcaGain += (targetVca - vcaGain) * 0.15f;
    
    // Smooth consumption visual activity
    float targetActivity = isBeingEaten ? 1.0f : 0.0f;
    consumptionActivity += (targetActivity - consumptionActivity) * 0.12f;
  }
}

void addFoodNodule(float x, float y, float r, float cap) {
  FoodNodule fn = new FoodNodule(x, y, r, cap);
  foodNodes.add(fn);
}

/* STREAMING_CHUNK:Sampling chemoattractant trail with bilinear interpolation */
float sampleChemo(float px, float py) {
  float x = ((px % SIM_W) + SIM_W) % SIM_W;
  float y = ((py % SIM_H) + SIM_H) % SIM_H;

  int x0 = int(x) % SIM_W;
  int y0 = int(y) % SIM_H;
  float fx = x - int(x);
  float fy = y - int(y);

  int x1 = (x0 + 1) % SIM_W;
  int y1 = (y0 + 1) % SIM_H;

  int i00 = y0 * SIM_W + x0;
  int i10 = y0 * SIM_W + x1;
  int i01 = y1 * SIM_W + x0;
  int i11 = y1 * SIM_W + x1;

  float top = trailMap[i00] * (1.0f - fx) + trailMap[i10] * fx;
  float btm = trailMap[i01] * (1.0f - fx) + trailMap[i11] * fx;
  return top * (1.0f - fy) + btm * fy;
}

/* STREAMING_CHUNK:Executing bioenergetics, chemotaxis, and cellular division */
void stepBioenergetics() {
  float totalColonyEnergy = 0;
  int newbornCount = 0;

  for (int i = activeAgentCount - 1; i >= 0; i--) {
    float x = agentX[i];
    float y = agentY[i];
    float heading = agentHeading[i];
    float energy = agentEnergy[i];

    energy -= bmr;

    // 3-Sensor Chemotaxis Sampling
    float fx = x + cos(heading) * sensorDist;
    float fy = y + sin(heading) * sensorDist;
    float lx = x + cos(heading - sensorAngle) * sensorDist;
    float ly = y + sin(heading - sensorAngle) * sensorDist;
    float rx = x + cos(heading + sensorAngle) * sensorDist;
    float ry = y + sin(heading + sensorAngle) * sensorDist;

    float valF = sampleChemo(fx, fy);
    float valL = sampleChemo(lx, ly);
    float valR = sampleChemo(rx, ry);

    if (valF > valL && valF > valR) {
      heading += random(-0.04f, 0.04f);
    } else if (valL > valR) {
      heading -= turnAngle + random(-0.03f, 0.03f);
    } else if (valR > valL) {
      heading += turnAngle + random(-0.03f, 0.03f);
    } else {
      heading += random(-0.4f, 0.4f);
    }

    // Hunger-Driven Wandering Impulse
    if (energy < 28.0f) {
      heading += random(-0.35f, 0.35f);
    }

    // Locomotion Exploration Cost
    float localTrail = sampleChemo(x, y);
    float territoryCost = max(0.25f, 1.0f - (localTrail / 80.0f));
    energy -= locomotionCost * territoryCost;

    float nx = (x + cos(heading) + SIM_W) % SIM_W;
    float ny = (y + sin(heading) + SIM_H) % SIM_H;

    // Ingestion of Food Nodules
    for (FoodNodule fn : foodNodes) {
      float dx = nx - fn.x;
      float dy = ny - fn.y;
      if (dx * dx + dy * dy <= fn.radius * fn.radius) {
        fn.grazingBuffer += grazingRate;
        fn.isBeingEaten = true;
        energy += grazingRate * assimilationYield;
      }
    }

    // Starvation Necrosis
    if (energy <= 0.0f) {
      int lastIdx = activeAgentCount - 1;
      if (i != lastIdx) {
        agentX[i] = agentX[lastIdx];
        agentY[i] = agentY[lastIdx];
        agentHeading[i] = agentHeading[lastIdx];
        agentEnergy[i] = agentEnergy[lastIdx];
      }
      activeAgentCount--;
      continue;
    }

    // Mitosis Division
    if (energy >= mitosisThreshold && (activeAgentCount + newbornCount) < MAX_AGENTS && newbornCount < MAX_NEWBORNS - 10) {
      energy *= 0.48f;
      newX[newbornCount] = nx + random(-1.5f, 1.5f);
      newY[newbornCount] = ny + random(-1.5f, 1.5f);
      newHeading[newbornCount] = heading + random(-1.0f, 1.0f);
      newEnergy[newbornCount] = energy;
      newbornCount++;
    }

    agentX[i] = nx;
    agentY[i] = ny;
    agentHeading[i] = heading;
    agentEnergy[i] = energy;
    totalColonyEnergy += energy;

    int idx = (int(ny) % SIM_H) * SIM_W + (int(nx) % SIM_W);
    trailMap[idx] = min(255.0f, trailMap[idx] + depositAmount);
  }

  // Insert Newborn Agents
  for (int n = 0; n < newbornCount; n++) {
    int slot = activeAgentCount;
    if (slot < MAX_AGENTS) {
      agentX[slot] = (newX[n] + SIM_W) % SIM_W;
      agentY[slot] = (newY[n] + SIM_H) % SIM_H;
      agentHeading[slot] = newHeading[n];
      agentEnergy[slot] = newEnergy[n];
      activeAgentCount++;
    }
  }

  prevColonyEnergy = totalColonyEnergy;
}

/* STREAMING_CHUNK:Diffusing trail map and evaporating old paths */
void diffuseAndEvaporate() {
  // Inject Food Chemoattractant Core
  for (FoodNodule fn : foodNodes) {
    float r = fn.radius;
    float rSq = r * r;
    float strength = 4.0f * (fn.nutrients / fn.initialCapacity);
    int x0 = max(0, int(fn.x - r));
    int x1 = min(SIM_W - 1, int(fn.x + r));
    int y0 = max(0, int(fn.y - r));
    int y1 = min(SIM_H - 1, int(fn.y + r));

    for (int py = y0; py <= y1; py++) {
      int yOff = py * SIM_W;
      float dy = py - fn.y;
      for (int px = x0; px <= x1; px++) {
        float dx = px - fn.x;
        if (dx * dx + dy * dy <= rSq) {
          trailMap[yOff + px] = min(255.0f, trailMap[yOff + px] + strength * 9.0f);
        }
      }
    }
  }

  // 3x3 Box Blur Convolution + Decay
  float invDiff = 1.0f - trailDiffuse;
  for (int y = 0; y < SIM_H; y++) {
    int yTop = ((y - 1 + SIM_H) % SIM_H) * SIM_W;
    int yMid = y * SIM_W;
    int yBtm = ((y + 1) % SIM_H) * SIM_W;

    for (int x = 0; x < SIM_W; x++) {
      int xLeft = (x - 1 + SIM_W) % SIM_W;
      int xRight = (x + 1) % SIM_W;

      float sum = trailMap[yTop + xLeft] + trailMap[yTop + x] + trailMap[yTop + xRight] +
                  trailMap[yMid + xLeft] + trailMap[yMid + xRight] +
                  trailMap[yBtm + xLeft] + trailMap[yBtm + x] + trailMap[yBtm + xRight];

      float avg = sum * 0.125f;
      float center = trailMap[yMid + x];
      float result = (center * invDiff + avg * trailDiffuse) * trailDecay;
      nextTrailMap[yMid + x] = (result > 0.15f) ? result : 0.0f;
    }
  }

  float[] temp = trailMap;
  trailMap = nextTrailMap;
  nextTrailMap = temp;
}

/* STREAMING_CHUNK:Updating grid biomass distributions and voice parameters */
void updateGridBiomassAndFood() {
  for (int i = 0; i < 64; i++) cellBiomass[i] = 0;

  float cellW = float(SIM_W) / GRID_DIM;
  float cellH = float(SIM_H) / GRID_DIM;

  for (int i = 0; i < activeAgentCount; i++) {
    int c = constrain(int(agentX[i] / cellW), 0, GRID_DIM - 1);
    int r = constrain(int(agentY[i] / cellH), 0, GRID_DIM - 1);
    cellBiomass[r * GRID_DIM + c] += agentEnergy[i];
  }

  for (int i = foodNodes.size() - 1; i >= 0; i--) {
    FoodNodule fn = foodNodes.get(i);
    float loss = fn.grazingBuffer + (passiveDecayRate / 60.0f);
    fn.nutrients -= loss;
    fn.grazingBuffer = 0;

    // Moore Neighborhood Sum (8 adjacent cells)
    float adjacentMass = 0;
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dc == 0 && dr == 0) continue;
        int nc = fn.gridCol + dc;
        int nr = fn.gridRow + dr;
        if (nc >= 0 && nc < GRID_DIM && nr >= 0 && nr < GRID_DIM) {
          adjacentMass += cellBiomass[nr * GRID_DIM + nc];
        }
      }
    }

    fn.updateAudioParameters(adjacentMass);

    // Quench Depleted Nodule Attractant Core
    if (fn.nutrients <= 0.0f || fn.radius <= 2.5f) {
      int fx = int(fn.x);
      int fy = int(fn.y);
      int clearR = int(fn.maxRadius * 1.5f);
      for (int dy = -clearR; dy <= clearR; dy++) {
        for (int dx = -clearR; dx <= clearR; dx++) {
          if (dx * dx + dy * dy <= clearR * clearR) {
            int tx = ((fx + dx) % SIM_W + SIM_W) % SIM_W;
            int ty = ((fy + dy) % SIM_H + SIM_H) % SIM_H;
            trailMap[ty * SIM_W + tx] *= 0.25f;
          }
        }
      }
      foodNodes.remove(fn);
    }
  }
}

/* STREAMING_CHUNK:Rendering discrete non-glowing pixels to offscreen frame */
void renderCrispPixels() {
  offscreenFrame.loadPixels();
  int[] px = offscreenFrame.pixels;

  int cBg, cAtrophy, cMargin, cSheet, cArtery;
  if (paletteIdx == 0) { // Yellow
    cBg = color(6, 7, 10);
    cAtrophy = color(115, 65, 8);
    cMargin = color(161, 98, 7);
    cSheet = color(234, 179, 8);
    cArtery = color(254, 240, 138);
  } else if (paletteIdx == 1) { // Mono
    cBg = color(6, 7, 10);
    cAtrophy = color(45, 45, 52);
    cMargin = color(95, 95, 105);
    cSheet = color(175, 175, 185);
    cArtery = color(245, 245, 250);
  } else { // Cyan
    cBg = color(5, 8, 12);
    cAtrophy = color(4, 52, 75);
    cMargin = color(6, 120, 160);
    cSheet = color(34, 211, 238);
    cArtery = color(207, 250, 254);
  }

  for (int i = 0; i < trailMap.length; i++) {
    float val = trailMap[i];
    if (val < 0.8f) {
      px[i] = cBg;
    } else if (val < 4.0f) {
      px[i] = cAtrophy;
    } else if (val < 10.0f) {
      px[i] = cMargin;
    } else if (val < 30.0f) {
      px[i] = cSheet;
    } else {
      px[i] = cArtery;
    }
  }

  offscreenFrame.updatePixels();
}

/* STREAMING_CHUNK:Executing main draw loop and time-lapse integration */
void draw() {
  background(11, 12, 16);

  if (!isPaused) {
    speedAccumulator += simSpeed;
    while (speedAccumulator >= 1.0f) {
      stepBioenergetics();
      diffuseAndEvaporate();
      speedAccumulator -= 1.0f;
    }
    updateGridBiomassAndFood();
    updateReverbBioTelemetry();
  }

  renderCrispPixels();

  // Track window dimension changes (resizing window)
  if (width != lastWinW || height != lastWinH) {
    lastWinW = width;
    lastWinH = height;
    recalculateLayout();
  }

  // Draw Simulation Frame
  image(offscreenFrame, canvasX, canvasY, canvasS, canvasS);

  if (showGridOverlay) {
    drawGridOverlay(canvasX, canvasY, canvasS, canvasS);
  }

  drawFoodNodules(canvasX, canvasY, canvasS, canvasS);

  if (!isFullScreen) {
    fill(113, 113, 122);
    textSize(9);
    textAlign(LEFT, TOP);
    text("Click canvas: drop oat nodule  •  Launchpad pads 11-88: drop oats  •  Amber LEDs: food  •  Green/Cyan LEDs: biomass  •  [F]: Full Screen",
         canvasX, canvasY + canvasS + 4);

    drawSidebarGUI(sidebarX, sidebarY(), sidebarW, sidebarH);
  } else {
    // In full screen, show mini toggle button / hint in top-right corner
    fill(18, 20, 26, 210);
    stroke(UI_CYAN);
    rect(width - 150, 12, 138, 24, 4);
    fill(UI_CYAN);
    textAlign(CENTER, CENTER);
    textSize(10);
    text("EXIT FULL SCREEN [F]", width - 81, 23);

    fill(255, 255, 255, 120);
    textAlign(LEFT, BOTTOM);
    textSize(10);
    text("Click anywhere on canvas to drop oats  •  Press [F] or [ESC] to exit Full Screen", 16, height - 10);
  }

  flushLaunchpadLeds();
}

/* STREAMING_CHUNK:Bio-sonification modulation telemetry for velvet convolver */
void updateReverbBioTelemetry() {
  float totalBiomass = 0.0f;
  for (int i = 0; i < 64; i++) {
    totalBiomass += cellBiomass[i];
  }

  if (autoModulateReverb) {
    // 1. Total Colony Biomass -> Wet / Dry Balance: Wet = tanh(Biomass / 10000) * 0.8
    float wet = (float) Math.tanh(totalBiomass / 10000.0f) * 0.8f;
    float dry = 1.0f - (wet * 0.4f);
    reverbWet = constrain(wet, 0.0f, 1.0f);
    reverbDry = constrain(dry, 0.0f, 1.0f);

    // 2. Locomotion Exploration Cost -> High-Frequency Damping (alpha_max): alpha_max = 0.2 + 0.6 * (Cost / 0.1)
    float targetDamp = constrain(0.2f + 0.6f * (locomotionCost / 0.1f), 0.05f, 0.95f);

    // 3. Longest Active Artery (Tendril Reach) -> Pre-Delay: t_pre = 5ms + (Reach / 45px) * 40ms
    float targetPreDelay = constrain(0.005f + (sensorDist / 45.0f) * 0.040f, 0.005f, 0.060f);

    boolean needRegen = false;

    // 4. Mitosis Burst Event -> Impulse Seed Re-trigger on mass doubling
    if (totalBiomass >= lastMitosisBiomassThreshold * 2.0f && totalBiomass > 2000.0f) {
      reverbSeed = System.nanoTime() ^ (long) totalBiomass;
      lastMitosisBiomassThreshold = totalBiomass;
      needRegen = true;
    }

    if (Math.abs(reverbHighDamping - targetDamp) > 0.08f) {
      reverbHighDamping = targetDamp;
      needRegen = true;
    }
    if (Math.abs(reverbPreDelay - targetPreDelay) > 0.010f) {
      reverbPreDelay = targetPreDelay;
      needRegen = true;
    }

    if (needRegen) {
      triggerIrRegenerationAsync();
    }

    if (reverbWetSlider != null) reverbWetSlider.setValue(reverbWet, false);
    if (reverbDrySlider != null) reverbDrySlider.setValue(reverbDry, false);
    if (reverbDampSlider != null) reverbDampSlider.setValue(reverbHighDamping, false);
    if (reverbPreSlider != null) reverbPreSlider.setValue(reverbPreDelay, false);
  }
}

/* STREAMING_CHUNK:Drawing harmonic pitch overlay over 8x8 grid */
void drawGridOverlay(float ox, float oy, float w, float h) {
  float cw = w / GRID_DIM;
  float ch = h / GRID_DIM;

  stroke(255, 255, 255, 30);
  strokeWeight(1);
  for (int c = 1; c < GRID_DIM; c++) line(ox + c * cw, oy, ox + c * cw, oy + h);
  for (int r = 1; r < GRID_DIM; r++) line(ox, oy + r * ch, ox + w, oy + r * ch);

  // Highlight cells that currently hold a sounding nodule
  noStroke();
  for (FoodNodule fn : foodNodes) {
    float activity = constrain(fn.vcaGain, 0.0f, 1.0f);
    color cYellow = color(234, 179, 8);
    color cRed    = color(227, 66, 52);
    fill(lerpColor(cYellow, cRed, activity), 22 + (18 * activity));
    rect(ox + fn.gridCol * cw, oy + fn.gridRow * ch, cw, ch);
  }

  textAlign(CENTER, CENTER);
  textSize(10);
  for (int r = 0; r < GRID_DIM; r++) {
    for (int c = 0; c < GRID_DIM; c++) {
      HarmonicData hd = cellHarmonics[r * GRID_DIM + c];
      float cx = ox + (c + 0.5f) * cw;
      float cy = oy + (r + 0.5f) * ch;
      fill(255, 255, 255, 55);
      text(hd.hz + "Hz", cx, cy - 6);
      fill(255, 255, 255, 35);
      text(hd.label, cx, cy + 7);
    }
  }
}

/* STREAMING_CHUNK:Drawing food nodules with shrinking cores and labels */
void drawFoodNodules(float ox, float oy, float w, float h) {
  float scaleX = w / SIM_W;
  float scaleY = h / SIM_H;

  for (FoodNodule fn : foodNodes) {
    float cx = ox + fn.x * scaleX;
    float cy = oy + fn.y * scaleY;
    float rCur = fn.radius * scaleX;
    float rMax = fn.maxRadius * scaleX;

    // Calculate ratio of food left
    float ratio = constrain(fn.nutrients / fn.initialCapacity, 0.0f, 1.0f);
    int pct = max(0, round(ratio * 100));

    // Zorn palette colors
    color cYellow = color(234, 179, 8); // Yellow Ochre
    color cRed    = color(227, 66, 52); // Vermilion
    color cWhite  = color(245, 245, 240); // Flake White
    
    // When being eaten: Lerp from Red (1.0 ratio, full) to Yellow (0.0 ratio, empty)
    color cConsumed = lerpColor(cYellow, cRed, ratio);
    
    // Final color: Lerp from White (not eaten) to cConsumed (being eaten) based on smooth activity
    color finalColor = lerpColor(cWhite, cConsumed, fn.consumptionActivity);

    noFill();
    stroke(90, 90, 100);
    strokeWeight(1);
    ellipse(cx, cy, rMax * 2, rMax * 2);

    if (fn.consumptionActivity > 0.01f) {
      stroke(cConsumed, 160 * fn.consumptionActivity);
      strokeWeight(2);
      float pulseRadius = rCur + 4 + (2.0f * fn.consumptionActivity);
      ellipse(cx, cy, pulseRadius * 2, pulseRadius * 2);
      strokeWeight(1);
    }

    fill(finalColor);
    noStroke();
    ellipse(cx, cy, rCur * 2, rCur * 2);

    textAlign(CENTER, BOTTOM);
    textSize(9);
    fill(255, 255, 255, 220);
    text(fn.label + " (" + fn.hz + "Hz)", cx, cy - rCur - 6);
    
    fill(lerpColor(cYellow, cRed, ratio));
    textSize(8);
    text(pct + "% (" + round(fn.nutrients) + "u)", cx, cy - rCur + 3);

    fn.isBeingEaten = false;
  }
}

/* STREAMING_CHUNK:Drawing sidebar status header and widget panel */
void drawSidebarGUI(float x, float y, float w, float h) {
  fill(18, 20, 26);
  stroke(39, 39, 42);
  strokeWeight(1);
  rect(x, y, w, h, 6);

  fill(250, 204, 21);
  textAlign(LEFT, TOP);
  textSize(12);
  text("PHYSARUM BIO-SONIC ENGINE", x + 12, y + 10);
  fill(161, 161, 170);
  textSize(10);
  text("FPS: " + round(frameRate) + "  |  POP: " + nf(activeAgentCount / 1000.0f, 1, 1) + "k  |  OATS: " + foodNodes.size(), x + 12, y + 26);
  String midiStatus;
  if (!midiHandler.isReady()) midiStatus = "NO OUTPUT PORT";
  else midiStatus = midiEnabled ? "PROGRAMMER MODE" : "LIVE MODE (LINK OFF)";
  text("MIDI: " + midiStatus, x + 12, y + 38);

  ui.draw();
}

/* STREAMING_CHUNK:Handling mouse interaction for canvas and GUI */
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

/* STREAMING_CHUNK:Keyboard shortcuts (Full-Screen toggle via F or ESC) */
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

/* STREAMING_CHUNK:Flushing Launchpad RGB LEDs via MIDI note velocity */
void flushLaunchpadLeds() {
  if (!midiEnabled || !midiHandler.isReady()) return;
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

/* STREAMING_CHUNK:Implementing Launchpad MIDI SysEx, port selection and pad receiver */
class MidiHandler implements Receiver {
  MidiDevice inputDevice;
  MidiDevice outputDevice;
  Transmitter inTransmitter;
  volatile Receiver outReceiver;
  volatile boolean ready = false;

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

  // Prefer the Launchpad or MIDImix port
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
    if (sel <= 0 || sel > inInfos.size()) return;
    try {
      inputDevice = MidiSystem.getMidiDevice(inInfos.get(sel - 1));
      inputDevice.open();
      inTransmitter = inputDevice.getTransmitter();
      inTransmitter.setReceiver(this);
      inSel = sel;
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
    if (sel > 0 && sel <= outInfos.size()) {
      try {
        outputDevice = MidiSystem.getMidiDevice(outInfos.get(sel - 1));
        outputDevice.open();
        outReceiver = outputDevice.getReceiver();
        outSel = sel;
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
    if (!ready) return;
    try {
      byte[] sysex = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, (byte)0xF7};
      SysexMessage msg = new SysexMessage(sysex, sysex.length);
      outReceiver.send(msg, -1);
      for (int i = 0; i < 64; i++) padDirtyStates[i] = (byte) 255;
    } catch (Exception e) {
      println("SysEx Send Err: " + e.getMessage());
    }
    syncMidiMixLeds();
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
    if (!ready) return;
    try {
      byte[] sysex = new byte[]{(byte)0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00, (byte)0xF7};
      SysexMessage msg = new SysexMessage(sysex, sysex.length);
      outReceiver.send(msg, -1);
    } catch (Exception e) {}
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
      int cmd = sm.getCommand();
      int d1 = sm.getData1();
      int d2 = sm.getData2();

      if (cmd == ShortMessage.NOTE_ON && d2 > 0) {
        // --- Launchpad Grid Spawning ---
        int r10 = d1 / 10;
        int c10 = d1 % 10;
        if (r10 >= 1 && r10 <= 8 && c10 >= 1 && c10 <= 8) {
          int row = 8 - r10;
          int col = c10 - 1;
          float cellW = float(SIM_W) / GRID_DIM;
          float cellH = float(SIM_H) / GRID_DIM;
          float x = col * cellW + random(8, cellW - 8);
          float y = row * cellH + random(8, cellH - 8);
          addFoodNodule(x, y, 16.0f, 500.0f);
        }
        
        // --- MIDImix Buttons (LED sync included) ---
        // Toggles (Mute Row 1-6)
        else if (d1 == 1) { if (pauseToggle != null) { pauseToggle.set(!pauseToggle.state, true); sendPadColor(1, pauseToggle.state ? 127 : 0); } }
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

/* STREAMING_CHUNK:Implementing biquad lowpass resonant digital filter */
class BiquadFilter {
  float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  float x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  void setLowPass(float cutoffHz, float q, float sampleRate) {
    float omega = TWO_PI * constrain(cutoffHz, 40.0f, sampleRate * 0.45f) / sampleRate;
    float alpha = sin(omega) / (2.0f * max(0.1f, q));
    float cosW = cos(omega);

    float a0 = 1.0f + alpha;
    b0 = ((1.0f - cosW) / 2.0f) / a0;
    b1 = (1.0f - cosW) / a0;
    b2 = ((1.0f - cosW) / 2.0f) / a0;
    a1 = (-2.0f * cosW) / a0;
    a2 = (1.0f - alpha) / a0;
  }

  float process(float in) {
    float out = b0 * in + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = in;
    y2 = y1;
    y1 = out;
    return out;
  }
}

/* STREAMING_CHUNK:Implementing multi-threaded stereo PCM audio engine with UP-OLA Velvet Convolver & Master Dynamics Limiter */
class AudioEngine extends Thread {
  SourceDataLine line;
  PartitionedConvolver convolver;
  volatile boolean running = true;
  final int SAMPLE_RATE = 44100;
  final int BUFFER_SAMPLES = 512;

  // Master Dynamics Limiter & AGC envelope follower
  float env = 0.0f;
  // Attack ~2ms, Release ~100ms
  final float attackCoeff = (float) Math.exp(-1.0 / (0.002 * 44100.0));
  final float releaseCoeff = (float) Math.exp(-1.0 / (0.100 * 44100.0));

  public void run() {
    try {
      convolver = new PartitionedConvolver(BUFFER_SAMPLES);
      VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(
        SAMPLE_RATE, reverbT60, 2000.0f, 10000.0f, reverbHighDamping, reverbPreDelay, reverbSeed
      );
      convolver.loadImpulseResponse(ir.left, ir.right);

      AudioFormat format = new AudioFormat(SAMPLE_RATE, 16, 2, true, false);
      DataLine.Info info = new DataLine.Info(SourceDataLine.class, format);
      line = (SourceDataLine) AudioSystem.getLine(info);
      line.open(format, BUFFER_SAMPLES * 4 * 4);
      line.start();

      float[] sineTable = new float[4096];
      for (int i = 0; i < 4096; i++) {
        sineTable[i] = (float) Math.sin((i / 4096.0) * Math.PI * 2.0);
      }

      byte[] byteBuffer = new byte[BUFFER_SAMPLES * 4];
      byte[] silence = new byte[BUFFER_SAMPLES * 4];
      float[] inL = new float[BUFFER_SAMPLES];
      float[] inR = new float[BUFFER_SAMPLES];
      float[] outL = new float[BUFFER_SAMPLES];
      float[] outR = new float[BUFFER_SAMPLES];

      while (running) {
        if (!audioEnabled || foodNodes.isEmpty()) {
          line.write(silence, 0, silence.length);
          try { Thread.sleep(8); } catch (Exception e) {}
          continue;
        }

        int wave = waveformIdx; // read once per buffer

        // Count active voices and apply proportional headroom scaling (1 / sqrt(N))
        int activeVoices = 0;
        for (int v = 0; v < foodNodes.size(); v++) {
          try {
            FoodNodule fn = foodNodes.get(v);
            if (fn.vcaGain >= 0.001f) activeVoices++;
          } catch (IndexOutOfBoundsException e) { break; }
        }
        float voiceScale = (activeVoices > 0) ? (0.24f / (float) Math.sqrt(Math.max(1.0, activeVoices * 0.75))) : 0.24f;

        // Clear input block buffers
        for (int i = 0; i < BUFFER_SAMPLES; i++) {
          inL[i] = 0.0f;
          inR[i] = 0.0f;
        }

        for (int v = 0; v < foodNodes.size(); v++) {
          FoodNodule fn;
          try {
            fn = foodNodes.get(v);
          } catch (IndexOutOfBoundsException e) { break; }
          
          if (fn.vcaGain < 0.001f) continue;

          // Pan voices across stereo field based on canvas horizontal location
          float panNorm = constrain(fn.x / (float) SIM_W, 0.05f, 0.95f);
          float panL = (float) Math.cos(panNorm * Math.PI * 0.5);
          float panR = (float) Math.sin(panNorm * Math.PI * 0.5);
          float voiceGainL = fn.vcaGain * voiceScale * panL;
          float voiceGainR = fn.vcaGain * voiceScale * panR;

          for (int i = 0; i < BUFFER_SAMPLES; i++) {
            float raw;
            if (wave == 0) {        // Triangle
              raw = (fn.phase < 0.5f) ? (4.0f * fn.phase - 1.0f) : (3.0f - 4.0f * fn.phase);
            } else if (wave == 1) { // Sine
              int idx = (int)(fn.phase * 4096f) & 4095;
              raw = sineTable[idx];
            } else if (wave == 2) { // Sawtooth
              raw = 2.0f * fn.phase - 1.0f;
            } else {                // Square
              raw = (fn.phase < 0.5f) ? 0.8f : -0.8f;
            }

            fn.phase = (fn.phase + fn.frequency / SAMPLE_RATE) % 1.0f;

            float filtered = fn.filter.process(raw);
            inL[i] += filtered * voiceGainL;
            inR[i] += filtered * voiceGainR;
          }
        }

        // Real-Time UP-OLA Velvet Noise Convolver
        if (reverbEnabled && convolver != null && convolver.isLoaded()) {
          convolver.processBlock(inL, inR, outL, outR, reverbWet, reverbDry);
        } else {
          for (int i = 0; i < BUFFER_SAMPLES; i++) {
            outL[i] = inL[i];
            outR[i] = inR[i];
          }
        }

        for (int i = 0; i < BUFFER_SAMPLES; i++) {
          // Stereo peak detector envelope follower
          float absSample = Math.max(Math.abs(outL[i]), Math.abs(outR[i]));
          if (absSample > env) {
            env = attackCoeff * env + (1.0f - attackCoeff) * absSample;
          } else {
            env = releaseCoeff * env + (1.0f - releaseCoeff) * absSample;
          }

          // Fast-acting transparent limiter: threshold = 0.75 (~ -2.5 dB)
          float limiterGain = 1.0f;
          final float threshold = 0.75f;
          if (env > threshold) {
            limiterGain = threshold / env;
          }

          float limitedL = outL[i] * limiterGain;
          float limitedR = outR[i] * limiterGain;

          // Transparent soft knee ceiling as a safety brickwall (guaranteed <= 0.98, zero harsh distortion)
          float finalL = softKnee(limitedL);
          float finalR = softKnee(limitedR);

          short pcmL = (short) (finalL * 32000.0f);
          short pcmR = (short) (finalR * 32000.0f);

          int bIdx = i * 4;
          byteBuffer[bIdx]     = (byte) (pcmL & 0xFF);
          byteBuffer[bIdx + 1] = (byte) ((pcmL >> 8) & 0xFF);
          byteBuffer[bIdx + 2] = (byte) (pcmR & 0xFF);
          byteBuffer[bIdx + 3] = (byte) ((pcmR >> 8) & 0xFF);
        }

        line.write(byteBuffer, 0, byteBuffer.length);
      }
    } catch (Exception e) {
      println("Audio Engine Exception: " + e.getMessage());
    }
  }

  private float fastTanh(float x) {
    if (x < -3.0f) return -1.0f;
    if (x > 3.0f) return 1.0f;
    float x2 = x * x;
    return x * (27.0f + x2) / (27.0f + 9.0f * x2);
  }

  private float softKnee(float v) {
    if (v > 0.85f) {
      return 0.85f + 0.13f * fastTanh((v - 0.85f) / 0.13f);
    } else if (v < -0.85f) {
      return -0.85f + 0.13f * fastTanh((v + 0.85f) / 0.13f);
    } else {
      return v;
    }
  }

  void closeEngine() {
    running = false;
    if (line != null) {
      line.stop();
      line.close();
    }
  }
}

/* STREAMING_CHUNK:Cleaning up MIDI and audio resources on sketch exit */
void exit() {
  if (midiHandler != null) {
    midiHandler.shutdown();
  }
  if (audioEngine != null) {
    audioEngine.closeEngine();
  }
  if (irExecutor != null) {
    irExecutor.shutdownNow();
  }
  super.exit();
}
