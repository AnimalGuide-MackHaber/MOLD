// =============================================================================
// FoodNodule.pde - Food Nodule Entity, State, and Audio Voice Modulation
// =============================================================================

// ---- Spatial & Grid Geometry Helpers ----

int worldToGridCol(float px) {
  return constrain(int((px / SIM_W) * GRID_DIM), 0, GRID_DIM - 1);
}

int worldToGridRow(float py) {
  return constrain(int((py / SIM_H) * GRID_DIM), 0, GRID_DIM - 1);
}

float spatialNormalizedDx(float px) {
  float halfW = SIM_W * 0.5f;
  return constrain((px - halfW) / halfW, -1.0f, 1.0f);
}

float spatialNormalizedDy(float py) {
  float halfH = SIM_H * 0.5f;
  return constrain((halfH - py) / halfH, -1.0f, 1.0f);
}

float spatialShapedBipolar(float b) {
  float sign = (b < 0.0f) ? -1.0f : 1.0f;
  return sign * (float) Math.pow(Math.abs(b), 1.35f);
}

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
  boolean wasBeingEaten = false;
  boolean isDepleted = false;
  float consumptionActivity = 0.0f; // Smooth transition for visual feedback
  volatile float vcaGain = 0.0f;
  float lpfCutoff = 80.0f;
  BiquadFilter filter;
  BiquadFilter headShadowL;
  BiquadFilter headShadowR;
  BiquadFilter airDampFilter;
  BiquadFilter pinnaElevationFilter;
  BiquadFilter frontBackFilter;
  final float[] delayBufL = new float[128];
  final float[] delayBufR = new float[128];
  int delayIdx = 0;
  float phase = 0.0f;
  volatile float elevationNorm = 0.0f; // 0.0 = ear level / horizon, 1.0 = zenith / overhead

  // Multi-modal inharmonic bell synthesis state
  final float[] bellPhases = new float[BELL_NUM_PARTIALS];
  final float[] bellAmps = new float[BELL_NUM_PARTIALS];
  final float[] bellCurAmp = new float[BELL_NUM_PARTIALS];
  final float[] bellRampAmp = new float[BELL_NUM_PARTIALS];
  final float[] bellPhaseIncs = new float[BELL_NUM_PARTIALS];

  FoodNodule(float px, float py, float r, float cap) {
    x = px;
    y = py;
    maxRadius = r;
    radius = r;
    initialCapacity = cap;
    nutrients = cap;
    gridCol = worldToGridCol(x);
    gridRow = worldToGridRow(y);

    applyHarmonics();
    filter = new BiquadFilter();
    headShadowL = new BiquadFilter();
    headShadowR = new BiquadFilter();
    airDampFilter = new BiquadFilter();
    pinnaElevationFilter = new BiquadFilter();
    frontBackFilter = new BiquadFilter();

    for (int p = 0; p < BELL_NUM_PARTIALS; p++) {
      bellPhases[p] = (float) Math.random();
      bellAmps[p] = 0.0f;
    }
  }

  // Strike excitation: impacts all vibrational modes with characteristic bell strike amplitudes
  void strike(float velocity) {
    if (velocity <= 0.0f) return;
    for (int p = 0; p < BELL_NUM_PARTIALS; p++) {
      float sAmp = BELL_STRIKE_AMPS[p] * velocity;
      if (sAmp > bellAmps[p]) {
        bellAmps[p] = sAmp;
      }
    }
  }

  // Total instantaneous vibrational energy across all harmonic modes
  float getBellTotalEnergy() {
    float sum = 0.0f;
    for (int p = 0; p < BELL_NUM_PARTIALS; p++) {
      sum += bellAmps[p];
    }
    return sum;
  }

  void applyHarmonics() {
    HarmonicData hd = cellHarmonics[gridRow * GRID_DIM + gridCol];
    frequency = hd.freq;
    label = hd.label;
    hz = hd.hz;
  }

  // Physical nutrient capacity and core lowpass sweep
  void updatePhysicalState() {
    float ratio = max(0.0f, nutrients / initialCapacity);
    radius = max(2.5f, maxRadius * pow(ratio, 0.65f));
    lpfCutoff = filterBaseHz + (filterMaxHz - filterBaseHz) * pow(ratio, 1.8f * filterSens);
  }

  // 3D Binaural Geometry and Pinna Spectral Cues
  void updateSpatialFilters() {
    float dx = spatialNormalizedDx(x);
    float dy = spatialNormalizedDy(y);
    float distNorm = (float) Math.sqrt(dx * dx + dy * dy);

    // 1. Core voice resonant lowpass filter (full acoustic nutrient sweep & user resonance)
    filter.setLowPass(lpfCutoff, filterQ, 44100.0f);

    // 2. Frequency-Dependent Interaural Level Difference (Spherical Head Shadow Model)
    // Rayleigh / Duda-Martens model: ~2.2kHz transition frequency
    // Contralateral ear gets deep acoustic skull shadow (-9.0dB at 1.0x, up to -16dB at 2.0x)
    // Ipsilateral ear gets pinna presence boost (+1.5dB at 1.0x, up to +3.0dB at 2.0x)
    float bShaped = spatialShapedBipolar(dx);
    float absB = Math.abs(bShaped);
    float depth = binauralDepth;

    float ipsiGain = 1.5f * absB * depth;
    float contraCut = -9.0f * absB * depth;

    float gainDbL = (bShaped <= 0.0f) ? ipsiGain : contraCut;
    float gainDbR = (bShaped >= 0.0f) ? ipsiGain : contraCut;

    headShadowL.setHighShelf(2200.0f, gainDbL, 44100.0f);
    headShadowR.setHighShelf(2200.0f, gainDbR, 44100.0f);

    // 3. Front/Back Spectral Pinna Cues:
    // Forward presence (+2.0dB at 1.0x) vs rear pinna shadow (-7.5dB at 1.0x, up to -15dB at 2.0x)
    float frontBackGainDb = (dy >= 0.0f) ? (dy * 2.0f * depth) : (dy * 7.5f * depth);
    frontBackFilter.setHighShelf(3800.0f, frontBackGainDb, 44100.0f);

    // 4. Distance Air Absorption Filter (Atmospheric high-frequency roll-off across space)
    float airLossDb = -constrain(distNorm * 4.2f * depth, 0.0f, 12.0f);
    airDampFilter.setHighShelf(4500.0f, airLossDb, 44100.0f);
  }

  // Slime Mold Mass -> 3D Height / Elevation notch filter
  void updateElevationFilter(float adjacentMass) {
    float targetElev = constrain(adjacentMass / 800.0f, 0.0f, 1.0f);
    elevationNorm += (targetElev - elevationNorm) * 0.12f;

    float notchFreq = 6200.0f + elevationNorm * 3000.0f;
    float notchDepthDb = -4.0f - elevationNorm * 4.0f; // -4dB at horizon -> -8dB deep notch overhead
    pinnaElevationFilter.setPeakNotch(notchFreq, 2.5f, notchDepthDb, 44100.0f);
  }

  // Adjacent mass VCA envelope and consumption activity smoothing
  void updateVcaModulation(float adjacentMass) {
    float effectiveMass = max(0.0f, adjacentMass - vcaGateThreshold);
    float drive = (effectiveMass * vcaSensitivity * 1.25f) / 1000.0f;
    float targetVca = (isBeingEaten) ? (float) Math.tanh(drive) : 0.0f;
    vcaGain += (targetVca - vcaGain) * 0.15f;

    float targetActivity = isBeingEaten ? 1.0f : 0.0f;
    consumptionActivity += (targetActivity - consumptionActivity) * 0.12f;
  }

  void updateAudioParameters(float adjacentMass) {
    updatePhysicalState();
    updateSpatialFilters();
    updateElevationFilter(adjacentMass);
    updateVcaModulation(adjacentMass);
  }
}

void addFoodNodule(float x, float y, float r, float cap) {
  FoodNodule fn = new FoodNodule(x, y, r, cap);
  if (bellAcousticsMode && bellStrikeIntensity > 0.0f) {
    fn.strike(0.6f * bellStrikeIntensity);
  }
  foodNodes.add(fn);
}
