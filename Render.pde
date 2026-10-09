// =============================================================================
// Render.pde - Discrete Pixel Drawing, Overlays, and UI Status Header
// =============================================================================

// Rendering discrete non-glowing pixels to screen via GPU Shader
void renderCrispPixels() {
  int[] px = trailTexture.pixels;
  for (int i = 0; i < trailMap.length; i++) {
    int val = (int) min(255.0f, trailMap[i]);
    px[i] = (255 << 24) | (val << 16);
  }
  trailTexture.updatePixels();

  renderShader.set("visualSharpness", visualSharpness);
  renderShader.set("paletteIdx", paletteIdx);
  
  renderFBO.beginDraw();
  renderFBO.clear();
  renderFBO.shader(renderShader);
  renderFBO.image(trailTexture, 0, 0);
  renderFBO.resetShader();
  renderFBO.endDraw();
  
  motionBlurFBO.beginDraw();
  
  int fadeAlpha = (int) map(visualBlur, 0.0f, 8.0f, 255f, 5f);
  motionBlurFBO.noStroke();
  
  // Background color changes slightly by palette
  if (paletteIdx == 2) motionBlurFBO.fill(5, 8, 12, fadeAlpha);
  else motionBlurFBO.fill(6, 7, 10, fadeAlpha);
  
  motionBlurFBO.rect(0, 0, SIM_W, SIM_H);
  
  motionBlurFBO.image(renderFBO, 0, 0);
  motionBlurFBO.endDraw();
  
  image(motionBlurFBO, canvasX, canvasY, canvasS, canvasS);
}

// Drawing harmonic pitch overlay over 8x8 grid
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

  // Draw 3D Binaural Virtual Listener (positioned at grid center)
  float lx = ox + w * 0.5f;
  float ly = oy + h * 0.5f;
  pushStyle();
  // Listener Head
  noFill();
  stroke(UI_CYAN, 180);
  strokeWeight(1.5f);
  ellipse(lx, ly, 16, 16);
  // Nose pointing forward (upward towards rows 0-3)
  fill(UI_CYAN, 200);
  noStroke();
  triangle(lx - 3, ly - 7, lx + 3, ly - 7, lx, ly - 12);
  // Left and Right Ears
  stroke(UI_CYAN, 220);
  strokeWeight(2);
  line(lx - 9, ly - 3, lx - 9, ly + 3);
  line(lx + 9, ly - 3, lx + 9, ly + 3);
  // Subtle orientation label
  textAlign(CENTER, TOP);
  textSize(8);
  fill(UI_CYAN, 160);
  text("LISTENER (3D)", lx, ly + 11);
  popStyle();
}

// Drawing a single food nodule with core, halos, and text labels
void drawSingleFoodNodule(FoodNodule fn, float scaleX, float scaleY, float ox, float oy) {
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

  // 3D Biomass Elevation Ring (lifts visually with mold mass height)
  if (fn.elevationNorm > 0.02f) {
    pushStyle();
    noFill();
    stroke(UI_CYAN, 70 + (120 * fn.elevationNorm));
    strokeWeight(1.2f);
    float elevOffset = fn.elevationNorm * 10.0f * scaleY;
    ellipse(cx, cy - elevOffset, (rCur + 6) * 2, (rCur + 3) * 2);
    popStyle();
  }

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

// Drawing food nodules with shrinking cores, labels, and 3D biomass elevation halos
void drawFoodNodules(float ox, float oy, float w, float h) {
  float scaleX = w / SIM_W;
  float scaleY = h / SIM_H;

  for (FoodNodule fn : foodNodes) {
    drawSingleFoodNodule(fn, scaleX, scaleY, ox, oy);
  }
}

// Drawing status metrics telemetry header
void drawSidebarTelemetry(float x, float y) {
  fill(250, 204, 21);
  textAlign(LEFT, TOP);
  textSize(12);
  text("PHYSARUM BIO-SONIC ENGINE", x + 12, y + 10);
  fill(161, 161, 170);
  textSize(10);
  text("FPS: " + round(frameRate) + "  |  POP: " + activeAgentCount + "  |  OATS: " + foodNodes.size(), x + 12, y + 26);
  String midiStatus;
  if (!midiHandler.isReady()) midiStatus = "NO OUTPUT PORT";
  else midiStatus = midiEnabled ? (midiHandler.inputIsMidimix ? "MIDIMIX LINKED" : "PROGRAMMER MODE") : "LIVE MODE (LINK OFF)";
  text("MIDI: " + midiStatus, x + 12, y + 38);
}

// Drawing sidebar status header and widget panel
void drawSidebarGUI(float x, float y, float w, float h) {
  fill(18, 20, 26);
  stroke(39, 39, 42);
  strokeWeight(1);
  rect(x, y, w, h, 6);

  drawSidebarTelemetry(x, y);

  ui.draw();
}
