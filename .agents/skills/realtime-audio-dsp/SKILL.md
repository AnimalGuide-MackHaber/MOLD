---
name: realtime-audio-dsp
description: >-
  Use this skill when designing, implementing, or tuning real-time audio synthesis,
  bio-sonification, biquad filter stability, algorithmic reverb, partitioned convolution,
  3D binaural spatialization, or master limiting in Java or Processing.
---

# Real-Time Audio DSP, Stability & Bio-Sonification Guide

This skill provides guidelines and patterns for implementing low-latency, crash-proof, real-time audio synthesis, algorithmic reverb, and spatialization in Java and Processing environments.

---

## 1. Filter Numerical Stability & Algebraic Saturation

Resonant biquad filters undergoing fast parameter modulation (such as biological sonification sweeps) are prone to internal state explosion, leading to `NaN` or `Infinity` audio dropouts.

### Direct Form II Transposed with Algebraic Saturation
To guarantee unconditional numerical stability across all cutoff sweeps and high resonance ($Q > 10$):
1. **Clamp Modulation Range**:
   Always clamp cutoff frequency strictly between `20.0 Hz` and `0.45 * sampleRate`.
2. **Bound Accumulator States**:
   Apply smooth algebraic saturation or `tanh` to the filter feedback state:
   ```java
   public float process(float in) {
     float out = b0 * in + s1;
     // Soft-saturate accumulator state to prevent NaN blowup
     s1 = b1 * in - a1 * out + s2;
     s2 = b2 * in - a2 * out;
     
     // Algebraic soft-clipping on output
     if (out > 3.0f || out < -3.0f) {
       out = (float) Math.tanh(out / 3.0f) * 3.0f;
     }
     return out;
   }
   ```

---

## 2. Algorithmic Velvet Noise Reverb & Partitioned Convolution

High-quality algorithmic space without heavy comb filter coloration:

### A. Sparse Velvet Impulse Generation (`VelvetImpulseGenerator`)
* Velvet noise replaces dense Gaussian noise with a sparse sequence of ternary impulses ($\pm 1$ and $0$).
* Pulse density $M$ determines the average number of pulses per second (typically 2000–4000 pulses/sec).
* Modulate decay time $T_{60}$ based on colony biomass while applying exponential envelope decay.

### B. Partitioned Overlap-Save Convolution (`PartitionedConvolver`)
* Convolving large impulse responses (e.g., 2–4 second reverb tails) in the time domain is $O(N^2)$, which overwhelms the CPU.
* Standard FFT convolution adds latency equal to the entire impulse response length.
* **The Solution: Partitioned FFT**: Split the impulse response into equal blocks of size $B$ (e.g., 256 or 512 samples). Perform frequency-domain multiplication and complex addition across active partitions in real time with minimal latency (latency = $B$ samples).

### C. Dynamic Headroom & Bio-Modulation Ceilings
When modulating reverb parameters from dynamic biological states (e.g. slime mold biomass, feeding rate):
```java
// Soft-limit injection into reverb tank to prevent infinite feedback
float injectionScale = 0.35f * (1.0f - reverbFeedback * 0.45f);
float wetInL = (float) Math.tanh(dryInL * injectionScale);
float wetInR = (float) Math.tanh(dryInR * injectionScale);
```

---

## 3. Master Bus Protection & Limiting

Bio-sonification often produces unpredictable multi-voice polyphony and sudden bursts of energy when colonies discover food.

### Studio Master Brickwall Limiter
Never allow raw multi-voice summers to feed directly into the audio DAC:
1. **Proportional Voice Scaling**:
   Scale the multi-voice mix bus by $1.0 / \sqrt{N}$ where $N$ is the active voice count.
2. **Dedicated Master Limiter**:
   Place a studio brickwall limiter (`StudioMasterLimiter`) on the master bus.
   - Threshold: `-0.92` to `-0.95` (-0.7 dBFS).
   - Instantaneous attack with smooth release curve or lookahead delay.
   - Under extreme overload (+36 dBFS), the limiter must hold output strictly within `[-0.92, +0.92]` without arithmetic wrap-around or harsh digital square waves.

---

## 4. 3D Binaural & Stereo Spatialization

To spatialize sound sources according to their coordinates on the 2D canvas:

### A. Constant-Power Stereo Panning
Use equal-power sinusoidal panning curves:
```java
float pan = constrain(nodeX / canvasWidth, 0.0f, 1.0f);
float gainL = (float) Math.cos(pan * Math.PI * 0.5);
float gainR = (float) Math.sin(pan * Math.PI * 0.5);
```

### B. Pinna Acoustic Shadowing (Front/Rear Depth)
Simulate HRTF (Head-Related Transfer Function) pinna cues:
* Sound sources in the upper half of the screen (representing distant/rear space) pass through a subtle high-shelf attenuation filter ($4 \text{ kHz} - 8 \text{ kHz}$ cut by -3 dB to -6 dB).
* Sound sources in the foreground retain crisp high-frequency presence.

### C. Vertical Elevation Filtering
Modulate harmonic pitch registers or high-pass brightness according to vertical position ($Y$ axis) to produce elevation cues.

---

## 5. Audio Thread Architecture & Device Resilience

1. **Lock-Free Buffering**: Never block the audio worker thread with `synchronized` blocks against the GUI thread. Use circular ring buffers or atomic memory swaps.
2. **Device Scanning & Fallback**: Always catch `LineUnavailableException`, log available `Mixer.Info` lines, and fallback gracefully to the system default audio device.
3. **Shutdown Cleanliness**: In sketch `exit()`, stop audio threads, drain lines, and call `line.close()` to avoid holding audio hardware locks.

---

## 6. Verification Checklist

Before committing audio DSP changes:
- [ ] Are biquad cutoff frequencies clamped safely below the Nyquist limit?
- [ ] Are accumulator states protected against NaN/Infinity overflow with algebraic soft saturation?
- [ ] Is multi-voice summing protected with proportional gain staging and a master brickwall limiter?
- [ ] Has `./tests/run_tests.sh` passed `MoldAudioStabilityTest` and `MoldStereoSpatializationTest`?
