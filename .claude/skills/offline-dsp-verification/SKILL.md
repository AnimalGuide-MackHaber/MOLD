---
name: offline-dsp-verification
description: >-
  Use this skill when creating automated offline tests, headless DSP verification suites,
  regression testing, or continuous integration for Processing and Java audio/simulation code.
---

# Offline DSP & Headless Simulation Verification Guide

This skill defines the methodology for validating real-time audio DSP, complex agent simulations, and hardware MIDI logic headlessly, without requiring an active graphical display or physical hardware peripherals.

---

## 1. Architecture of Headless Processing Testing

Processing sketches depend heavily on `PApplet` and `PImage`. However, launching a GUI window in automated test environments or CI runners is slow and often fails due to missing display servers (X11 / Wayland / AppKit).

### The Headless Transpilation Pipeline
1. **Transpile `.pde` Tabs to Java (`tests/pde_to_java.py`)**:
   Flattens all `.pde` tabs in the sketch folder into an inner class of a top-level Java class (`MoldSketch.java`), stripping or stubbing GUI-dependent calls where appropriate.
2. **Compile with Processing `core.jar`**:
   Compile the transpiled sketch, static DSP classes (`FastFFT.java`, `PartitionedConvolver.java`, `VelvetImpulseGenerator.java`), and test classes using the JDK:
   ```bash
   javac -nowarn -d tests/build/bench -cp "$CORE_JAR" \
     tests/build/gen/MoldSketch.java FastFFT.java PartitionedConvolver.java VelvetImpulseGenerator.java tests/MoldTestUtils.java tests/*.java
   ```
3. **Execute Headlessly**:
   Run tests with `-Djava.awt.headless=true`:
   ```bash
   java -Djava.awt.headless=true -cp "tests/build/bench:$CORE_JAR" MoldAudioStabilityTest
   ```

---

## 2. Invariant Verification Design Patterns

Effective offline tests assert mathematical and system invariants rather than brittle pixel comparisons:

### A. DSP Numerical Stability & Saturation Sweeps
Never assume a filter or reverb is stable based on one test tone. Sweep through combinations:
* Sweep cutoff frequencies from `20 Hz` to `20 kHz` across resonance values ($Q = 0.5$ to $18.0$).
* Feed impulse spikes, Nyquist tones, and extreme DC offsets.
* Assert:
  1. `!Float.isNaN(sample)`
  2. `!Float.isInfinite(sample)`
  3. `Math.abs(sample) <= saturationCeiling`

### B. Master Limiter Brickwall Verification Under Overload
* Feed a continuous +36 dBFS sine wave (amplitude = 64.0) into the master limiter.
* Assert that every output sample remains strictly within `[-0.92, +0.92]`.
* Assert that upon cessation of the overload tone, the gain envelope recovers smoothly to 1.0 without lingering distortion.

### C. Simulation Bioenergetics & Spatial Conservation
* **Spatial Invariant**: Assert that all $N$ agents remain strictly within $[0, \text{width}) \times [0, \text{height})$ across 300+ simulation frames.
* **Non-Negativity Invariant**: Assert that chemical concentrations across `trailMap` are strictly $\ge 0.0$.
* **Conservation/Decay Invariant**: In an isolated grid with no agents or food, assert that total grid chemical energy decreases monotonically per step according to the evaporation factor.

### D. Concurrency & Asynchronous Reset Safety
* Spawn background threads calling simulation updates while triggering asynchronous reset actions (`reinoculate()`).
* Assert that state resets complete cleanly without `ConcurrentModificationException`, array index out of bounds, or memory corruption.

### E. MIDI Parser Fuzz Testing
* Generate 500+ random byte sequences (interleaved status bytes, truncated payloads, values $> 127$).
* Stream them into the MIDI receiver.
* Assert that the system handles all fuzzed messages gracefully without throwing uncaught exceptions or corrupting parameter state.

---

## 3. Running the Test Suite

Run the full verification suite before committing any code:
```bash
./tests/run_tests.sh
```

A passing suite produces:
```text
>> ALL REVERB BIO-MODULATION & MIDI ROUTING TESTS PASSED! <<
>> ALL 3D BINAURAL & STEREO SPATIALIZATION TESTS PASSED! <<
>> ALL HARDWARE MIDI CONTROLLER & TELEMETRY TESTS PASSED! <<
>> ALL SIMULATION & BIOENERGETICS INVARIANTS PASSED! <<
>> ALL AUDIO STABILITY & DSP INVARIANTS PASSED! <<
>> ALL HEADLESS INTEGRATION & SMOKE TESTS PASSED! <<
```

---

## 4. Verification Checklist

When adding new features or fixing bugs:
- [ ] Has an automated unit or invariant test been added to `tests/`?
- [ ] Does `./tests/run_tests.sh` pass cleanly with exit code 0?
- [ ] Are all new test assertions deterministic (zero dependence on wall-clock timing or audio hardware availability)?
