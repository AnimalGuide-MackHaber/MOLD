// =============================================================================
// Harmony.pde - Harmonic Pitch Grid, Scale Semitones, and Tuning Matrices
// =============================================================================

class HarmonicData {
  float freq;
  String label;
  int hz;
}

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
