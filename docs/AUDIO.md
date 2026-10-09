# Audio Engine: Synthesis, Velvet Convolver & Bio-Sonification

This document details the real-time audio synthesis pipeline, DSP algorithms, filter equations, and biometric audio modulation architecture implemented in `MOLD`.

---

## 1. System Overview & Audio Threading

The audio engine runs on a dedicated high-priority background thread (`AudioEngine extends Thread`) isolated from Processing's 60 FPS animation loop. Communication between the simulation and the audio thread occurs exclusively via thread-safe lock-free primitives (`volatile` scalars and thread-safe data structures).

```mermaid
flowchart TD
    subgraph ControlThread["Visual / Simulation Thread (60 FPS)"]
        Bio["Simulation State & Food Nodules"] --> BioTelem["updateReverbBioTelemetry()"]
        BioTelem --> Params["Volatile DSP Controls & Async IR Trigger"]
    end
    subgraph AudioThread["Real-Time Audio Thread (~86.1 Hz Block Rate)"]
        Params -.-> Mix["Voice Summer & Equal-Power Panner"]
        Mix --> Voices["Nodule Voices: Oscillators + Biquad Filter"]
        Voices --> Headroom["1/√N Acoustic Headroom Scaling"]
        Headroom --> Convolver["Uniform Partitioned Convolver (UP-OLA)"]
        Convolver --> Limiter["Master Dynamics Peak Limiter"]
        Limiter --> SoftKnee["Padé Rational Tanh Soft Knee"]
        SoftKnee --> Line["javax.sound.sampled SourceDataLine"]
    end
    AsyncExec["irExecutor (Background Worker)"] -. "New Stereo IR" .-> Convolver
```

### Real-Time Specs & Constraints

- **Sample Rate ($f_s$):** $44{,}100\text{ Hz}$
- **Format:** 16-bit Signed PCM Little-Endian Stereo (2 channels)
- **Audio Block Size ($B$):** $512\text{ samples}$
- **Block Latency:** $T_{\text{block}} = \frac{512}{44100} \approx 11.61\text{ ms}$
- **Zero Heap Allocations:** All sample arrays, FFT workspaces, and accumulation buffers are pre-allocated during initialization. Zero objects are instantiated inside `run()` or `processBlock()`, completely preventing JVM Garbage Collection stalls.

---

## 2. 8×8 Spatial Pitch Mapping & Tuning Matrices

Each food nodule's fundamental frequency is determined by its position on an $8 \times 8$ grid over the canvas ($c \in [0, 7]$, $r \in [0, 7]$):

$$r_{\text{inv}} = 7 - r, \quad \text{octave} = \text{baseOctave} + \lfloor r_{\text{inv}} / 2 \rfloor$$

If $r_{\text{inv}}$ is odd, an intermediate sub-octave scalar ($1.5$) is applied to double melodic density.

### Tuning Systems

1. **Equal Temperament Modes (Major/Minor Pentatonic, Lydian, Dorian, Hirajoshi):**
   Given scale degree semitone offset $S(c)$ and root pitch index $K_{\text{root}} \in [0, 11]$:
   $$\text{semitone}_{\text{total}} = (\text{octave} \cdot 12) + K_{\text{root}} + S(c)$$
   $$f = 440.0 \cdot 2^{\frac{\text{semitone}_{\text{total}} - 57}{12}} \cdot \text{subOffset}$$

2. **Just Intonation:**
   Uses pure integer frequency ratios relative to fundamental root pitch:
   $$R \in \left\{ 1.0, \; \frac{9}{8}, \; \frac{5}{4}, \; \frac{11}{8}, \; \frac{3}{2}, \; \frac{13}{8}, \; \frac{7}{4}, \; 2.0 \right\}$$
   $$f = 55.0 \cdot 2^{\text{octave} - 1} \cdot 2^{K_{\text{root}} / 12} \cdot R(c) \cdot \text{subOffset}$$

---

## 3. Voice Synthesis & Filter Architecture

Each active food nodule acts as an autonomous monophonic synthesizer voice:

### Oscillators & Fast Sine LUT

The oscillator phase advances by $\Delta \phi = f / f_s$ per sample. Supported waveforms:
- **Triangle:** $\text{raw} = (\phi < 0.5) \;?\; (4\phi - 1) : (3 - 4\phi)$
- **Sine:** Pre-computed 4096-entry lookup table with bitwise wrap:
  $$\text{idx} = \lfloor \phi \cdot 4096 \rfloor \;\&\; 4095, \quad \text{raw} = \text{sineTable}[\text{idx}]$$
- **Sawtooth:** $\text{raw} = 2\phi - 1$
- **Square:** $\text{raw} = (\phi < 0.5) \;?\; 0.8 : -0.8$

### Dynamic Resonant Biquad Low-Pass Filter

The voice signal passes through a direct-form II Biquad low-pass filter (Robert Bristow-Johnson Cookbook):

$$\begin{aligned}
\omega_0 &= \frac{2\pi f_c}{f_s}, \quad \alpha = \frac{\sin(\omega_0)}{2Q} \\
b_0 &= \frac{1 - \cos(\omega_0)}{2(1 + \alpha)}, \quad b_1 = \frac{1 - \cos(\omega_0)}{1 + \alpha}, \quad b_2 = b_0 \\
a_1 &= \frac{-2\cos(\omega_0)}{1 + \alpha}, \quad a_2 = \frac{1 - \alpha}{1 + \alpha}
\end{aligned}$$

#### Non-Linear Cutoff Sweep
As nutrients deplete ($\rho = N / N_0$), the cutoff sweeps downwards from $3200\text{ Hz}$ to $80\text{ Hz}$:
$$f_c = f_{\text{base}} + (f_{\max} - f_{\text{base}}) \cdot \rho^{1.8 \cdot \text{sens}}$$

### Moore-Neighborhood VCA Modulation

The voice output is amplified by a Voltage Controlled Amplifier (VCA) driven by the surrounding biological mass. 
The 8 Moore neighbors surrounding the nodule's cell are summed to calculate $\text{adjacentMass}$:
$$\text{effectiveMass} = \max(0, \; \text{adjacentMass} - \text{gateThreshold})$$
$$\text{drive} = \frac{\text{effectiveMass} \cdot \text{vcaSensitivity} \cdot 1.25}{1000.0}$$
$$\text{targetGain} = \text{isBeingEaten} \;?\; \tanh(\text{drive}) : 0.0$$

The gain is smoothed through a single-pole low-pass filter to prevent clicks:
$$G_{t} = G_{t-1} + (\text{targetGain} - G_{t-1}) \cdot 0.15$$

---

## 4. Multi-Voice Headroom & 3D Binaural Spatial Soundscape

### Listener-Centered 3D Spatial Geometry

The virtual listener is seated at the center of the $8 \times 8$ simulation grid at $(x_0, y_0) = (W / 2, H / 2) = (360, 360)$. Food nodules are projected into a 3D binaural coordinate space $(\Delta x, \Delta y, z)$:

1. **Normalized Cartesian Coordinates:**
   $$\Delta x = \text{constrain}\left(\frac{x - x_0}{x_0}, \; -1.0, \; 1.0\right) \quad (\text{Left } [-1] \to \text{Right } [+1])$$
   $$\Delta y = \text{constrain}\left(\frac{y_0 - y}{y_0}, \; -1.0, \; 1.0\right) \quad (\text{Rear } [-1] \to \text{Front } [+1])$$

2. **Frequency & Front/Back Harmonic Layout:**
   - **Front ($\Delta y > 0$, Rows 0–3):** Higher harmonic registers ($2\times$ to $4\times$ fundamental pitch) are located in front of the listener.
   - **Rear ($\Delta y < 0$, Rows 4–7):** Deeper harmonic registers and sub-bass frequencies are located behind the listener.

3. **Front vs. Back Pinna Spectral Modeling:**
   Human ears differentiate forward from backward sound sources using outer ear pinna concha acoustic reflections.
   Each voice incorporates a dedicated `frontBackFilter` (Biquad high-shelf at $4.0\text{ kHz}$):
   - **Front Sources ($\Delta y > 0$):** Direct presence boost $G_{\text{front}} = +1.5\text{ dB} \cdot \Delta y$ preserving high-frequency clarity.
   - **Rear Sources ($\Delta y < 0$):** Rear-head acoustic shadow attenuates high frequencies $G_{\text{rear}} = -4.5\text{ dB} \cdot |\Delta y|$.

4. **Slime Mold Mass $\to$ 3D Elevation (Z-Axis Height):**
   When the slime mold colony swarms onto a food nodule, the local biomass density elevates the perceived sound vertically in 3D headphone space:
   - Elevation parameter: $E = \text{constrain}(\text{adjacentMass} / 800.0, \; 0.0, \; 1.0)$.
   - Modeled via an HRTF vertical pinna notch filter (`pinnaElevationFilter`) whose notch frequency sweeps from $6.2\text{ kHz}$ (ear level / horizon) up to $9.2\text{ kHz}$ (overhead zenith) with deepening notch attenuation ($-4\text{ dB} \to -8\text{ dB}$).

5. **Lateral Azimuth Panning & Constant-Power Law:**
   Lateral pan passes through an expansive $1.35\times$ power curve:
   $$b_{\text{shaped}} = \text{sgn}(\Delta x) \cdot |\Delta x|^{1.35}$$
   $$\text{panNorm} = \text{constrain}(0.5 + 0.5 \cdot b_{\text{shaped}}, \; 0.0, \; 1.0)$$
   $$\theta_{\text{pan}} = \text{panNorm} \cdot \frac{\pi}{2}, \quad g_L = \cos(\theta_{\text{pan}}), \quad g_R = \sin(\theta_{\text{pan}})$$

6. **Binaural Interaural Time Difference (ITD / Haas Micro-Delay):**
   The ear opposite the source receives a micro-delay of up to $18\text{ samples}$ ($\approx 0.4\text{ ms}$):
   $$\tau_{\text{delay}} = \lfloor |b_{\text{shaped}}| \cdot 18.0 \rfloor$$
   If $b_{\text{shaped}} < 0$, right ear is delayed; if $b_{\text{shaped}} > 0$, left ear is delayed.

7. **Acoustic Head-Shadow Filter Tilt (ILD):**
   Ear facing the source receives direct high-frequency transmission, opposite ear receives lateral shadow attenuation:
   $$f_{c, L} = f_c \cdot (1 - 0.18 \cdot \Delta x), \quad f_{c, R} = f_c \cdot (1 + 0.18 \cdot \Delta x)$$

8. **Distance Attenuation:**
   Sound level subtly attenuates with Euclidean distance from listener center:
   $$d = \sqrt{\Delta x^2 + \Delta y^2}, \quad G_{\text{dist}} = \frac{1.0}{1.0 + 0.25 \cdot d}$$

### Acoustic Summer Headroom Scaling

To prevent multi-voice accumulation clipping, the sub-mix is scaled proportionally by the square root of active voices $V_{\text{active}}$:
$$S_{\text{voice}} = \frac{0.24}{\sqrt{\max(1.0, \; 0.75 \cdot V_{\text{active}})}}$$

---

## 5. Velvet Noise Algorithmic Convolver (True Stereo UP-OLA)

Reverberation is implemented via real-time partitioned convolution with a parametrically synthesized stereo velvet-noise impulse response.

### Velvet Impulse Response Generation

Velvet noise synthesizes sparse, pseudo-random sequences of unit impulses ($+1$ and $-1$) whose temporal density increases logarithmically from early reflections ($D_0 = 2000\text{ pulses/s}$) to dense late diffuse field ($D_{\max} = 10000\text{ pulses/s}$):

1. **Grid Interval:** At time $t$, average pulse spacing is $T_d(t) = \frac{f_s}{D(t)}$.
2. **Pulse Position & Sign:** Pulse sample $m_k = \lfloor k \cdot T_d + \mathcal{U}(0, T_d - 1) \rfloor$, sign $s_k \in \{-1, +1\}$.
3. **Decay Envelope:** Energy decays exponentially based on $T_{60}$:
   $$E(t) = 10^{-3 \cdot t / T_{60}}$$
4. **Spectral Absorption Filter:** Single-pole low-pass filter simulates air and wall absorption:
   $$y[n] = (1 - \alpha) x[n] + \alpha y[n-1]$$
5. **Stereo Decorrelation:** Left and right impulse trains use independent pseudorandom seeds, achieving normalized cross-correlation $\rho_{LR} < 0.01$.

### True Stereo Convolution Architecture

To prevent reverberant tails from collapsing the stereo image into mono, the convolver features dual-channel input history ring buffers and natural $85/15$ acoustic room cross-bleed:
$$\text{send}_L = 0.85 \cdot x_L + 0.15 \cdot x_R, \quad \text{send}_R = 0.15 \cdot x_L + 0.85 \cdot x_R$$

```mermaid
flowchart LR
    InL["Input Left (B=512)"] --> Cross["85/15 Acoustic Cross-Bleed"]
    InR["Input Right (B=512)"] --> Cross
    Cross --> FFT_L["FastFFT(send_L)"]
    Cross --> FFT_R["FastFFT(send_R)"]
    FFT_L --> HistL["History Ring Buffer L [P][1024]"]
    FFT_R --> HistR["History Ring Buffer R [P][1024]"]
    HistL --> AccL["Spectral Acc: sum_p(X_L * H_L)"]
    HistR --> AccR["Spectral Acc: sum_p(X_R * H_R)"]
    AccL --> IFFT_L["FastFFT.ifft(L)"]
    AccR --> IFFT_R["FastFFT.ifft(R)"]
    IFFT_L --> OLA["Overlap-Add & Headroom Mix"]
    IFFT_R --> OLA
    OLA --> Out["Wide Stereo Output"]
```

### Uniform Partitioned Overlap-Add (UP-OLA)

- **Block Size $B = 512$**, **FFT Size $2B = 1024$**.
- An impulse response of length $L$ is sliced into $P = \lceil L / B \rceil$ uniform partitions $h_p[n]$ ($0 \le p < P$), zero-padded to $2B$, and transformed into frequency domain slices $H_p[k]$.
- Input audio is buffered into blocks of size $B$, zero-padded to $2B$, transformed to $X_m[k]$, and stored in a circular history delay buffer.
- Spectral accumulation computes the circular convolution:
  $$Y_m[k] = \sum_{p=0}^{P-1} X_{m-p}[k] \cdot H_p[k]$$
- Two inverse FFTs (Left and Right) yield the time-domain signal, which is overlap-added with the previous tail buffer.

---

## 6. Bio-Sonification Telemetry Routing

The slime mold's macroscopic colony states dynamically modulate the acoustic reverberator, scaled by the **Mold Bio-Mod Depth** (`reverbBioModDepth`, default `2.0x`):

| Biological Macro-Metric | Reverb Parameter | Transfer Function / Mapping | Musical Character |
|:---|:---|:---|:---|
| **Colony Biomass & Feeding** ($\sum E_{\text{cell}}$, $A_{\text{feed}}$) | **Wet / Dry Mix** | $\Delta \text{Wet} = \Delta \text{Mass} \cdot 0.20 + (d_{\text{spread}} - 0.4) \cdot 0.15 + A_{\text{feed}} \cdot 0.15$<br>$\text{Wet} = \text{baseWet} + \Delta \text{Wet} \cdot D_{\text{mod}}$ | Small colony is dry and intimate; sprawling, gorging colony immerses the space in lush ambient reverb. |
| **Feeding vs Exploration** ($A_{\text{feed}}$, $C_{\text{loco}}$) | **High Damping** ($\alpha_{\text{damp}}$) | $\alpha = \text{baseDamp} + (A_{\text{feed}} \cdot 0.16 + \Delta \text{spread} \cdot 0.12 - \Delta C_{\text{loco}} \cdot 0.10) \cdot D_{\text{mod}}$ | Active roaming brightens acoustic reflections; resting/grazing clusters damp high frequencies. |
| **Tendril Reach & Spatial Spread** ($d_s$, $d_{\text{spread}}$) | **Pre-Delay** ($t_{\text{pre}}$) | $t_{\text{pre}} = \text{basePre} + ((d_{\text{spread}} - 0.3) \cdot 15\text{ms} + \Delta d_s \cdot 10\text{ms}) \cdot D_{\text{mod}}$ | Extended arterial reach delays first reflections, physically expanding perceived virtual room boundaries. |
| **Colony Vitality & Network Bloom** | **Decay Time** ($T_{60}$) | $T_{60} = \text{baseT}_{60} + (\Delta \text{Mass} \cdot 0.7 + \Delta d_{\text{spread}} \cdot 0.5 + A_{\text{feed}} \cdot 0.4) \cdot D_{\text{mod}}$ | Massive organism blooms open decay length into cavernous space. |
| **Colony Mass Surge / Boom** | **Impulse Reseed** | Triggers asynchronous background IR rebuild upon population boom | Mitosis bursts inject distinct spatial reflections without halting audio playback. |


---

## 7. Master Dynamics Limiter & Padé Soft Knee

To protect against unexpected output spikes, the master bus routes through a studio dynamics limiter followed by a mathematical brickwall soft-knee ceiling:

### Envelope Follower
$$\text{absSample} = \max(|L|, |R|)$$
$$\text{env}_{t} = (\text{absSample} > \text{env}_{t-1}) \;?\; (\alpha_{\text{att}} \text{env} + (1-\alpha_{\text{att}})\text{absSample}) : (\alpha_{\text{rel}} \text{env} + (1-\alpha_{\text{rel}})\text{absSample})$$
*(Attack: $2\text{ ms}$, Release: $100\text{ ms}$)*

### Fast-Acting Limiter
$$\text{Gain}_{\text{limiter}} = (\text{env} > 0.75) \;?\; \frac{0.75}{\text{env}} : 1.0$$

### Padé Rational Tanh Approximation Soft Knee
To avoid expensive `Math.tanh()` calls ($88{,}000+$ per second), we evaluate a 4-multiplication Padé rational approximation:
$$\text{fastTanh}(x) = \begin{cases} -1.0 & x < -3.0 \\ 1.0 & x > 3.0 \\ x \cdot \frac{27 + x^2}{27 + 9x^2} & \text{otherwise} \end{cases}$$

Signals exceeding $0.85$ are gently curved below $0.98$:
$$\text{softKnee}(v) = (v > 0.85) \;?\; 0.85 + 0.13 \cdot \text{fastTanh}\left(\frac{v - 0.85}{0.13}\right) : \dots$$
Guarantees clean, zero-clipping 16-bit integer conversion without CPU stalls.
