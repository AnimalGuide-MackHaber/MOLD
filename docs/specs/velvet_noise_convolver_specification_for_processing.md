# Technical Specification: Algorithmic Velvet-Noise / Exponential Gaussian Convolver for Processing (Java)

## 1. System Overview & Objective

This specification details the mathematical architecture, memory models, DSP algorithms, and execution pipeline required to implement a zero-latency, high-diffusion algorithmic convolver in **Processing 4 (Java Desktop)**.

Standard comb/allpass reverberators (e.g., Schroeder/Freeverb) introduce modal ringing and flutter when driven by sustained sinusoidal and triangle wave bio-sonification feeds. This engine uses **synthetic Velvet Noise (VNS)** multiplied by an **exponential Gaussian energy envelope** and **frequency-dependent absorption damping** to generate a decorrelated stereo Impulse Response (IR) on demand, convolving incoming audio via **Uniform Partitioned Overlap-Add (UP-OLA)** in the frequency domain.

## 2. DSP & Mathematical Formulation

### 2.1. Velvet Noise Generator (VNS) Core

Velvet noise is a sparse, pseudo-random sequence consisting of discrete impulses of unit amplitude with randomized signs ($\pm 1$) distributed across uniform temporal grid cells.

1. **Grid Interval Calculation**:
   Given sample rate $f_s$ ($\text{Hz}$) and pulse density $D(t)$ ($\text{pulses/second}$), the average interval between pulses in samples is:
   

   $$
   T_d(t) = \frac{f_s}{D(t)}
   $$

2. **Temporal Grid & Jitter**:
   The impulse response buffer of total length $L = \lceil f_s \cdot T_{60} \rceil$ is partitioned into consecutive grid intervals $m \in [0, M-1]$. The sample position $k_m$ of the pulse inside grid cell $m$ is given by:
   

   $$
   k_m = \left\lfloor m \cdot T_d + r_m \cdot (T_d - 1) \right\rfloor
   $$

   
   where $r_m \sim \mathcal{U}(0, 1)$ is a uniform random variable.

3. **Randomized Sign**:
   Each pulse is assigned an independent sign:
   

   $$
   s_m \in \{-1, +1\}, \quad P(s_m = +1) = 0.5
   $$

4. **Logarithmic Density Progression**:
   To eliminate sparse graininess at the onset while maintaining low computational overhead, impulse density ramps from an initial density $D_0 \approx 2{,}000\text{ pulses/sec}$ up to $D_{\text{max}} \approx 10{,}000\text{ pulses/sec}$:
   

   $$
   D(t) = D_0 + (D_{\text{max}} - D_0) \cdot \left(\frac{t}{T_{60}}\right)^\gamma, \quad \gamma \approx 0.5
   $$

### 2.2. Exponential Gaussian Envelope & $T_{60}$ Calibration

The raw velvet sequence $v[n]$ is sculpted by a continuous decay envelope $E[n]$ such that energy reaches $-60\text{ dB}$ ($10^{-3}$ in amplitude) at $t = T_{60}$:

1. **Decay Constant**:
   

   $$
   \tau = \frac{T_{60}}{\ln(1000)} = \frac{T_{60}}{3 \cdot \ln(10)} \approx \frac{T_{60}}{6.907755}
   $$

2. **Envelope Function**:
   

   $$
   E[n] = \exp\left(-\frac{n}{f_s \cdot \tau}\right) = \exp\left(-\frac{6.907755 \cdot n}{f_s \cdot T_{60}}\right)
   $$

3. **Onset Shaping (Gaussian Attack / Pre-Delay)**:
   To prevent unnatural transient clipping at $n = 0$, an initial half-Gaussian curve shapes the onset for $t_{\text{attack}} \approx 5\text{ ms} - 15\text{ ms}$:
   

   $$
   A[n] = \begin{cases}     \exp\left(-\frac{(n - n_{\text{attack}})^2}{2 \sigma^2}\right) & n < n_{\text{attack}} \\    1.0 & n \ge n_{\text{attack}}    \end{cases}
   $$

   
   where $n_{\text{attack}} = \lfloor f_s \cdot t_{\text{attack}} \rfloor$ and $\sigma = \frac{n_{\text{attack}}}{3}$.

### 2.3. Frequency-Dependent Absorption (Air Damping)

High frequencies dissipate faster in physical spaces than low frequencies. This is modeled by running a backward-integrated one-pole low-pass filter across the impulse response:

$$
y[n] = (1 - \alpha[n]) \cdot x[n] + \alpha[n] \cdot y[n-1]
$$

Where the smoothing coefficient $\alpha[n]$ increases dynamically over time:

$$
\alpha[n] = \alpha_{\text{base}} + (\alpha_{\text{max}} - \alpha_{\text{base}}) \cdot \left(\frac{n}{L}\right)
$$


Typical ranges: $\alpha_{\text{base}} = 0.05$ (nearly unfiltered onset), $\alpha_{\text{max}} = 0.85$ (muffled tail).

### 2.4. True Stereo Decorrelation

To produce a 3D acoustic image without center clumping:

* Left Channel $h_L[n]$ and Right Channel $h_R[n]$ **must use distinct pseudo-random seeds** for both pulse position jitter $r_m$ and sign distribution $s_m$.

* Normalized Cross-Correlation (NCC) between $h_L$ and $h_R$ must satisfy:
  

  $$
  \rho_{LR} = \frac{\sum_{n=0}^{L-1} h_L[n] \cdot h_R[n]}{\sqrt{\sum h_L[n]^2 \cdot \sum h_R[n]^2}} < 0.05
  $$

## 3. Real-Time Convolution Pipeline: Uniform Partitioned Overlap-Add (UP-OLA)

Time-domain convolution $y[n] = \sum_{k=0}^{L-1} x[n-k]h[k]$ with $T_{60} = 4.0\text{s}$ at $44.1\text{ kHz}$ requires $\approx 176{,}400$ multiply-accumulate operations **per sample**, which is unviable in real-time Java.

The implementation must use **Uniform Partitioned Overlap-Add (UP-OLA)** in the frequency domain.

```
Incoming Stream x[n]
   │
   ▼
[Input Ring Buffer: Block Size B = 512]
   │
   ├─► Forward FFT(2B = 1024) ──► X_k (Frequency Domain)
   │                                  │
   │      ┌───────────────────────────┴───────────────────────────┐
   │      ▼                           ▼                           ▼
   │   [FD Delay Line: X_k]       [FD Delay Line: X_{k-1}]    [FD Delay Line: X_{k-(P-1)}]
   │      │                           │                           │
   │      ▼ (Complex Mult)            ▼ (Complex Mult)            ▼ (Complex Mult)
   │   [H_0 (IR Part 0)]          [H_1 (IR Part 1)]           [H_{P-1} (IR Part P-1)]
   │      │                           │                           │
   │      └───────────────────────────┼───────────────────────────┘
   │                                  ▼
   │                           Sum Spectrum Y_k
   │                                  │
   │                                  ▼
   │                        Inverse FFT(2B = 1024)
   │                                  │
   │                                  ▼
   │                        [Overlap-Add Accumulator]
   │                                  │
   ▼                                  ▼
[Dry Gain] ────────────────────────► (+) ──► Output Stream y[n]

```

### 3.1. Partitioning Math

1. Choose block size $B = 512$ samples (latency = $\frac{512}{44100} \approx 11.6\text{ ms}$).

2. FFT frame size: $N = 2B = 1024$ (zero-padded).

3. Number of partitions:
   

   $$
   P = \left\lceil \frac{L}{B} \right\rceil
   $$

4. Pre-transform each IR segment $p \in [0, P-1]$ of length $B$ (zero-padded to $N$) via FFT into static complex array $H_p[\omega]$.

## 4. Processing (Java) Target Implementation Architecture

The agent must create three clean, modular Java classes in the Processing sketchbook (`.pde` or `.java` files):

```
PhysarumBioSynth/
├── PhysarumBioSynth.pde       # Main sketch with UI and simulation
├── VelvetImpulseGenerator.java# Computes the synthetic IR buffers
├── FastFFT.java               # In-place radix-2 Cooley-Tukey FFT
└── PartitionedConvolver.java  # Real-time multi-channel block convolver

```

### 4.1. FastFFT.java Specification

Must provide zero-allocation, in-place forward and inverse FFT:

```
public final class FastFFT {
    // In-place Radix-2 Cooley-Tukey FFT
    // real and imag arrays must have length N = 2^k
    public static void fft(float[] real, float[] imag) { ... }
    public static void ifft(float[] real, float[] imag) { ... }
}

```

### 4.2. VelvetImpulseGenerator.java Specification

Responsible for synthesizing stereo IR buffers into float arrays:

```
public class VelvetImpulseGenerator {
    public static class StereoIR {
        public float[] left;
        public float[] right;
        public int length;
    }

    public static StereoIR generate(
        float sampleRate,
        float t60,
        float densityInitial,
        float densityMax,
        float highDamping,
        float preDelaySeconds,
        long seed
    ) {
        int totalSamples = (int)(sampleRate * t60);
        int preDelaySamples = (int)(sampleRate * preDelaySeconds);
        float[] irL = new float[totalSamples + preDelaySamples];
        float[] irR = new float[totalSamples + preDelaySamples];

        // 1. Generate Left Channel using seed
        // 2. Generate Right Channel using (seed ^ 0x5DEECE66DL)
        // 3. Apply logarithmic density distribution
        // 4. Multiply by exponential decay E[n]
        // 5. Apply backward one-pole filter for absorption
        // 6. Normalize peak gain to -3dBFS (0.707)
        
        StereoIR out = new StereoIR();
        out.left = irL;
        out.right = irR;
        out.length = irL.length;
        return out;
    }
}

```

### 4.3. PartitionedConvolver.java Specification

Handles the real-time block streaming without garbage collection allocations in the audio thread:

```
public class PartitionedConvolver {
    private final int blockSize; // B = 512
    private final int fftSize;   // 2B = 1024
    private int numPartitions;   // P

    // Frequency domain IR slices: [numPartitions][fftSize]
    private float[][] irPartitionsRealL, irPartitionsImagL;
    private float[][] irPartitionsRealR, irPartitionsImagR;

    // Delay line of input frequency domain blocks: [numPartitions][fftSize]
    private float[][] inputHistoryReal, inputHistoryImag;
    private int historyIndex = 0;

    // Output overlap-add tail buffers
    private float[] overlapL, overlapR;

    public PartitionedConvolver(int blockSize) {
        this.blockSize = blockSize;
        this.fftSize = blockSize * 2;
    }

    public void loadImpulseResponse(float[] irL, float[] irR) {
        // Partition buffers into blocks of size B, zero-pad to 2B,
        // perform forward FFT, and store into irPartitions arrays.
    }

    // Process a block of B input samples into B output samples
    public void processBlock(
        float[] inL, float[] inR, 
        float[] outL, float[] outR, 
        float wetMix, float dryMix
    ) {
        // Zero memory allocations in this method.
        // 1. Copy inL/inR to FFT buffers with zero padding.
        // 2. Compute FFT -> store in inputHistory at historyIndex.
        // 3. For each partition p in 0..P-1:
        //      Complex multiply inputHistory[(historyIndex - p + P) % P] by irPartitions[p].
        //      Accumulate into spectral accumulator arrays.
        // 4. IFFT on accumulator arrays.
        // 5. Overlap-add with previous tails.
        // 6. Blend dry and wet signals into outL/outR.
        // 7. Advance historyIndex = (historyIndex + 1) % P.
    }
}

```

## 5. Integration with the Processing Audio Graph

In Processing desktop, audio is processed via custom Java audio loops (such as `javax.sound.sampled` or Processing Sound library). Below is the required integration wrapper for raw stereo streams:

```
import javax.sound.sampled.*;

public class ReverbAudioEngine implements Runnable {
    private SourceDataLine line;
    private PartitionedConvolver convolver;
    private float wetLevel = 0.5f;
    private float dryLevel = 0.7f;
    private volatile boolean running = true;

    public void init(float sampleRate, float t60) {
        convolver = new PartitionedConvolver(512);
        VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(
            sampleRate, t60, 2000f, 10000f, 0.45f, 0.015f, 1337L
        );
        convolver.loadImpulseResponse(ir.left, ir.right);
        // Initialize 16-bit stereo SourceDataLine at sampleRate...
    }

    public void setBioTelemetry(float totalColonyMass, float explorationRate) {
        // Dynamic cross-modulation:
        // As colony mass increases, room wetness and decay bloom open
        this.wetLevel = constrain(map(totalColonyMass, 500, 25000, 0.15f, 0.85f), 0.0f, 1.0f);
        this.dryLevel = 1.0f - (this.wetLevel * 0.4f);
    }
}

```

## 6. Bio-Sonification Modulation Bindings

The AI coding agent must bind the simulation state variables to the reverberator using the following modulation transfer functions:

| Slime Mold Metric | Reverb Parameter | Transfer Function / Range | Sonic Effect | 
| ----- | ----- | ----- | ----- | 
| **Total Colony Biomass** | Wet / Dry Balance | $Wet = \tanh\left(\frac{Biomass}{10000}\right) \cdot 0.8$ | Small colony sounds direct and intimate; thriving network becomes a cavernous bath. | 
| **Locomotion Exploration Cost** | High-Frequency Damping ($\alpha_{\text{max}}$) | $\alpha_{\text{max}} = 0.2 + 0.6 \cdot \left(\frac{Cost}{0.1}\right)$ | Active exploration brightens early reflections; static grazing dampens high frequencies. | 
| **Longest Active Artery (Tendril Reach)** | Pre-Delay ($t_{\text{pre}}$) | $t_{\text{pre}} = 5\text{ ms} + \left(\frac{Reach}{45\text{ px}}\right) \cdot 40\text{ ms}$ | Extended searching tendrils push perceived virtual room boundaries outward. | 
| **Mitosis Burst Event** | Impulse Seed Re-trigger | Regenerate IR with new seed on mass doubling | Subtle morphological shift in room geometry during population booms. | 

## 7. Verification & Acceptance Criteria for Coding Agent

When the coding agent implements this specification, the solution must satisfy the following automated assertions:

1. **Zero Heap Allocation in Audio Thread**:

   * Running `processBlock()` for $10{,}000$ consecutive blocks must generate **0 bytes** of heap allocation (no `new float[]`, no object boxing).

2. **Impulse Response Sparsity & Decorrelation**:

   * Normalized cross-correlation $\rho_{LR}$ between Left and Right generated buffers must be $< 0.05$.

   * Energy decay curve must follow linear regression slope in $\text{dB}$ equivalent to $-60\text{ dB} \pm 1.5\text{ dB}$ across the specified $T_{60}$ interval.

3. **Latency Bound**:

   * End-to-end algorithmic latency must not exceed $B = 512$ samples ($\approx 11.6\text{ ms}$ at $44.1\text{ kHz}$).

4. **Spectral Flatness (Zero Comb Filtering)**:

   * When a pure $440\text{ Hz}$ sine wave or $220\text{ Hz}$ triangle wave is processed through the convolver with $100\%$ wet mix, the output magnitude spectrum must show smooth, continuous dispersion without isolated comb notch dropouts exceeding $6\text{ dB}$.