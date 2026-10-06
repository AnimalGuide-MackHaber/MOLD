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

// Scattering randomized initial food reserves
void scatterInitialFood(int count) {
  for (int i = 0; i < count; i++) {
    float x = random(40, SIM_W - 40);
    float y = random(40, SIM_H - 40);
    addFoodNodule(x, y, 16.0f, 550.0f);
  }
}

// Sampling chemoattractant trail with bilinear interpolation
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

// Executing bioenergetics, chemotaxis, and cellular division
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

// Diffusing trail map and evaporating old paths
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

// Updating grid biomass distributions and voice parameters
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
