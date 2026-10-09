# Antigravity Agents Guide - MOLD Bio-Sonification & Simulation

This repository contains multi-agent simulation, real-time spatialized audio synthesis, and hardware MIDI telemetry systems.

---

## Workspace Skills

The repository defines 6 specialized skills located in `.agents/skills/` (and mirrored in `.agent/skills/` and `.claude/skills/`). The Antigravity agent progressively activates these skills when relevant:

1. **`processing-opengl-sim`** (`.agents/skills/processing-opengl-sim/SKILL.md`):
   Processing OpenGL (P2D/P3D), offscreen texture handling, GLSL shader feeding via `PImage`, and CPU diffusion-decay grids.
2. **`processing-threading-lifecycle`** (`.agents/skills/processing-threading-lifecycle/SKILL.md`):
   Processing PDE compilation invariants, JOGL thread affinity, asynchronous callback deferral, and macOS display stability.
3. **`realtime-audio-dsp`** (`.agents/skills/realtime-audio-dsp/SKILL.md`):
   Real-time bio-sonification, biquad filter numerical stability, algorithmic velvet noise reverb, partitioned convolution, and master limiting.
4. **`hardware-midi-telemetry`** (`.agents/skills/hardware-midi-telemetry/SKILL.md`):
   Hardware MIDI controller protocols (Novation Launchpad Mini MK3, Akai MIDImix), batch SysEx RGB lighting, perimeter CCs, and Trilateral Color Telemetry.
5. **`offline-dsp-verification`** (`.agents/skills/offline-dsp-verification/SKILL.md`):
   Headless automated testing with Processing `core.jar`, DSP invariant assertions, and regression testing without hardware dependencies.
6. **`web-audio-sim-porting`** (`.agents/skills/web-audio-sim-porting/SKILL.md`):
   Porting simulation and DSP to HTML5 Canvas/Web Audio, tick rate matching, shader-to-CPU scaling, and Web MIDI.

---

## Verification Commands

Always run the offline verification suite before committing any changes:
```bash
./tests/run_tests.sh
```

To run performance benchmarks:
```bash
./tests/run_bench.sh
```

---

## Engineering Guidelines
Refer to `GEMINI.md` for in-depth technical rules regarding Processing OpenGL texture buffers, thread safety, audio limiter calibration, and hardware MIDI telemetry standards.
