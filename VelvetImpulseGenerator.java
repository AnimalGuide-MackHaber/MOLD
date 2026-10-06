import java.util.Random;

/**
 * VelvetImpulseGenerator.java
 *
 * Synthesizes decorrelated stereo impulse responses using synthetic Velvet Noise (VNS),
 * an exponential Gaussian energy decay envelope, and frequency-dependent absorption damping.
 */
public class VelvetImpulseGenerator {

    public static class StereoIR {
        public float[] left;
        public float[] right;
        public int length;
    }

    /**
     * Synthesizes a decorrelated stereo impulse response buffer.
     *
     * @param sampleRate        Sampling rate in Hz (e.g. 44100.0f)
     * @param t60               Reverberation time to -60dB in seconds (e.g. 3.5f)
     * @param densityInitial    Initial pulse density at onset (pulses/sec, ~2000)
     * @param densityMax        Maximum pulse density in late tail (pulses/sec, ~10000)
     * @param highDamping       High-frequency absorption coefficient alpha_max [0.05, 0.95]
     * @param preDelaySeconds   Initial pre-delay silence in seconds (e.g. 0.015f)
     * @param seed              Base pseudo-random seed
     * @return StereoIR containing left and right channels and total length
     */
    public static StereoIR generate(
        float sampleRate,
        float t60,
        float densityInitial,
        float densityMax,
        float highDamping,
        float preDelaySeconds,
        long seed
    ) {
        if (sampleRate <= 0.0f) sampleRate = 44100.0f;
        if (t60 <= 0.05f) t60 = 0.05f;
        if (densityInitial <= 100.0f) densityInitial = 100.0f;
        if (densityMax < densityInitial) densityMax = densityInitial;
        if (preDelaySeconds < 0.0f) preDelaySeconds = 0.0f;

        int totalSamples = Math.max(1, (int)(sampleRate * t60));
        int preDelaySamples = Math.max(0, (int)(sampleRate * preDelaySeconds));
        int totalLength = totalSamples + preDelaySamples;

        float[] irL = new float[totalLength];
        float[] irR = new float[totalLength];

        // 1. Generate Left Channel using seed
        generateChannel(irL, preDelaySamples, totalSamples, sampleRate, t60,
                        densityInitial, densityMax, highDamping, seed);

        // 2. Generate Right Channel using decorrelated seed (seed ^ 0x5DEECE66DL)
        generateChannel(irR, preDelaySamples, totalSamples, sampleRate, t60,
                        densityInitial, densityMax, highDamping, seed ^ 0x5DEECE66DL);

        // 6. Normalize peak gain to -3dBFS (10^(-3/20) ~ 0.70710678)
        float maxPeak = 0.0f;
        for (int i = 0; i < totalLength; i++) {
            float absL = Math.abs(irL[i]);
            if (absL > maxPeak) maxPeak = absL;
            float absR = Math.abs(irR[i]);
            if (absR > maxPeak) maxPeak = absR;
        }

        if (maxPeak > 1e-7f) {
            float normScale = 0.70710678f / maxPeak;
            for (int i = 0; i < totalLength; i++) {
                irL[i] *= normScale;
                irR[i] *= normScale;
            }
        }

        StereoIR out = new StereoIR();
        out.left = irL;
        out.right = irR;
        out.length = totalLength;
        return out;
    }

    private static void generateChannel(
        float[] buffer,
        int preDelaySamples,
        int totalSamples,
        float sampleRate,
        float t60,
        float densityInitial,
        float densityMax,
        float highDamping,
        long seed
    ) {
        Random rng = new Random(seed);
        float[] rawPulses = new float[totalSamples];

        // 3. Temporal Grid & Logarithmic Density Progression:
        // D(t) = D0 + (Dmax - D0) * (t / T60)^gamma, gamma = 0.5
        int currSample = 0;
        while (currSample < totalSamples) {
            float t = (float) currSample / sampleRate;
            float normT = Math.min(1.0f, Math.max(0.0f, t / t60));
            float d = densityInitial + (densityMax - densityInitial) * (float) Math.sqrt(normT);
            int td = Math.max(1, Math.round(sampleRate / d));

            int jitter = (td > 1) ? (int)(rng.nextFloat() * (td - 1)) : 0;
            int pulsePos = currSample + jitter;
            float sign = rng.nextBoolean() ? 1.0f : -1.0f;

            if (pulsePos < totalSamples) {
                rawPulses[pulsePos] = sign;
            }
            currSample += td;
        }

        // 4. Exponential Decay E[n] & Gaussian Attack Onset Shaping A[n]
        // E[n] = exp(-6.907755 * n / (fs * T60))
        // Half-Gaussian attack over tAttack ~ 10ms
        float tAttack = Math.min(0.010f, t60 * 0.1f);
        int nAttack = Math.max(1, (int)(sampleRate * tAttack));
        float sigma = nAttack / 3.0f;
        float twoSigmaSq = 2.0f * sigma * sigma;

        for (int n = 0; n < totalSamples; n++) {
            if (rawPulses[n] == 0.0f) continue;

            float decayEnv = (float) Math.exp(-6.907755f * n / (sampleRate * t60));
            if (n < nAttack) {
                float diff = n - nAttack;
                float attackEnv = (float) Math.exp(-(diff * diff) / twoSigmaSq);
                decayEnv *= attackEnv;
            }
            rawPulses[n] *= decayEnv;
        }

        // 5. Frequency-Dependent Absorption Damping (Backward-Euler One-Pole Filter)
        // y[n] = (1 - alpha[n]) * x[n] + alpha[n] * y[n-1]
        // alpha[n] = alpha_base + (alpha_max - alpha_base) * (n / L)
        float alphaBase = 0.05f;
        float alphaMax = Math.min(0.95f, Math.max(0.05f, highDamping));
        float yPrev = 0.0f;

        for (int n = 0; n < totalSamples; n++) {
            float alpha = alphaBase + (alphaMax - alphaBase) * ((float) n / (float) totalSamples);
            float y = (1.0f - alpha) * rawPulses[n] + alpha * yPrev;
            yPrev = y;
            buffer[preDelaySamples + n] = y;
        }
    }
}
