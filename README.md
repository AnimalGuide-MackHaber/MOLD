# MOLD: Physarum Polycephalum 8×8 Bio-Sonic Synthesizer

An interactive generative bio-simulation and real-time audio synthesizer written in Processing (Java Mode). The system simulates the emergent foraging behavior, chemotaxis, and network formation of the true slime mold (*Physarum polycephalum*), mapping its growth dynamics directly into sound synthesis, spatial stereo panning, and an algorithmic velvet-noise convolution reverberator.

---

## Key Features

- **Emergent Agent Bioenergetics:** Up to 25,000 autonomous slime mold agents featuring 3-sensor chemotactic navigation, energy consumption (BMR), territory costs, mitosis, and starvation necrosis.
- **Harmonic Scale Tuning Matrix:** 8×8 grid spatial mapping providing customizable musical scales (Major/Minor Pentatonic, Lydian, Dorian, Hirajoshi, Just Intonation) across pitch space.
- **Zero-Allocation UP-OLA Velvet Noise Convolver:** Algorithmic velvet-noise impulse response generator with a Uniform Partitioned Overlap-Add (UP-OLA) stereo convolver operating with exactly 0 bytes of heap allocation in the audio thread.
- **Biometric Audio Telemetry:** Live biological feedback coupling total colony biomass to reverb wet/dry balance, locomotion expenditure to high-frequency damping, arterial reach to pre-delay, and mitosis explosions to impulse response regeneration.
- **Zorn-Inspired Color Feedback:** Warm visual palette (Yellow Ochre, Vermilion Red, Flake White, Ivory Black) depicting agent arteries, active grazing sites, and nutrient depletion.
- **Dual Hardware MIDI Integration:** Native bi-directional support for Novation Launchpad Mini [MK3] (pad dropping & RGB telemetry) and Akai MIDImix (8 audio faders, simulation speed master, bioenergetics knobs, and LED-synced toggles).

---

## Repository Structure

```
MOLD/
├── MOLD.pde                   # Main sketch tab: global configuration, setup(), draw(), exit()
├── Simulation.pde             # Slime mold chemotaxis, trail diffusion, bioenergetics
├── FoodNodule.pde             # Food nodule entity, nutrient consumption & audio parameters
├── Harmony.pde                # Pitch calculation, scale semitone matrices, tuning cache
├── Render.pde                 # Discrete pixel rendering, grid overlays, UI status bar
├── Controls.pde               # GUI layout, action callbacks, mouse & keyboard inputs
├── UI.pde                     # Zero-dependency immediate-mode UI widget system
├── Midi.pde                   # Hardware MIDI handlers for Launchpad Mini & Akai MIDImix
├── Audio.pde                  # Realtime stereo synthesis engine, Biquad filter, reverb telemetry
├── FastFFT.java               # In-place Radix-2 Cooley-Tukey FFT & IFFT (zero heap allocation)
├── PartitionedConvolver.java  # Real-time UP-OLA block convolver (zero heap allocation)
├── VelvetImpulseGenerator.java# Parametric stereo velvet noise impulse generator
├── docs/                      # Architectural and technical documentation
│   ├── ARCHITECTURE.md        # Concurrency, data flow, thread boundaries
│   ├── SIMULATION.md          # Slime mold mathematical model & bioenergetics
│   ├── AUDIO.md               # Sound synthesis, biquad filter, UP-OLA convolver
│   ├── MIDI.md                # MIDI mappings, controller layouts, LED protocols
│   └── specs/                 # Hardware & DSP technical specifications
└── tests/                     # Offline test suites & verification scripts
    ├── ConvolverVerificationTest.java
    └── run_tests.sh
```

---

## Getting Started

### Prerequisites

- **Processing 4.x** (Tested on Processing 4.5.7).
- No external Processing libraries or ControlP5 dependencies required (uses built-in `javax.sound.sampled` and `javax.sound.midi`).

### Running the Sketch

1. Open `MOLD.pde` in the Processing IDE.
2. Ensure all related `.pde` and `.java` files are located in the sketch root folder.
3. Click the **Run** button (or press `Cmd+R` / `Ctrl+R`).

### Controls Quick Reference

- **Left-Click (Canvas):** Deposit a new oat food nodule at cursor location.
- **F / ESC:** Toggle borderless fullscreen display.
- **Sidebar GUI:** Adjust simulation speed, tuning, Biquad filter Q/sensitivity, convolver parameters, and bioenergetic coefficients.

---

## Testing & Verification

An automated offline verification test suite validates the UP-OLA convolution engine against strict real-time DSP constraints (zero heap allocation across 10,000 blocks, cross-correlation $\rho_{LR} < 0.05$, energy decay slope $-60\text{ dB} \pm 1.5\text{ dB}$, and spectral flatness).

To run the offline test suite:

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

---

## Documentation

Comprehensive conceptual and mathematical documentation is located in the `docs/` directory:

1. [docs/SIMULATION.md](docs/SIMULATION.md): Mathematical equations for 3-sensor chemotaxis, trail diffusion convolution, and agent bioenergetics.
2. [docs/AUDIO.md](docs/AUDIO.md): Synthesis architecture, Moore-neighborhood VCA drive, UP-OLA partitioned convolution, and dynamics limiting.
3. [docs/MIDI.md](docs/MIDI.md): Akai MIDImix and Novation Launchpad Mini MIDI specifications, mapping tables, and LED protocols.
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Multi-threaded lifecycle, thread safety, and data flow.
