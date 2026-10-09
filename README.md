# MOLD: Physarum Polycephalum 8×8 Bio-Sonic Synthesizer

An interactive generative bio-simulation and real-time audio synthesizer written in Processing (Java Mode). The system simulates the emergent foraging behavior, chemotaxis, and network formation of the true slime mold (*Physarum polycephalum*), mapping its growth dynamics directly into sound synthesis, spatial stereo panning, and an algorithmic velvet-noise convolution reverberator.

---

## Key Features

- **Emergent Agent Bioenergetics:** Up to 64,000 autonomous slime mold agents on a high-resolution $720 \times 720$ simulation canvas featuring 3-sensor chemotactic navigation, energy consumption (BMR), territory costs, mitosis, and starvation necrosis.
- **GLSL Shading & Texture Pipeline:** Hardware-accelerated GLSL shader (`render.glsl`) with controllable visual sharpness (sigmoid gradient to binary threshold) and interactive motion blur trail decay via offscreen FBOs.
- **Harmonic Scale Tuning Matrix & 3D Spatialization:** 8×8 grid spatial mapping providing customizable musical scales across pitch space, octave shifting (`-1 OCT`, `NORMAL`, `+1 OCT`), and **true 3D binaural spatialization** (inter-aural time/intensity panning, head shadow filtering, and biomass-driven vertical elevation).
- **Zero-Allocation UP-OLA Velvet Noise Convolver:** Algorithmic velvet-noise impulse response generator with a Uniform Partitioned Overlap-Add (UP-OLA) stereo convolver operating with exactly 0 bytes of heap allocation in the audio thread, featuring an 85/15 acoustic cross-bleed matrix.
- **Dynamic Bio-Sonification Telemetry:** Live biological feedback coupling total colony biomass, spatial dispersion spread, and active grazing ratios to reverb wet/dry balance, decay time ($T_{60}$), high-frequency damping, pre-delay, and mitosis-triggered IR reseeding (with dedicated `reverbBioModDepth` scaling).
- **Zorn-Inspired Color Feedback:** Warm visual palette (Yellow Ochre, Vermilion Red, Flake White, Ivory Black) depicting agent arteries, active grazing sites, and nutrient depletion.
- **Dual Hardware MIDI Integration:** Native bi-directional support for Novation Launchpad Mini [MK3] (Programmable & User mode quadrant note mapping, radial ripple wavefronts, SysEx RGB lighting, side button transport, and trilateral LED display layers) and Akai MIDImix (8 audio faders, master speed, bioenergetics knobs, and LED-synced toggles).

---

## Repository Structure

```
MOLD/
├── MOLD.pde                   # Main sketch tab: global configuration, setup(), draw(), exit()
├── Simulation.pde             # Slime mold chemotaxis, trail diffusion, bioenergetics, fast math LUT
├── FoodNodule.pde             # Food nodule entity, nutrient consumption & 3D audio parameters
├── Harmony.pde                # Pitch calculation, scale semitone matrices, octave shifting, tuning cache
├── Render.pde                 # GLSL shader rendering, motion blur FBOs, 3D listener overlay, UI telemetry
├── Controls.pde               # GUI layout, action callbacks, mouse & keyboard inputs
├── UI.pde                     # Zero-dependency immediate-mode UI widget system
├── Midi.pde                   # Hardware MIDI handlers for Launchpad Mini & Akai MIDImix
├── Audio.pde                  # Realtime stereo synthesis engine, Biquad filter, 3D binaural DSP, reverb telemetry
├── FastFFT.java               # In-place Radix-2 Cooley-Tukey FFT & IFFT (zero heap allocation)
├── PartitionedConvolver.java  # Real-time UP-OLA block convolver with true stereo cross-bleed
├── VelvetImpulseGenerator.java# Parametric stereo velvet noise impulse generator
├── data/
│   └── render.glsl            # Hardware GLSL shader for palette mapping and sharpness curves
├── docs/                      # Architectural and technical documentation
│   ├── ARCHITECTURE.md        # Concurrency, data flow, thread boundaries, OpenGL pipeline
│   ├── SIMULATION.md          # Slime mold mathematical model, bioenergetics, fast math LUTs
│   ├── AUDIO.md               # Sound synthesis, biquad filter, 3D spatialization, UP-OLA convolver
│   ├── MIDI.md                # MIDI mappings, controller layouts, LED protocols, radial ripples
│   └── specs/                 # Hardware & DSP technical specifications
└── tests/                     # Offline test suites & verification scripts
    ├── ConvolverVerificationTest.java       # Real-time UP-OLA mathematical acceptance criteria
    ├── MoldAudioStabilityTest.java          # Biquad filter stability, master limiter, tuning range
    ├── MoldMidiControllerTest.java          # MIDImix & Launchpad protocol fuzzing, ripple & RGB tests
    ├── MoldReverbModTest.java               # Bio-telemetry scaling, defaults, and routing
    ├── MoldSimulationInvariantsTest.java    # Agent spatial bounds, diffusion conservation, mitosis
    ├── MoldStereoSpatializationTest.java    # 3D binaural spatialization & true stereo energy ratios
    ├── MoldHeadlessSmokeTest.java           # 300-frame continuous simulation headless smoke run
    └── run_tests.sh                         # Unified test runner script
```

---

## Getting Started

### Prerequisites

- **Processing 4.x** (Tested on Processing 4.5.7).
- OpenGL / P2D hardware acceleration.
- No external Processing libraries or ControlP5 dependencies required (uses built-in `javax.sound.sampled` and `javax.sound.midi`).

### Running the Sketch

1. Open `MOLD.pde` in the Processing IDE.
2. Ensure all related `.pde` and `.java` files are located in the sketch root folder, and `render.glsl` is in `data/`.
3. Click the **Run** button (or press `Cmd+R` / `Ctrl+R`).

### Controls Quick Reference

- **Left-Click (Canvas):** Deposit a new oat food nodule at cursor location (triggers radial LED ripple if Launchpad connected).
- **F / ESC:** Toggle borderless fullscreen display.
- **Sidebar GUI:** Adjust simulation speed, octave transposition, tuning, Biquad filter Q/sensitivity, convolver parameters, bioenergetic coefficients, and GLSL visual sharpness/motion blur.
- **Hardware Controls:**
  - **Launchpad Mini [MK3]:** 8×8 grid drops oat nodules; side buttons trigger Re-Inoculate (`CC 89`), Clear Food (`CC 79`), and toggle LED display layers for Mold (`CC 39`), Food (`CC 29`), and Eating (`CC 19`).
  - **Akai MIDImix:** Faders 1-8 adjust nodule voice levels; Master fader controls simulation speed; top knobs adjust filter cutoff/resonance, bioenergetics, and reverb parameters; Mute/Rec buttons toggle states with hardware LED sync.

---

## Testing & Verification

An extensive offline test suite validates the entire codebase against strict DSP, mathematical, MIDI, and simulation invariants:
- **Convolver Verification:** Zero heap allocation across 10,000 blocks, cross-correlation $\rho_{LR} < 0.05$, energy decay slope $-60\text{ dB} \pm 1.5\text{ dB}$, algorithmic latency $\le 512$ samples.
- **3D Audio & Binaural:** Inter-aural time and intensity panning, head shadow filtering, and vertical elevation mapping.
- **Reverb Bio-Modulation:** Telemetry depth scaling and parameter bounding.
- **Simulation Invariants:** Toroidal boundary constraints, diffusion non-negativity, energy conservation, and mitosis bounds.
- **MIDI Controllers & Telemetry:** Launchpad Programmer/Drum Rack modes, SysEx RGB protocol, ripple propagation, and malformed packet fuzz resilience.
- **Headless Smoke Test:** 300 continuous simulation and parameter update frames without crashes or NaNs.

To run the offline test suite:

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

---

## Documentation

Comprehensive conceptual and mathematical documentation is located in the `docs/` directory:

1. [docs/SIMULATION.md](docs/SIMULATION.md): Mathematical equations for 3-sensor chemotaxis, trail diffusion convolution, bioenergetics, fast math LUTs, and agent bounds.
2. [docs/AUDIO.md](docs/AUDIO.md): Synthesis architecture, 3D binaural spatialization, Moore-neighborhood VCA drive, UP-OLA partitioned convolution, and dynamics limiting.
3. [docs/MIDI.md](docs/MIDI.md): Akai MIDImix and Novation Launchpad Mini MIDI specifications, mapping tables, radial ripples, and trilateral LED protocols.
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Multi-threaded lifecycle, OpenGL thread affinity, thread safety, and data flow.
