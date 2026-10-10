---
name: web-audio-sim-porting
description: >-
  Use this skill when porting Processing or native Java simulation and audio engines
  to HTML5 Canvas, WebGL, Web Audio API, or maintaining cross-platform parity with WebApp.
---

# Web Audio & Simulation Porting Guide

This skill governs parity, mathematical conversions, and safety checks when porting native desktop Processing/Java simulation and DSP systems to the browser via HTML5 Canvas, Web Audio API, and Web MIDI.

---

## 1. Shader to CPU Value Scaling

In native Processing OpenGL, visual post-processing shaders operate on normalized float color channels in the range `[0.0, 1.0]`. When porting trail decay or brightness thresholding to a CPU pixel buffer (`ImageData.data` or `Uint32Array`):

* **The Scaling Trap**: A GLSL shader threshold of `0.005` corresponds to:
  $$\text{CPU Threshold} = 0.005 \times 255 = 1.275$$
* **The Error**: Setting an arbitrary CPU cutoff (e.g. `0.15`) prevents low-intensity chemical trails from ever evaporating completely, resulting in massive, lingering screen-wide "blooms".
* **The Rule**: Always scale normalized shader constants by $255.0$ when evaluating integer CPU pixel arrays.

---

## 2. Simulation Tick Rate Synchronization

In Processing desktop, the `draw()` loop advances simulation frames using a speed accumulator:
```java
speedAccumulator += simSpeed * 0.4f;
while (speedAccumulator >= 1.0f) {
  stepSimulation();
  speedAccumulator -= 1.0f;
}
```

* **WebApp Parity**: The WebApp's `requestAnimationFrame` loop must use the exact same accumulator multiplier:
  ```javascript
  speedAccumulator += CONFIG.simSpeed * 0.4;
  while (speedAccumulator >= 1.0) {
    stepSimulation();
    speedAccumulator -= 1.0;
  }
  ```
* Using a different multiplier (e.g., `0.1` or `1.0`) causes the web colony to behave sluggishly or hyperactively compared to the native desktop experience.

---

## 3. Harmonic Grid Frequency Math

When mapping an 8x8 spatial grid to musical pitches:
* **Octave Stacking**: The musical grid shifts one octave every *two* rows:
  ```javascript
  const octaveShift = Math.floor(invertedRow / 2);
  ```
* **Baseline Octave Anchor**:
  Always anchor the base octave at `baseOctave = 1` relative to the A1 (55 Hz) root frequency.
  - Setting `baseOctave = 0` causes sub-audible low rumble.
  - Omitting the anchor or using `baseOctave >= 3` shifts the upper grid rows into ultrasonic (>20 kHz) frequencies, stressing audio hardware and producing digital aliasing artifacts.

---

## 4. Web Audio Algorithmic Reverb & 3D Spatialization

To achieve parity with native desktop Velvet Noise Reverb and 3D binaural spatialization:
1. **Velvet Noise Impulse Generation**:
   Generate synthetic sparse ternary impulses ($\pm 1$, $0$) directly into an `AudioBuffer`, and load it into a Web Audio `ConvolverNode`.
2. **HRTF Spatialization**:
   Use `PannerNode` configured with `panningModel = 'HRTF'` and `distanceModel = 'inverse'`.
3. **Equal-Power Pan**:
   When using stereophonic panning without full HRTF:
   ```javascript
   const pan = (nodeX / canvasWidth) * 2 - 1; // [-1.0, 1.0]
   stereoPannerNode.pan.setValueAtTime(pan, audioCtx.currentTime);
   ```

---

## 5. Web MIDI API & Telemetry

1. **Permissions & Sysex**:
   Always request MIDI access with `sysex: true`:
   ```javascript
   navigator.requestMIDIAccess({ sysex: true }).then(onMidiSuccess, onMidiFailure);
   ```
2. **Event Handling**:
   Handle device plug/unplug events dynamically via `midiAccess.onstatechange`.

---

## 6. Modular Architecture & Script Verification Safety

1. **Subsystem File Decomposition**:
   Decompose the web application across dedicated, modular files:
   - `css/styles.css`: Visual styling, canvas crisp pixelation, and transitions.
   - `js/config.js`: Configuration state (`CONFIG`), musical scale matrices, and Simpson bell acoustic tuning ratios.
   - `js/audio.js`: Web Audio context lifecycle, `FoodAudioVoice` synthesizer, and algorithmic velvet noise reverb.
   - `js/simulation.js`: `Agent` and `FoodNodule` data models, Moore neighborhood biomass evaluation.
   - `js/midi.js`: Web MIDI endpoints, Launchpad MK3 batch SysEx RGB telemetry, and MIDImix CC bindings.
   - `js/sketch.js`: Encapsulate the `p5.js` instance (`new p5((p) => { ... })`) handling canvas resizing, CPU trail decay, and pixel array streaming.
   - `js/ui.js`: DOM event listeners, slider bindings, and accordion toggles.

2. **Automated Syntax & Shared Global Scope Check**:
   Before committing, verify all modular JS files with `node -c js/*.js` and run a shared-context global script evaluation (`vm.runInThisContext`) to ensure inter-module variables and functions resolve cleanly without reference errors:
   ```bash
   node -c js/*.js
   node -e '
     const fs = require("fs");
     const vm = require("vm");
     global.window = global;
     global.document = { getElementById: () => ({ addEventListener: ()=>{}, classList: { add: ()=>{}, remove: ()=>{} }, innerText: "", value: "0" }), querySelectorAll: () => [] };
     global.navigator = { requestMIDIAccess: false };
     global.p5 = function(fn) { fn({ createCanvas: ()=>({ parent: ()=>{} }), pixelDensity: ()=>{}, noSmooth: ()=>{}, createImage: () => ({ pixels: new Uint8ClampedArray(256*256*4), updatePixels: ()=>{} }), color: ()=>({ levels: [0,0,0,0] }), resizeCanvas: ()=>{} }); };
     global.ResizeObserver = class { observe(){} };
     ["config.js", "audio.js", "simulation.js", "midi.js", "sketch.js", "ui.js"].forEach(f => {
       vm.runInThisContext(fs.readFileSync("js/" + f, "utf8"), { filename: f });
     });
     console.log("All modular scripts loaded and verified!");
   '
   ```

3. **Root and Subdirectory Mirroring**:
   Always mirror modifications across both `./index.html` (with `./js/` and `./css/`) and `./WebApp/index.html` (with `./WebApp/js/` and `./WebApp/css/`).

4. **Event Listener Attachment**:
   Ensure all dynamically created buttons and dropdowns have explicit `addEventListener` bindings attached after creation.

---

## 7. Verification Checklist

Before committing WebApp changes:
- [ ] Do CPU trail evaporation cutoffs match the shader scale ($0.005 \times 255 = 1.275$)?
- [ ] Does `speedAccumulator` increment at `CONFIG.simSpeed * 0.4`?
- [ ] Does harmonic grid math calculate `Math.floor(invertedRow / 2)` anchored at `baseOctave = 1`?
- [ ] Have all modular JS files passed syntax validation (`node -c js/*.js`) and global scope load checks?
- [ ] Are `./index.html` (root) and `./WebApp/index.html` completely in sync?
- [ ] Does Web MIDI launch cleanly in supported browsers?
