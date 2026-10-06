// =============================================================================
// FoodNodule.pde - Food Nodule Entity, State, and Audio Voice Modulation
// =============================================================================

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
