# Processing OpenGL, Simulation & Real-Time Synthesis Guidelines

## 1. Processing OpenGL (`PGraphicsOpenGL`) Texture & Pixel Buffers
- **Never Ping-Pong Simulation State Through `PGraphics`**: Do not use offscreen `PGraphics` with `loadPixels()` / `updatePixels()` as simulation buffers. In Processing 4 (JOGL), rendering an FBO via `image(pg, ...)` synchronizes its OpenGL texture cache; if `pg.pixels` is null during cache init or after `beginDraw()`, Processing forcibly sets `pg.pixels = null`, causing `NullPointerException` on subsequent frame readbacks.
- **Use `PImage` for Feeding Shaders**: When simulation state (e.g. height maps, chemo trails) needs to feed GLSL shaders, allocate a dedicated `PImage` (`createImage(w, h, ARGB)`). `PImage.pixels` is a permanent CPU integer array that is never cleared to null by JOGL. Update via `trailTexture.pixels[...] = ...; trailTexture.updatePixels();` before passing to `shader()` / `image()`.
- **Keep Simulation Hot Paths on CPU**: For grids up to ~720x720, maintain simulation diffusion and evaporation on primitive arrays (`float[] trailMap`, `float[] nextTrailMap`). CPU convolution avoids costly `glReadPixels` pipeline stalls, maintains 60+ FPS, and preserves headless unit testability.
- **Visual Rendering vs Audio Entity Lifecycle Decoupling**: When audio voices persist after an entity's physical exhaustion (e.g. ringing modal bell tails, reverb decay), immediately suppress all visual geometry for `isDepleted` entities unless an explicit ephemeral particle effect is active. Never render static boundary outlines (`rMax`) or lingering resonance circles once nutrients reach zero. Render food nodules with only their live active physical radius (`rCur`), active eating pulses, and elevation displacement.

## 2. Multi-Threaded Control & Animation Thread Purity
- **Thread Affinity Constraint**: In Processing OpenGL (`P2D` / `P3D` / JOGL), native OpenGL commands (`beginDraw()`, `endDraw()`, `background()`, `glClearColor`) are strictly thread-bound to the main rendering thread (`draw()`).
- **Asynchronous Callback Prohibition**: Never execute `beginDraw()`, `endDraw()`, shader passes, or FBO drawing inside asynchronous callbacks (such as Java Sound `Receiver.send()` MIDI callbacks, audio worker threads, or background tasks). Violating this triggers fatal native JVM crashes (`SIGSEGV` in `glClearColor`).
- **Deferred Execution Pattern**: When an asynchronous event requires an FBO reset or OpenGL canvas operation:
  1. The callback must mutate only pure CPU memory (float arrays, parameters, volatile booleans).
  2. Set a thread-safe flag (e.g., `volatile boolean pendingReinoculateFboClear = true;`).
  3. At the beginning of `draw()`, check the flag and perform the required FBO / OpenGL calls safely within the active OpenGL context.
- **Redundant FBO Clears**: When a render pipeline already streams CPU buffer data into GPU textures each frame (e.g. `updatePixels()`), avoid redundant asynchronous FBO clears.

## 3. Hardware MIDI Controller Protocols & Telemetry

### Novation Launchpad Mini [MK3]
- **Grid vs Perimeter Addressing**:
  - **8x8 Grid Pads**: Transmit and receive `NOTE_ON` / `NOTE_OFF` (`36–99` in Custom Mode 3 / Drum Rack layout; `11–88` in Programmer Mode).
  - **Perimeter Buttons (Scene Launch Column & Top Row)**: Transmit and receive `CONTROL_CHANGE` on Channel 1 (`0xB0`). The 8 right-side scene buttons map top-to-bottom to `CC 89`, `CC 79`, `CC 69`, `CC 59`, `CC 49`, `CC 39`, `CC 29`, `CC 19`.
- **Bi-Directional CC Feedback**: Send Channel 1 `CONTROL_CHANGE` (`0xB0`) with the CC number and velocity (palette code `0–127`) to drive perimeter LEDs.

### Spectral Separation for Hardware LED Telemetry
- **Pad Diffusion & Color Overlap**: Translucent silicone pads and adjacent reflections blend similar warm tones. Never map multiple semantic layers to adjacent warm colors (such as Yellow, Amber, and Orange).
- **Trilateral Color Domain Standard**:
  - **Colony / Organism**: Yellow / Golden / Warm Ochre spectrum (`12–15`, `62`, `84`).
  - **Nutrient / Food Nodules**: Electric Cyan / Turquoise spectrum (`37`, `78`).
  - **Consumption / Eating Activity**: Vivid Magenta $\to$ Purple degradation spectrum (`53`, `54`, `55`, `52`).
  - **Hardware Toggles**: Indicator LEDs on hardware toggle buttons must match the exact grid layer color (e.g. Yellow for mold layer, Cyan for food layer, Magenta for eating layer).

### Bidirectional Onscreen UI Synchronization
- **Discrete Controller Widget Binding**: Any parameter controllable via physical MIDI inputs (knobs, faders, buttons) that also has an onscreen representation (`Slider`, `Toggle`, `RadioGroup`, `Dropdown`) must maintain bidirectional state binding.
- **Recursive Callback Suppression**: When updating onscreen widgets from incoming MIDI interrupts, invoke non-notifying setters (e.g., `widget.setIndex(newIdx, false)`) so hardware adjustments refresh the UI display without re-triggering simulation or audio action callbacks.

### Akai MIDImix Matrix & Receiver Latch Protection
- **Factory CC Invariant**: Respect the physical CC layout (`Faders 1–8: 19, 23, 27, 31, 49, 53, 57, 61`; `Master Fader: 62`; `Knobs R1: 16, 20, 24, 28, 46, 50, 54, 58`; `R2: 17, 21, 25, 29, 47, 51, 55, 59`; `R3: 18, 22, 26, 30, 48, 52, 56, 60`; `Mute: Notes 1, 4, 7, 10, 13, 16, 19, 22`; `Solo: Notes 2, 5, 8, 11, 14, 17, 20, 23`; `Rec Arm: Notes 3, 6, 9, 12, 15, 18, 21, 24`).
- **Receiver Re-Enable Guard**: If a physical button (such as Note 19) toggles the master connection state (`midiEnabled`), the MIDI receiver callback must whitelist that specific toggle event even when `midiEnabled == false` to prevent permanent hardware lockouts.

## 4. Processing PDE Architecture & Compilation Invariants
- **Single Outer Class Preprocessing**: Processing flattens all `.pde` files in the sketch folder into a single Java class extending `PApplet`.
- **Never Declare `settings()` in `.pde` Tabs**: Processing's preprocessor extracts calls to `size()`, `fullScreen()`, `pixelDensity()`, `smooth()`, and `noSmooth()` from `setup()` and automatically synthesizes a `public void settings()` method. Declaring an explicit `settings()` method while any of these calls are present in `setup()` triggers a duplicate method compile error (`Duplicate method settings() in type <Sketch>`). Always place `fullScreen(P2D);` or `size(w, h, P2D);` directly as the first statement in `setup()`.
- **No Static Members in `.pde` Inner Classes**: In Processing, code across all `.pde` tabs is concatenated as non-static inner members of `PApplet`. Non-static inner classes cannot declare `static class` or `static` fields. Never use `static` on classes, structs, or fields defined in `.pde` tabs (e.g. `static class Coeffs` causes: `The member type cannot be declared static; static types can only be declared in static or top level types`). Place any required static utility classes in dedicated `.java` tabs (such as `FastFFT.java` or `PartitionedConvolver.java`).
- **Member Interfaces Forbidden in `.pde` Inner Classes**: In Java, all member interfaces are implicitly `static`. Because `.pde` classes are non-static inner classes of `PApplet`, declaring an interface inside an inner class (e.g. `class MidiHandler { interface FloatConsumer { ... } }`) triggers: `The member interface <Name> can only be defined inside a top-level class or interface or in a static context`. Always declare functional interfaces at the top-level sketch scope in a `.pde` file (outside of any class block, such as `FloatCallback` in `UI.pde`) or in a dedicated `.java` tab.
- **Exclusive Lifecycle Methods**: Lifecycle methods like `setup()`, `draw()`, and `exit()` must exist **only** in the root sketch file (`MOLD.pde`). Never duplicate lifecycle methods in auxiliary `.pde` files.
- **Namespace Collision Guard**: Helper methods and global variables declared in `.pde` files are package/class-level. Ensure method signatures and names are globally unique across all `.pde` files.

## 5. Window & Display Stability (macOS / Processing)
- **Native Fullscreen via `setup()`**: Always configure Processing's native `fullScreen(P2D)` as the first call in `setup()` in `MOLD.pde`.
- **Never Enable Window Resizing with OpenGL on macOS**: Never call `surface.setResizable(true);` when using `P2D` or `P3D` renderers on macOS. JOGL deadlocks with macOS AppKit during window resizing and native Spaces transitions, causing an unrecoverable spinning beachball freeze.
- **Zero Low-Level AWT/AppKit Reflection**: Never attempt low-level native window manipulation (`NSWindow`, `NSApplicationPresentationOptions`, or Java AWT Peer reflection) on startup, as this deadlocks the macOS event thread and causes unrendered white screens / spinning beachball freezes.
- **Presentation & Theater Modes**: Implement Theater / Fullscreen presentation modes by dynamically adapting canvas margins and toggling UI component visibility in the rendering loop, keeping window management standard.

## 6. Multi-Device MIDI Architecture
- **Decoupled Controller Handles**: When supporting multiple physical MIDI devices (e.g., Novation Launchpad + Akai MIDImix), maintain separate `Transmitter` and `Receiver` pipelines for each device.
- **Independent UI Routing**: Provide dedicated In/Out dropdown selectors and status tracking for each controller rather than a shared port slot.
- **Isolated LED Streams**: Keep high-frequency LED feedback streams (e.g. Launchpad 64-pad matrix) strictly isolated to their target device receiver to prevent MIDI bus saturation.

## 7. Execution Momentum & Verification
- **Direct Implementation**: When a concrete edit or bug fix is identified, execute the code change immediately. Avoid redundant re-reading or polling loops.
- **Automated Verification**: Run `./tests/run_tests.sh` to verify compilation and DSP acceptance criteria after modifications.

## 8. WebApp Porting & Synchronization
- **Shader to CPU Value Scaling**: Float-based GLSL shaders (`[0.0, 1.0]`) scale up by 255 for WebApp CPU pixel arrays. A shader cutoff of `0.005` translates to a hard CPU cutoff of `1.275`. Do NOT use arbitrarily low values (like `0.15`), or the web app will suffer from massive, lingering trails and "blooms".
- **Simulation Tick Rate Matching**: The WebApp's `requestAnimationFrame` loop must increment its `speedAccumulator` identically to the Processing `draw()` loop (e.g. `speedAccumulator += CONFIG.simSpeed * 0.4`). A lower multiplier will cause sluggishness and mismatched decay rendering.
- **Harmonic Grid Scaling Math**: The musical grid shifts one octave every *two* rows (`Math.floor(invertedRow / 2)`). Additionally, maintain a baseline of `baseOctave = 1` (shifting the 55Hz A1 root) to prevent the "NORMAL" setting from scaling up into ultrasonic (>20kHz) ranges.
- **WebApp Modular Architecture & p5.js Encapsulation**: Keep the web application decomposed into clean, specialized files:
  - `css/styles.css`: Viewport styling, canvas pixelation rules, and UI transitions.
  - `js/config.js`: Global configuration state (`CONFIG`), musical scale matrices, and acoustic bell ratios.
  - `js/audio.js`: Web Audio context lifecycle, `FoodAudioVoice` synthesizer, and algorithmic velvet noise reverb.
  - `js/simulation.js`: `Agent` and `FoodNodule` data models, Moore neighborhood biomass evaluation.
  - `js/midi.js`: Web MIDI endpoints, Launchpad MK3 batch SysEx RGB telemetry, and MIDImix CC bindings.
  - `js/sketch.js`: Encapsulate the `p5.js` instance (`new p5((p) => { ... })`) handling canvas resizing, CPU trail decay, and pixel array streaming.
  - `js/ui.js`: DOM event listeners, slider bindings, and accordion toggles.
- **Root and Subdirectory Mirroring**: The repository maintains web app entry points at both `./index.html` (with `./js/` and `./css/`) and `./WebApp/index.html` (with `./WebApp/js/` and `./WebApp/css/`). Any updates to one must be mirrored to the other.
- **HTML Script Patching & Module Verification Safety**: When modifying script logic or JavaScript files, ALWAYS verify them with `node -c` and run a shared-context global script evaluation (`vm.runInThisContext`) to ensure inter-module variables and functions resolve cleanly without reference errors. Ensure all dynamically added UI elements have properly attached `addEventListener` bindings.

## 9. Workspace Skills
The repository includes dedicated workspace skills located in `.agents/skills/` (mirrored in `.agent/skills/` and `.claude/skills/`):
- `processing-opengl-sim`: Processing OpenGL, PImage shader feeding, simulation CPU arrays, agent bioenergetics.
- `processing-threading-lifecycle`: Processing PDE architecture, JOGL threading purity, deferred execution, macOS window stability.
- `realtime-audio-dsp`: Real-time DSP stability, velvet noise reverb, partitioned convolution, 3D spatialization, saturation & limiting.
- `hardware-midi-telemetry`: Hardware MIDI controller integration, Launchpad MK3 protocols, SysEx RGB, Trilateral Color telemetry, MIDImix.
- `offline-dsp-verification`: Offline testing without hardware/display, `pde_to_java.py`, Processing headless harness, DSP invariant assertion.
- `web-audio-sim-porting`: Porting Processing/Java DSP & simulation to Web Audio/HTML5 Canvas, tick rate matching, shader-to-CPU scaling, harmonic grid math.

