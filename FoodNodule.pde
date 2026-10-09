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
  float consumptionActivity = 0.0f; // Smooth transition for visual feedback
  volatile float vcaGain = 0.0f;
  float lpfCutoff = 80.0f;
  BiquadFilter filter;
  BiquadFilter filterR;
  BiquadFilter pinnaElevationFilter;
  BiquadFilter frontBackFilter;
  final float[] delayBufL = new float[32];
  final float[] delayBufR = new float[32];
  int delayIdx = 0;
  float phase = 0.0f;
  volatile float elevationNorm = 0.0f; // 0.0 = ear level / horizon, 1.0 = zenith / overhead

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
    filterR = new BiquadFilter();
    pinnaElevationFilter = new BiquadFilter();
    frontBackFilter = new BiquadFilter();
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

    // Lateral azimuth head-shadow tilt on left/right ears
    float cutoffL = constrain(lpfCutoff * (1.0f - dx * 0.18f), 40.0f, 18000.0f);
    float cutoffR = constrain(lpfCutoff * (1.0f + dx * 0.18f), 40.0f, 18000.0f);
    filter.setLowPass(cutoffL, filterQ, 44100.0f);
    filterR.setLowPass(cutoffR, filterQ, 44100.0f);

    // Front/Back Spectral Pinna Cues:
    // Rear shadowing (high-shelf cut up to -4.5dB above 3.8kHz) vs front presence (+1.5dB above 4kHz)
    float frontBackGainDb = (dy >= 0.0f) ? (dy * 1.5f) : (dy * 4.5f);
    frontBackFilter.setHighShelf(4000.0f, frontBackGainDb, 44100.0f);
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
  foodNodes.add(fn);
}
