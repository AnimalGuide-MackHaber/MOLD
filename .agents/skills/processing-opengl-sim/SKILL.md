---
name: processing-opengl-sim
description: >-
  Use this skill when developing or modifying Processing OpenGL (P2D/P3D) simulations,
  agent-based models (Physarum polycephalum, slime mold), PImage texture pipelines,
  GLSL shader integration, or CPU diffusion-decay grids.
---

# Processing OpenGL Simulation & Texture Pipeline Guide

This skill governs best practices, memory architectures, and critical OpenGL invariants when building real-time agent simulations (such as *Physarum polycephalum* / slime mold) and feeding simulation buffers into GLSL shaders in Processing (Java / JOGL).

---

## 1. PGraphics vs PImage Buffer Architecture

### The Critical JOGL Pitfall
In Processing 4 (`P2D` / `P3D` / JOGL), **never ping-pong simulation state through `PGraphics`** with `loadPixels()` and `updatePixels()`.

```java
// CRITICAL ERROR: JOGL texture cache desynchronization
PGraphics pg = createGraphics(w, h, P2D);
pg.beginDraw();
// ...
pg.loadPixels();
pg.pixels[i] = ...; // DANGER: After render/cache init, pg.pixels may be null!
pg.updatePixels();
pg.endDraw();
```
* **Why it fails**: In Processing 4, rendering an offscreen `PGraphics` FBO via `image(pg, ...)` or shader binding synchronizes its underlying OpenGL texture cache. If `pg.pixels` is null during texture cache recreation or if an internal readback fails, Processing forcibly nulls `pg.pixels`, throwing a fatal `NullPointerException` on subsequent frame readbacks.

### The Correct Architecture: Dedicated CPU `PImage`
When simulation buffers (such as chemical trail maps or height maps) need to feed GLSL shaders, allocate a dedicated `PImage`:

```java
PImage trailTexture = createImage(simWidth, simHeight, ARGB);
```

* **Why it works**: A standard `PImage.pixels` is a permanent CPU `int[]` array managed entirely by Java heap memory. Processing and JOGL **never** clear `PImage.pixels` to null.
* **Stream per frame**:
  ```java
  // In draw() or render loop:
  trailTexture.loadPixels();
  for (int i = 0; i < totalPixels; i++) {
    float val = trailMap[i];
    // Map scalar simulation float into RGBA texture
    int c = (int)(constrain(val * 255.0f, 0, 255));
    trailTexture.pixels[i] = (255 << 24) | (c << 16) | (c << 8) | c;
  }
  trailTexture.updatePixels();

  // Pass to shader safely:
  shader.set("u_trailTexture", trailTexture);
  ```

---

## 2. Keep Simulation Hot Paths on CPU

For simulation grids up to ~720x720 (and up to 64,000+ agents):
* **Do not use GPU ping-pong compute shaders with `glReadPixels`**: Reading GPU framebuffers back to CPU memory stalls the graphics pipeline, collapsing frame rates from 60 FPS to under 15 FPS.
* **Maintain twin 1D primitive float arrays on CPU**:
  ```java
  float[] trailMap = new float[GRID_W * GRID_H];
  float[] nextTrailMap = new float[GRID_W * GRID_H];
  ```
* **Benefits**:
  1. Guaranteed 60+ FPS without GPU readback stalls.
  2. Zero driver-specific GLSL compute shader compatibility issues.
  3. Fully deterministic, headless unit testability without an active OpenGL display.

---

## 3. Fast CPU Diffusion & Evaporation Convolution

Perform 3x3 diffusion and evaporation in a single cache-friendly pass with toroidal boundary wrapping:

```java
void diffuseAndEvaporate(float decayFactor, float diffuseRate) {
  float centerWeight = 1.0f - diffuseRate;
  float neighborWeight = diffuseRate / 8.0f;

  for (int y = 0; y < simHeight; y++) {
    int yPrev = (y == 0 ? simHeight - 1 : y - 1) * simWidth;
    int yCurr = y * simWidth;
    int yNext = (y == simHeight - 1 ? 0 : y + 1) * simWidth;

    for (int x = 0; x < simWidth; x++) {
      int xPrev = (x == 0 ? simWidth - 1 : x - 1);
      int xNext = (x == simWidth - 1 ? 0 : x + 1);

      float sum = trailMap[xPrev + yPrev] + trailMap[x + yPrev] + trailMap[xNext + yPrev]
                + trailMap[xPrev + yCurr]                         + trailMap[xNext + yCurr]
                + trailMap[xPrev + yNext] + trailMap[x + yNext] + trailMap[xNext + yNext];

      float diffused = trailMap[x + yCurr] * centerWeight + sum * neighborWeight;
      nextTrailMap[x + yCurr] = diffused * decayFactor;
    }
  }

  // Swap buffers
  float[] temp = trailMap;
  trailMap = nextTrailMap;
  nextTrailMap = temp;
}
```

---

## 4. Agent Sensory Steering & Bioenergetics

In *Physarum* models, agents steer by sampling chemical concentrations ahead of them:
1. **Three Receptors**: Forward (`SO`), Front-Left (`FL`), and Front-Right (`FR`) positioned at `sensorAngle` and `sensorDist`.
2. **Toroidal Coordinate Evaluation**: Always wrap sensor coordinates defensively:
   ```java
   float sampleChemo(float x, float y) {
     int ix = (int) x;
     int iy = (int) y;
     ix = (ix % simWidth + simWidth) % simWidth;
     iy = (iy % simHeight + simHeight) % simHeight;
     return trailMap[ix + iy * simWidth];
   }
   ```
3. **Steering Logic**:
   - If `SO > FL` and `SO > FR`: continue forward.
   - If `FL > FR`: turn left by `turnAngle`.
   - If `FR > FL`: turn right by `turnAngle`.
   - If `FL == FR`: randomize turn or stay straight.
4. **Deposit & Mitosis**:
   - Deposit chemical concentration at current `(x, y)`.
   - Track energy/biomass: increase when consuming nutrients, decay per step.
   - If energy exceeds mitosis threshold, divide up to `MAX_AGENTS`. If energy drops to zero, mark agent dead.

---

## 5. Entity Lifecycle & Audio-Visual Decoupling

In audio-visual simulations where entities (e.g., food nodules, oscillators) have extended acoustic decays (ringing bell modes, reverb tails, release envelopes):
1. **Lifecycle Decoupling**:
   - The entity may remain in the active entity list (`foodNodes`) so the audio thread can finish processing decay tails.
   - The visual rendering pipeline (`drawSingleFoodNodule`) must immediately return early if `entity.isDepleted`:
     ```java
     if (fn.isDepleted) {
       return; // Immediately omit visual geometry; do not draw ghost rings
     }
     ```
2. **Preventing Ghost Guide Outlines**:
   - Avoid rendering fixed initial-capacity bounding rings (`rMax`). Render only dynamic active physical state (`rCur`, pulse, elevation).

---

## 6. Verification Checklist

Before committing simulation changes:
- [ ] Are simulation buffers allocated on CPU (`float[]`) rather than ping-pong `PGraphics`?
- [ ] Is GLSL texture feeding handled via `PImage.createImage` + `updatePixels()`?
- [ ] Are all coordinate evaluations protected with toroidal or clamped modulo wrapping?
- [ ] Are depleted entities immediately omitted from visual rendering to prevent ghost rings during audio decay tails?
- [ ] Has `./tests/run_tests.sh` passed `MoldSimulationInvariantsTest`?
