import javax.sound.sampled.*;
import javax.sound.midi.*;
import java.util.ArrayList;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// =============================================================================
// PHYSARUM POLYCEPHALUM 8x8 HARMONIC SYNTHESIZER & HARDWARE CONTROLLER
// Processing Sketch (.pde) - Self-Contained with Zero External Library Dependencies
// Real-time Sound Synthesis (javax.sound.sampled) & Hardware MIDI (javax.sound.midi)
// Tabs:
//   - Simulation.pde   : Agent dynamics, chemotaxis, trail diffusion, bioenergetics
//   - FoodNodule.pde   : Food nodule entity, nutrients, audio parameters
//   - Harmony.pde      : Musical pitch cache, scale matrices, tuning
//   - Render.pde       : Discrete pixel rendering, canvas overlays, sidebar header
//   - Controls.pde     : UI widget construction, callbacks, mouse & keyboard input
//   - UI.pde           : Immediate-mode lightweight widget framework
//   - Midi.pde         : Launchpad Mini & Akai MIDImix MIDI hardware driver
//   - Audio.pde        : Realtime stereo audio thread, Biquad filter, convolver
// =============================================================================

final int SIM_W = 720;
final int SIM_H = 720;
final int GRID_DIM = 8;
final int MAX_AGENTS = 64000;
final int INITIAL_AGENTS = 16000;
int targetAgentCount = INITIAL_AGENTS;
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

// Simulation Dynamics & Bioenergetics
float simSpeed = 1.0f;
float speedAccumulator = 0.0f;
volatile boolean isPaused = false;
float sensorDist = 40.0f;
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

// Musical tuning matrices and scales
int keyRootIndex = 9; // 0=C, 9=A
int baseOctave = 2;
int currentScaleIdx = 0;
volatile int waveformIdx = 0; // 0=triangle, 1=sine, 2=sawtooth, 3=square
float filterSens = 3.0f; // Default to maximum value on start up (range: 0.2f - 3.0f)
float filterQ = 18.0f;   // Default to maximum value on start up (range: 0.5f - 18.0f)
float filterBaseHz = 80.0f;
float filterMaxHz = 3200.0f;
float vcaSensitivity = 1.0f;
float vcaGateThreshold = 120.0f;
boolean showGridOverlay = false;
int paletteIdx = 0; // 0=yellow (Zorn), 1=mono, 2=cyan
float visualSharpness = 0.0f;
float visualBlur = 0.0f; // 0.0=gradient, 1.0=sharp on/off

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

// Memory buffers for cellular slime mold
float[] trailMap;
float[] nextTrailMap;
PImage trailTexture;

PGraphics renderFBO;
PGraphics motionBlurFBO;
PShader renderShader;

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

float prevColonyEnergy = 0;

// Subsystems
AudioEngine audioEngine;
volatile boolean audioEnabled = false;

// Velvet-Noise Algorithmic Convolver Reverb
volatile boolean reverbEnabled = true;
volatile boolean autoModulateReverb = true;
volatile float reverbBioModDepth = 2.0f; // Mold bio-modulation depth multiplier (default 2.0x is 2x as pronounced)
volatile float baseReverbWet = 0.50f;
volatile float baseReverbDry = 0.80f;
volatile float baseReverbT60 = 3.5f;
volatile float baseReverbHighDamping = 0.45f;
volatile float baseReverbPreDelay = 0.015f;
volatile float reverbWet = 0.50f;
volatile float reverbDry = 0.80f;
volatile float reverbT60 = 3.5f;
volatile float reverbHighDamping = 0.45f;
volatile float reverbPreDelay = 0.015f;
long reverbSeed = 1337L;
float lastMitosisBiomassThreshold = 8000.0f;
ExecutorService irExecutor = Executors.newSingleThreadExecutor();

Slider simSpeedSlider;
int octaveShiftIdx = 1;
String[] OCTAVE_NAMES = {"-1 OCT", "NORMAL", "+1 OCT"};
Slider filterSensSlider;
Slider filterQSlider;
Slider vcaSensSlider;
Slider sensorDistSlider;
Slider bmrSlider;
Slider locoCostSlider;

Slider reverbBioModSlider;
Slider reverbWetSlider;
Slider reverbDrySlider;
Slider reverbT60Slider;
Slider reverbDampSlider;
Slider reverbPreSlider;
Slider visualSharpnessSlider;
Slider visualBlurSlider;
Slider agentCountSlider;
Slider ledThresholdSlider;
Slider lpRippleWidthSlider;
float ledMassThreshold = 120.0f;
float lpRippleWidth = 3.0f;

// Launchpad LED Display Layers (default: only show slime mold position)
boolean lpShowSlime = true;
boolean lpShowFood = false;
boolean lpShowEating = false;

Toggle lpShowSlimeToggle;
Toggle lpShowFoodToggle;
Toggle lpShowEatingToggle;
Toggle lpRgbModeToggle;
Toggle lpUserModeToggle;

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
volatile boolean pendingReinoculateFboClear = false;

// UI
UIPanel ui;
Dropdown midiInDropdown;
Dropdown midiOutDropdown;
Dropdown midimixInDropdown;
Dropdown midimixOutDropdown;

// =============================================================================
// Window & Display Mode Configuration
// Default: Native borderless full screen with hardware-accelerated OpenGL.
// (To run in windowed mode instead, see setup() below).
// =============================================================================

// Toggle theater / presentation mode (hide sidebar to expand canvas view)
void toggleFullScreen() {
  isFullScreen = !isFullScreen;
  if (fullScreenToggle != null) fullScreenToggle.state = isFullScreen;
  recalculateLayout();
}

void recalculateLayout() {
  if (isFullScreen) {
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
    sidebarX = width - sidebarW - margin;
    float availW = sidebarX - gap - margin;
    float availH = height - margin * 2 - 20;
    canvasS = max(200.0f, min(availW, availH));
    canvasX = margin + max(0.0f, (availW - canvasS) / 2.0f);
    canvasY = max(margin, (height - canvasS) / 2.0f);
    sidebarH = canvasS;
  }
  if (ui != null) {
    ui.updateBounds(sidebarX, sidebarY() + 52, sidebarW, sidebarY() + sidebarH - 4);
  }
}

float sidebarY() {
  return isFullScreen ? 16 : canvasY;
}

void configureNativeFullScreen() {
  try {
    processing.core.PApplet.hideMenuBar();
  } catch (Throwable t) {}
}

void setup() {
  // Borderless native full screen with hardware-accelerated OpenGL:
  fullScreen(P2D);
  // (To launch in a standard 1060x760 window instead, comment out fullScreen(P2D) above and uncomment below):
  // size(1060, 760, P2D);
  pixelDensity(1);
  noSmooth();

  surface.setTitle("Physarum Polycephalum 8x8 Sonification Matrix");
  frameRate(60);

  // Enforce true macOS fullscreen and completely hide menu bar & dock
  configureNativeFullScreen();


  renderFBO = createGraphics(SIM_W, SIM_H, P2D);
  motionBlurFBO = createGraphics(SIM_W, SIM_H, P2D);
  renderFBO.noSmooth();
  motionBlurFBO.noSmooth();
  renderFBO.beginDraw();
  renderFBO.background(0);
  renderFBO.endDraw();
  motionBlurFBO.beginDraw();
  motionBlurFBO.background(0);
  motionBlurFBO.endDraw();
  
  renderShader = loadShader("render.glsl");
  
  trailMap = new float[SIM_W * SIM_H];
  nextTrailMap = new float[SIM_W * SIM_H];
  trailTexture = createImage(SIM_W, SIM_H, ARGB);
  trailTexture.loadPixels();

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

void draw() {
  if (pendingReinoculateFboClear) {
    pendingReinoculateFboClear = false;
    if (motionBlurFBO != null) {
      motionBlurFBO.beginDraw();
      motionBlurFBO.background(0);
      motionBlurFBO.endDraw();
    }
    if (renderFBO != null) {
      renderFBO.beginDraw();
      renderFBO.background(0);
      renderFBO.endDraw();
    }
  }

  background(11, 12, 16);

  if (!isPaused) {
    speedAccumulator += simSpeed * 0.4f;
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
  

  if (showGridOverlay) {
    drawGridOverlay(canvasX, canvasY, canvasS, canvasS);
  }

  drawFoodNodules(canvasX, canvasY, canvasS, canvasS);

  if (!isFullScreen) {
    fill(113, 113, 122);
    textSize(9);
    textAlign(LEFT, TOP);
    text("Click canvas: drop oat nodule  •  Launchpad: drop oats  •  MIDImix: control params  •  Amber: food  •  Cyan: biomass  •  [F]: Full Screen",
         canvasX, canvasY + canvasS + 4);

    drawSidebarGUI(sidebarX, sidebarY(), sidebarW, sidebarH);
  }

  flushLaunchpadLeds();
}

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
