# The Mathematics of Bell Acoustics: Volume and Harmonic Decay

When a bell is struck by its clapper, it produces a sound characterized by a complex combination of non-harmonic frequencies. Unlike a plucked guitar string, which produces integer-multiple harmonic overtones (e.g., $100\text{ Hz}$, $200\text{ Hz}$, $300\text{ Hz}$), the geometry of a bell forces the metal to vibrate in complex, inharmonic patterns known as **partials** or **vibrational modes**.

This document outlines the mathematical framework governing how the overall volume and these individual harmonic partials evolve during the initial strike and subsequent exponential decay.

---

## 1. The Physics of the Strike and Vibration

When the clapper strikes the bell, kinetic energy is transferred to the bell's body (the sound bow), causing the metal to deform elastically. This deformation excites numerous modes of vibration simultaneously.

Each vibrational mode $i$ has a distinct:
1.  **Frequency ($f_i$):** The rate of vibration, determining its perceived pitch.
2.  **Initial Amplitude ($A_{i,0}$):** The starting volume of that specific mode, determined by the strike force and the location of the strike relative to the mode's antinodes.
3.  **Phase ($\phi_i$):** The initial state of the vibration cycle.
4.  **Decay Time Constant ($\tau_i$):** The rate at which the mode loses energy.

The total acoustic pressure waveform, $P(t)$, perceived by the human ear is the linear superposition (sum) of all these decaying sinusoidal modes:

$$P(t) = \sum_{i=1}^{n} A_{i,0} e^{-t / \tau_i} \sin(2\pi f_i t + \phi_i)$$

Where $n$ represents the total number of excited vibrational modes.

---

## 2. Amplitude (Volume) Decay Over Time

The amplitude of any single partial $i$ does not ring indefinitely; it decays exponentially over time due to energy losses. These losses are primarily attributed to two factors:
*   **Internal Damping:** Friction within the crystalline structure of the metal alloy (usually bell bronze, roughly 80% copper and 20% tin) converting kinetic energy into heat.
*   **Acoustic Radiation:** The transfer of vibrational energy into the surrounding air to create the sound wave.

The amplitude envelope of a single partial $i$ is described by the exponential decay equation:

$$A_i(t) = A_{i,0} e^{-t / \tau_i}$$

Where:
*   $A_i(t)$ is the instantaneous amplitude of partial $i$ at time $t$.
*   $A_{i,0}$ is the initial amplitude at $t=0$.
*   $\tau_i$ is the time it takes for the amplitude to decay to $1/e$ (approximately $36.8\%$) of its initial value.

### Logarithmic Decay and Decibels

In acoustics, volume is perceived logarithmically. Therefore, the decay is often expressed in decibels ($\text{dB}$). The Sound Pressure Level ($\text{SPL}$) of a single partial decreases linearly over time:

$$\text{SPL}_i(t) = 20 \log_{10} \left( \frac{A_i(t)}{P_{\text{ref}}} \right)$$

Substituting the amplitude equation:

$$\text{SPL}_i(t) = 20 \log_{10} \left( \frac{A_{i,0} e^{-t / \tau_i}}{P_{\text{ref}}} \right)$$
$$\text{SPL}_i(t) = 20 \log_{10} \left( \frac{A_{i,0}}{P_{\text{ref}}} \right) - \left( \frac{20 \cdot t}{\tau_i \ln(10)} \right)$$

This shows a linear decay in volume ($\text{dB}$) at a rate inversely proportional to $\tau_i$.

---

## 3. Quality Factor (Q) and Frequency Dependency

The most significant characteristic of a bell's tone is that different frequencies decay at different rates. The decay time constant $\tau_i$ for each mode is mathematically related to its frequency ($f_i$) and the bell's **Quality Factor** ($Q_i$) for that specific mode:

$$\tau_i = \frac{Q_i}{\pi f_i}$$

*   **$Q_i$ (Quality Factor):** A dimensionless parameter that describes how under-damped the oscillator is. It represents the ratio of the energy stored in the oscillating system to the energy dissipated per cycle. Bell bronze has an exceptionally high $Q$, often in the thousands, allowing for a long sustain.
*   **$f_i$ (Frequency):** Because frequency is in the denominator, higher frequencies intrinsically have shorter decay times (assuming $Q$ is relatively constant or changes slowly across modes). 

Therefore, if $f_{\text{high}} > f_{\text{low}}$, then $\tau_{\text{high}} < \tau_{\text{low}}$. High notes die out faster than low notes.

---

## 4. The Harmonic Evolution of the Partials

A professionally tuned carillon bell is cast and then carefully lathed on the inside to align its primary partials into a recognizable musical structure. The five primary partials are:

| Partial Name | Musical Interval | Frequency Ratio | Typical Initial Amplitude ($A_0$) | Decay Rate ($\tau$) |
| :--- | :--- | :--- | :--- | :--- |
| **Hum** | Sub-octave | $f_0$ (e.g., $0.5 \cdot \text{Prime}$) | Low/Moderate | Very Long (Largest $\tau$) |
| **Prime** | Fundamental | $2f_0$ | Moderate | Long |
| **Tierce** | Minor Third | $\sim 2.4f_0$ | Moderate/High | Medium |
| **Quint** | Perfect Fifth | $\sim 3f_0$ | High | Short |
| **Nominal**| Octave | $4f_0$ | Very High | Very Short (Smallest $\tau$) |

*Note: The exact ratios depend on the specific tuning profile (e.g., Simpson tuning).*

### The Temporal Evolution of Timbre

Because $\tau_{\text{Nominal}} \ll \tau_{\text{Hum}}$, the spectral envelope (the "timbre" or tone color) of the bell changes dramatically over time. This evolution can be divided into three phases:

1.  **The Strike Phase ($t=0$ to $t=0.5\text{s}$):** 
    Immediately upon impact, the higher-frequency nominals and numerous untuned, high-frequency metallic "strike tones" are excited with a massive initial amplitude ($A_{i,0}$). The sound is bright, metallic, percussive, and highly dissonant. 
2.  **The Bloom Phase ($t=0.5\text{s}$ to $t=2\text{s}$):**
    The extremely high frequencies, having very small $\tau$ values, decay rapidly. As the percussive noise clears, the Prime, Tierce (giving the bell its characteristic minor-third sound), and Quint become the dominant auditory features. The true musical pitch of the bell is established here.
3.  **The Decay Phase ($t > 3\text{s}$):**
    The higher harmonic modes die out completely. The mathematical summation $P(t)$ simplifies as terms drop toward zero. The very last tone to ring out is purely the **Hum** (the lowest partial), which possesses the lowest frequency $f_0$ and therefore the largest decay time constant $\tau_0$.