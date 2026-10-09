# Claude Code Guide - MOLD Bio-Sonification & Simulation

MOLD is an interactive multi-agent slime mold (*Physarum polycephalum*) simulation and real-time bio-sonification engine written in Processing (Java / JOGL) with an accompanying Web Audio / HTML5 Canvas WebApp and hardware MIDI controller integration (Novation Launchpad Mini [MK3], Akai MIDImix).

---

## Essential Commands

### Automated Test Suite
Always run the verification suite before committing any changes:
```bash
./tests/run_tests.sh
```
This suite compiles the transpiled sketch, verifies DSP numerical stability, 3D binaural spatialization, hardware MIDI protocols, simulation bioenergetics, and runs a 300-frame headless smoke test with zero graphical dependencies.

### Performance Benchmarks
```bash
./tests/run_bench.sh
```

### WebApp Script Validation
When editing `index.html` or `WebApp/`:
```bash
node -c WebApp/app.js 2>/dev/null || node -e '
  const fs = require("fs");
  const html = fs.readFileSync("index.html", "utf8");
  const matches = html.match(/<script>([\s\S]*?)<\/script>/gi) || [];
  matches.forEach((tag, idx) => {
    const code = tag.replace(/<\/?script>/gi, "");
    try { new Function(code); }
    catch (e) { console.error(`Syntax error in script tag ${idx}:`, e); process.exit(1); }
  });
  console.log("WebApp inline scripts valid!");
'
```

---

## Core Engineering Invariants

1. **Processing OpenGL (`P2D`/JOGL) Buffer Purity**:
   - Never ping-pong simulation state through `PGraphics` (`loadPixels()` / `updatePixels()` triggers JOGL texture cache nullification and `NullPointerException`).
   - Use dedicated `PImage` (`createImage`) for feeding GLSL shaders via `updatePixels()`.
   - Maintain simulation diffusion and evaporation on CPU primitive arrays (`float[] trailMap`).

2. **OpenGL Thread Affinity & Deferred Execution**:
   - Native OpenGL calls (`beginDraw()`, `endDraw()`, `glClearColor`, shaders) must execute **strictly** on the main render thread inside `draw()`.
   - Never invoke OpenGL from asynchronous MIDI callbacks (`Receiver.send()`) or audio threads (`SIGSEGV` crash).
   - Use the **Deferred Execution Pattern**: callbacks mutate pure CPU variables and set volatile flags (e.g. `pendingReinoculateFboClear = true;`), which `draw()` consumes safely.

3. **Processing PDE Preprocessing Rules**:
   - All `.pde` files are concatenated into a single class extending `PApplet`.
   - **Never declare `settings()` in `.pde` tabs** (causes `Duplicate method settings()` compile error). Place `fullScreen(P2D);` or `size(...)` as the first statement in `setup()`.
   - **No static members in `.pde` tabs**. Place all static classes (e.g. `FastFFT.java`, `PartitionedConvolver.java`) in separate `.java` files.
   - Lifecycle methods (`setup()`, `draw()`, `exit()`) must exist only in `MOLD.pde`.

4. **macOS Display & Windowing Stability**:
   - Never call `surface.setResizable(true);` with OpenGL on macOS (causes unrecoverable AppKit/JOGL deadlock freeze).
   - Zero low-level AWT/AppKit reflection.

5. **Audio DSP Stability & Master Limiting**:
   - Apply algebraic soft-saturation (`tanh` or safe rational limiter) to biquad filter states to prevent `NaN`/`Infinity` blowups under high resonance or fast cutoff modulation.
   - Reverb bio-modulation must have dynamic headroom ceilings to avoid runaway feedback.
   - Master bus must pass through `StudioMasterLimiter` brickwall limiter (`|out| <= 0.92`) to prevent clipping under heavy polyphony.

6. **Hardware MIDI & Trilateral Color Telemetry**:
   - Novation Launchpad Mini [MK3]: 8x8 grid uses Note On/Off (Programmer notes 11..88, Drum Rack pads 36..99); perimeter buttons use Channel 1 CC (top-to-bottom CC 89, 79, 69, 59, 49, 39, 29, 19).
   - Trilateral Color Standard: Colony = Yellow spectrum (`12..15`), Food = Cyan spectrum (`37`), Eating activity = Magenta spectrum (`53`). Hardware toggles must match their respective layer colors.

---

## Available Claude Code Skills

This repository provides 6 specialized skills located in `.claude/skills/`. Invoke them or use them for guidance when working on relevant subsystems:

* `/processing-opengl-sim` (`.claude/skills/processing-opengl-sim/SKILL.md`):
  Guidelines for OpenGL texture buffers, PImage shader pipelines, and CPU agent simulation.
* `/processing-threading-lifecycle` (`.claude/skills/processing-threading-lifecycle/SKILL.md`):
  PDE compilation invariants, JOGL thread affinity, deferred callbacks, and macOS window stability.
* `/realtime-audio-dsp` (`.claude/skills/realtime-audio-dsp/SKILL.md`):
  Real-time bio-sonification, biquad stability, velvet noise reverb, partitioned convolution, and 3D spatialization.
* `/hardware-midi-telemetry` (`.claude/skills/hardware-midi-telemetry/SKILL.md`):
  Launchpad MK3 & MIDImix protocols, batch SysEx RGB lighting, perimeter CCs, and Trilateral Color telemetry.
* `/offline-dsp-verification` (`.claude/skills/offline-dsp-verification/SKILL.md`):
  Headless automated testing with Processing `core.jar`, DSP invariant assertion patterns, and regression testing.
* `/web-audio-sim-porting` (`.claude/skills/web-audio-sim-porting/SKILL.md`):
  Porting simulation and DSP to HTML5 Canvas/Web Audio, tick rate matching, shader-to-CPU scaling, and Web MIDI.
