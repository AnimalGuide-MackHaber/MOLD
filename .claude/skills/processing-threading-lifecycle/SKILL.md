---
name: processing-threading-lifecycle
description: >-
  Use this skill when modifying Processing PDE lifecycle methods, managing JOGL/OpenGL
  thread affinity, handling asynchronous callbacks (MIDI, audio threads), preventing macOS
  window freezes, or structuring multi-tab Java/PDE sketches.
---

# Processing PDE Architecture, Thread Affinity & macOS Display Stability

This skill defines the threading, lifecycle, compilation, and windowing invariants required to keep Processing 4 (Java / JOGL) rock-solid, crash-free, and high-performance.

---

## 1. Processing PDE Compilation Invariants

Processing has unique preprocessing behaviors that differ from standard Java IDEs:

### A. Single Outer Class Preprocessing
Processing concatenates all `.pde` tabs in the sketch folder into a single top-level Java class extending `PApplet`.
* Global variables and helper methods in any `.pde` tab share the sketch-wide namespace.
* Ensure method signatures and variable names are globally unique across all `.pde` tabs to prevent collision errors.

### B. Never Declare `settings()` in `.pde` Tabs
Processing's preprocessor automatically parses calls to `size()`, `fullScreen()`, `pixelDensity()`, `smooth()`, and `noSmooth()` located in `setup()`, and generates its own `public void settings()` method during build.
* **The Error**: Declaring an explicit `public void settings()` or `void settings()` in any `.pde` tab causes:
  `Duplicate method settings() in type <Sketch>`
* **The Rule**: Place `fullScreen(P2D);` or `size(w, h, P2D);` directly as the first statement in `setup()` inside the root `.pde` file.

### C. No Static Members in `.pde` Inner Classes
Because code across `.pde` tabs is concatenated as non-static inner members of `PApplet`, inner classes cannot declare `static` methods, fields, or nested classes:
* **The Error**: `The member type cannot be declared static; static types can only be declared in static or top level types.`
* **The Rule**: Place any required static utility classes, FFT engines, or DSP convolving kernels in dedicated `.java` tabs (e.g., `FastFFT.java`, `PartitionedConvolver.java`, `VelvetImpulseGenerator.java`).

### D. Exclusive Lifecycle Methods
Lifecycle methods (`setup()`, `draw()`, `exit()`, `keyPressed()`, `keyReleased()`, `mousePressed()`, `mouseReleased()`) must exist **strictly in the root sketch file** (e.g., `MOLD.pde`). Never duplicate lifecycle methods in auxiliary `.pde` tabs.

---

## 2. Multi-Threaded Control & OpenGL Thread Affinity

In Processing OpenGL (`P2D` / `P3D` / JOGL), native OpenGL commands are strictly bound to the active OpenGL context on the main rendering/animation thread (`draw()`).

### The Fatal Asynchronous Trap
Never execute OpenGL or FBO commands inside asynchronous callbacks:
* Java Sound / PortAudio callbacks (`AudioCallback`, `AudioWorker`)
* Java Sound MIDI receiver callbacks (`Receiver.send()`)
* Background threads or timers

```java
// FATAL ERROR: Native JVM crash (SIGSEGV in glClearColor or JOGL context lockup)
public void send(MidiMessage msg, long timeStamp) {
  if (isReinoculateNote(msg)) {
    fbo.beginDraw();      // CRASH! Not on OpenGL render thread
    fbo.background(0);    // SIGSEGV
    fbo.endDraw();
  }
}
```

### The Deferred Execution Pattern
When an asynchronous hardware or audio event requires a canvas reset, FBO clear, or shader update:
1. **Mutate only pure CPU state in the callback**: update atomic variables, arrays, or volatile flags.
2. **Declare thread-safe flags**:
   ```java
   volatile boolean pendingReinoculateFboClear = false;
   ```
3. **Execute in `draw()`**: At the beginning of the frame in `draw()`, check the flag within the active OpenGL context:
   ```java
   void draw() {
     if (pendingReinoculateFboClear) {
       pendingReinoculateFboClear = false;
       fbo.beginDraw();
       fbo.background(0);
       fbo.endDraw();
     }
     // Normal render loop continues...
   }
   ```

---

## 3. macOS Window & Display Stability

macOS AppKit and JOGL have fragile interactions that can cause unrecoverable UI hangs:

### A. Never Enable Window Resizing with OpenGL on macOS
Never call:
```java
surface.setResizable(true); // STRICTLY FORBIDDEN on macOS with P2D / P3D
```
* **Why**: JOGL's native peer locks up with AppKit during live window resizing, Mission Control swipes, and native Spaces transitions, creating an unrecoverable spinning beachball freeze.

### B. Zero Low-Level AWT/AppKit Reflection
Never attempt native window manipulation using Java reflection against `NSWindow`, `NSApplicationPresentationOptions`, or AWT peer classes on startup. Doing so deadlocks the macOS AppKit event loop before the first frame renders, resulting in blank white screens.

### C. Presentation & Theater Modes
To implement Theater or Fullscreen modes:
* Use Processing's native `fullScreen(P2D)` in `setup()`.
* Dynamically adjust canvas margins and UI panel visibility within the standard `draw()` loop rather than resizing or manipulating the underlying native window.

---

## 4. Verification Checklist

Before committing lifecycle or threading changes:
- [ ] Is `fullScreen()` or `size()` placed only in `setup()` in the root `.pde`?
- [ ] Are `setup()` and `draw()` declared only once across the entire project?
- [ ] Are all static utility classes in `.java` files rather than `.pde` tabs?
- [ ] Are all OpenGL commands (`beginDraw`, `endDraw`, `glClearColor`) isolated strictly to `draw()`?
- [ ] Are asynchronous events handled using the deferred execution pattern with volatile flags?
- [ ] Is `surface.setResizable(true)` absent from the codebase?
- [ ] Has `./tests/run_tests.sh` passed `MoldHeadlessSmokeTest`?
