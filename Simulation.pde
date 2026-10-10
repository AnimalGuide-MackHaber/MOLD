// =============================================================================
// Simulation.pde - Physarum Slime Mold Chemotaxis, Trail Diffusion & Bioenergetics
// =============================================================================

// Seeding initial central colony blob
void seedCentralInoculate() {
  activeAgentCount = INITIAL_AGENTS;
  float cx = SIM_W * 0.5f;
  float cy = SIM_H * 0.5f;
  float radius = 24.0f;

  for (int i = 0; i < SIM_W * SIM_H; i++) {
    trailMap[i] = 0;
    if (nextTrailMap != null) nextTrailMap[i] = 0;
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

// Scattering randomized initial food reserves
void scatterInitialFood(int count) {
  for (int i = 0; i < count; i++) {
    float x = random(40, SIM_W - 40);
    float y = random(40, SIM_H - 40);
    float r = random(8.0f, 24.0f);
    addFoodNodule(x, y, r, r * r * 2.0f);
  }
}

// ---- Fast math helpers for the agent loop ----
// 4096-entry sine table: max angle error ~0.0008 rad (~0.035 px at max sensor reach)
final int TRIG_N = 4096;
final int TRIG_MASK = TRIG_N - 1;
final float TRIG_SCALE = TRIG_N / TWO_PI;
final float[] SIN_LUT = buildSinLUT();

float[] buildSinLUT() {
  float[] t = new float[TRIG_N];
  for (int i = 0; i < TRIG_N; i++) t[i] = (float) Math.sin(i * (Math.PI * 2.0) / TRIG_N);
  return t;
}

// Xorshift32 RNG for the simulation thread (java.util.Random is atomic/CAS-based and much slower)
int simRng = 0x9E3779B9;
float simRand(float lo, float hi) {
  int s = simRng;
  s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
  simRng = s;
  return lo + (hi - lo) * ((s >>> 8) * (1.0f / 16777216.0f));
}

// Sampling chemoattractant trail with bilinear interpolation
// Inputs are at most one canvas width outside [0, SIM) (sensor reach <= 45 px), so one wrap suffices.
float sampleChemo(float px, float py) {
  float x = px;
  if (x < 0) x += SIM_W; else if (x >= SIM_W) x -= SIM_W;
  float y = py;
  if (y < 0) y += SIM_H; else if (y >= SIM_H) y -= SIM_H;

  int x0 = (int) x;
  int y0 = (int) y;
  float fx = x - x0;
  float fy = y - y0;
  if (x0 >= SIM_W) x0 = 0; // float rounding guard (e.g. -1e-7 + 420 == 420.0f)
  if (y0 >= SIM_H) y0 = 0;

  int x1 = (x0 + 1 == SIM_W) ? 0 : x0 + 1;
  int y1 = (y0 + 1 == SIM_H) ? 0 : y0 + 1;

  float[] tm = trailMap;
  int r0 = y0 * SIM_W;
  int r1 = y1 * SIM_W;
  float top = tm[r0 + x0] + (tm[r0 + x1] - tm[r0 + x0]) * fx;
  float btm = tm[r1 + x0] + (tm[r1 + x1] - tm[r1 + x0]) * fx;
  return top + (btm - top) * fy;
}

// Adjust population towards target count (cull or spawn)
void adjustPopulationToTarget() {
  int popDiff = activeAgentCount - targetAgentCount;
  if (popDiff > 0) {
    activeAgentCount -= Math.min(popDiff, 500);
  } else if (popDiff < 0 && activeAgentCount > 0) {
    int spawnCount = Math.min(-popDiff, 500);
    for (int i = 0; i < spawnCount; i++) {
      if (activeAgentCount >= MAX_AGENTS) break;
      int srcIdx = (int) simRand(0, activeAgentCount);
      if (srcIdx >= activeAgentCount) srcIdx = 0;
      agentX[activeAgentCount] = agentX[srcIdx] + simRand(-2f, 2f);
      agentY[activeAgentCount] = agentY[srcIdx] + simRand(-2f, 2f);
      agentHeading[activeAgentCount] = simRand(0, TWO_PI);
      agentEnergy[activeAgentCount] = 40.0f;
      activeAgentCount++;
    }
  }
}

// Apply accumulated grazing hits once per nodule
void applyAccumulatedGrazing(FoodNodule[] foods, int[] foodHits, int nFood) {
  for (int f = 0; f < nFood; f++) {
    if (foodHits[f] > 0) {
      foods[f].grazingBuffer += grazingRate * foodHits[f];
      if (!foods[f].wasBeingEaten) {
        if (bellAcousticsMode && bellStrikeIntensity > 0.0f) {
          foods[f].strike(1.0f * bellStrikeIntensity);
        }
        foods[f].wasBeingEaten = true;
      }
      foods[f].isBeingEaten = true;
    } else {
      foods[f].wasBeingEaten = false;
    }
  }
}

// Insert newborn agents created through mitosis
void insertMitosisNewborns(int count) {
  for (int n = 0; n < count; n++) {
    int slot = activeAgentCount;
    if (slot < MAX_AGENTS) {
      agentX[slot] = (newX[n] + SIM_W) % SIM_W;
      agentY[slot] = (newY[n] + SIM_H) % SIM_H;
      agentHeading[slot] = newHeading[n];
      agentEnergy[slot] = newEnergy[n];
      activeAgentCount++;
    }
  }
}

void stepBioenergetics() {
  float totalColonyEnergy = 0;
  int newbornCount = 0;

  adjustPopulationToTarget();

  // Hoist fields/params to locals once per step
  final float[] ax = agentX, ay = agentY, ah = agentHeading, ae = agentEnergy;
  final float[] lut = SIN_LUT;
  final float sDist = sensorDist;
  final float bmrL = bmr;
  final float locoL = locomotionCost;
  // Sensor offsets via rotation identity: cos(h±a) = cos h·cos a ∓ sin h·sin a
  final float cosA = (float) Math.cos(sensorAngle);
  final float sinA = (float) Math.sin(sensorAngle);
  final int quarter = TRIG_N / 4;

  // Snapshot food once per step (iterating a CopyOnWriteArrayList per agent allocates an iterator each time)
  final FoodNodule[] foods = foodNodes.toArray(new FoodNodule[0]);
  final int nFood = foods.length;
  final float[] foodX = new float[nFood], foodY = new float[nFood], foodR2 = new float[nFood];
  final int[] foodHits = new int[nFood];
  for (int f = 0; f < nFood; f++) {
    foodX[f] = foods[f].x;
    foodY[f] = foods[f].y;
    foodR2[f] = foods[f].radius * foods[f].radius;
  }
  final float grazeGain = grazingRate * assimilationYield;

  for (int i = activeAgentCount - 1; i >= 0; i--) {
    float x = ax[i];
    float y = ay[i];
    float heading = ah[i];
    float energy = ae[i] - bmrL;

    // 3-Sensor Chemotaxis Sampling
    int hIdx = (int) (heading * TRIG_SCALE) & TRIG_MASK;
    float sh = lut[hIdx];
    float ch = lut[(hIdx + quarter) & TRIG_MASK];
    float cl = ch * cosA + sh * sinA;   // cos(h - a)
    float sl = sh * cosA - ch * sinA;   // sin(h - a)
    float cr = ch * cosA - sh * sinA;   // cos(h + a)
    float sr = sh * cosA + ch * sinA;   // sin(h + a)

    float valF = sampleChemo(x + ch * sDist, y + sh * sDist);
    float valL = sampleChemo(x + cl * sDist, y + sl * sDist);
    float valR = sampleChemo(x + cr * sDist, y + sr * sDist);

    if (valF > valL && valF > valR) {
      heading += simRand(-0.04f, 0.04f);
    } else if (valL > valR) {
      heading -= turnAngle + simRand(-0.03f, 0.03f);
    } else if (valR > valL) {
      heading += turnAngle + simRand(-0.03f, 0.03f);
    } else {
      heading += simRand(-0.4f, 0.4f);
    }

    // Hunger-Driven Wandering Impulse
    if (energy < 28.0f) {
      heading += simRand(-0.35f, 0.35f);
    }

    // Keep heading in [0, 2π) so it never grows unbounded (trig is periodic; behavior unchanged)
    if (heading < 0) heading += TWO_PI; else if (heading >= TWO_PI) heading -= TWO_PI;

    // Locomotion Exploration Cost
    float localTrail = sampleChemo(x, y);
    float territoryCost = Math.max(0.25f, 1.0f - (localTrail * (1.0f / 80.0f)));
    energy -= locoL * territoryCost;

    int mIdx = (int) (heading * TRIG_SCALE) & TRIG_MASK;
    float nx = x + lut[(mIdx + quarter) & TRIG_MASK];
    float ny = y + lut[mIdx];
    if (nx < 0) nx += SIM_W; else if (nx >= SIM_W) nx -= SIM_W;
    if (ny < 0) ny += SIM_H; else if (ny >= SIM_H) ny -= SIM_H;

    // Ingestion of Food Nodules
    for (int f = 0; f < nFood; f++) {
      if (foods[f].isDepleted) continue;
      float dx = nx - foodX[f];
      float dy = ny - foodY[f];
      if (dx * dx + dy * dy <= foodR2[f]) {
        foodHits[f]++;
        energy += grazeGain;
      }
    }

    // Starvation Necrosis
    if (energy <= 0.0f) {
      int lastIdx = activeAgentCount - 1;
      if (i != lastIdx) {
        ax[i] = ax[lastIdx];
        ay[i] = ay[lastIdx];
        ah[i] = ah[lastIdx];
        ae[i] = ae[lastIdx];
      }
      activeAgentCount--;
      continue;
    }

    // Mitosis Division
    if (energy >= mitosisThreshold && (activeAgentCount + newbornCount) < MAX_AGENTS && newbornCount < MAX_NEWBORNS - 10) {
      energy *= 0.48f;
      newX[newbornCount] = nx + simRand(-1.5f, 1.5f);
      newY[newbornCount] = ny + simRand(-1.5f, 1.5f);
      newHeading[newbornCount] = heading + simRand(-1.0f, 1.0f);
      newEnergy[newbornCount] = energy;
      newbornCount++;
    }

    ax[i] = nx;
    ay[i] = ny;
    ah[i] = heading;
    ae[i] = energy;
    totalColonyEnergy += energy;

    int px = (int) nx, py = (int) ny;
    if (px >= SIM_W) px = 0;
    if (py >= SIM_H) py = 0;
    int idx = py * SIM_W + px;
    trailMap[idx] = Math.min(255.0f, trailMap[idx] + depositAmount);
  }

  applyAccumulatedGrazing(foods, foodHits, nFood);
  insertMitosisNewborns(newbornCount);

  prevColonyEnergy = totalColonyEnergy;
}

// Inject food nodule chemoattractant cores into the trail map
void injectFoodChemoCores() {
  for (FoodNodule fn : foodNodes) {
    if (fn.isDepleted) continue;
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
}

// 3x3 Box Blur Convolution + Decay across the trail map
void convolveAndDecayTrailMap() {
  final float cCenter = (1.0f - trailDiffuse) * trailDecay;
  final float cNeigh = 0.125f * trailDiffuse * trailDecay;

  for (int y = 0; y < SIM_H; y++) {
    int yTop = (y == 0 ? SIM_H - 1 : y - 1) * SIM_W;
    int yMid = y * SIM_W;
    int yBtm = (y == SIM_H - 1 ? 0 : y + 1) * SIM_W;

    // x = 0 (left wraps to SIM_W - 1, right is 1)
    {
      float sum = trailMap[yTop + (SIM_W - 1)] + trailMap[yTop] + trailMap[yTop + 1] +
                  trailMap[yMid + (SIM_W - 1)] +                  trailMap[yMid + 1] +
                  trailMap[yBtm + (SIM_W - 1)] + trailMap[yBtm] + trailMap[yBtm + 1];
      float result = trailMap[yMid] * cCenter + sum * cNeigh;
      nextTrailMap[yMid] = (result > 0.15f) ? result : 0.0f;
    }

    // Interior x: 1 .. SIM_W - 2 (contiguous sequential array accesses, 0 modulos)
    for (int x = 1; x < SIM_W - 1; x++) {
      float sum = trailMap[yTop + x - 1] + trailMap[yTop + x] + trailMap[yTop + x + 1] +
                  trailMap[yMid + x - 1] +                     trailMap[yMid + x + 1] +
                  trailMap[yBtm + x - 1] + trailMap[yBtm + x] + trailMap[yBtm + x + 1];
      float result = trailMap[yMid + x] * cCenter + sum * cNeigh;
      nextTrailMap[yMid + x] = (result > 0.15f) ? result : 0.0f;
    }

    // x = SIM_W - 1 (left is SIM_W - 2, right wraps to 0)
    {
      int x = SIM_W - 1;
      float sum = trailMap[yTop + x - 1] + trailMap[yTop + x] + trailMap[yTop] +
                  trailMap[yMid + x - 1] +                     trailMap[yMid] +
                  trailMap[yBtm + x - 1] + trailMap[yBtm + x] + trailMap[yBtm];
      float result = trailMap[yMid + x] * cCenter + sum * cNeigh;
      nextTrailMap[yMid + x] = (result > 0.15f) ? result : 0.0f;
    }
  }

  float[] temp = trailMap;
  trailMap = nextTrailMap;
  nextTrailMap = temp;
}

// Diffusing trail map and evaporating old paths
void diffuseAndEvaporate() {
  injectFoodChemoCores();
  convolveAndDecayTrailMap();
}

// Compute 8x8 cell biomass distribution from active agents
void computeCellBiomass() {
  for (int i = 0; i < 64; i++) cellBiomass[i] = 0;

  float cellW = float(SIM_W) / GRID_DIM;
  float cellH = float(SIM_H) / GRID_DIM;
  float invCellW = 1.0f / cellW;
  float invCellH = 1.0f / cellH;

  for (int i = 0; i < activeAgentCount; i++) {
    int c = constrain(int(agentX[i] * invCellW), 0, GRID_DIM - 1);
    int r = constrain(int(agentY[i] * invCellH), 0, GRID_DIM - 1);
    cellBiomass[r * GRID_DIM + c] += agentEnergy[i];
  }
}

// Compute Moore Neighborhood sum (8 adjacent cells) for a grid coordinate
float computeMooreAdjacentMass(int col, int row) {
  float adjacentMass = 0;
  for (int dr = -1; dr <= 1; dr++) {
    for (int dc = -1; dc <= 1; dc++) {
      if (dc == 0 && dr == 0) continue;
      int nc = col + dc;
      int nr = row + dr;
      if (nc >= 0 && nc < GRID_DIM && nr >= 0 && nr < GRID_DIM) {
        adjacentMass += cellBiomass[nr * GRID_DIM + nc];
      }
    }
  }
  return adjacentMass;
}

// Quench attractant core in trail map around a depleted food nodule
void quenchDepletedNoduleCore(FoodNodule fn) {
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
}

// Update food nodule nutrients, audio parameters, and prune depleted nodules
void updateFoodNodulesAndVoices() {
  for (int i = foodNodes.size() - 1; i >= 0; i--) {
    FoodNodule fn = foodNodes.get(i);
    float loss = fn.grazingBuffer + (passiveDecayRate / 60.0f);
    fn.nutrients -= loss;
    fn.grazingBuffer = 0;

    float adjacentMass = computeMooreAdjacentMass(fn.gridCol, fn.gridRow);
    fn.updateAudioParameters(adjacentMass);

    if (fn.nutrients <= 0.0f || fn.radius <= 2.5f) {
      if (!fn.isDepleted) {
        fn.isDepleted = true;
        quenchDepletedNoduleCore(fn);
      }
      if (!bellAcousticsMode || fn.getBellTotalEnergy() < 0.001f) {
        foodNodes.remove(fn);
      }
    }
  }
}

// Updating grid biomass distributions and voice parameters
void updateGridBiomassAndFood() {
  computeCellBiomass();
  updateFoodNodulesAndVoices();
}
