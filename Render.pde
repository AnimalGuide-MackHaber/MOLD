// =============================================================================
// Render.pde - Discrete Pixel Drawing, Overlays, and UI Status Header
// =============================================================================

// Rendering discrete non-glowing pixels to offscreen frame
void renderCrispPixels() {
  offscreenFrame.loadPixels();
  int[] px = offscreenFrame.pixels;

  int cBg, cAtrophy, cMargin, cSheet, cArtery;
  if (paletteIdx == 0) { // Yellow (Zorn-inspired warm ochre)
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
}

// Drawing food nodules with shrinking cores and labels
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

// Drawing sidebar status header and widget panel
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
  text("FPS: " + round(frameRate) + "  |  POP: " + activeAgentCount + "  |  OATS: " + foodNodes.size(), x + 12, y + 26);
  String midiStatus;
  if (!midiHandler.isReady()) midiStatus = "NO OUTPUT PORT";
  else midiStatus = midiEnabled ? (midiHandler.inputIsMidimix ? "MIDIMIX LINKED" : "PROGRAMMER MODE") : "LIVE MODE (LINK OFF)";
  text("MIDI: " + midiStatus, x + 12, y + 38);

  ui.draw();
}
