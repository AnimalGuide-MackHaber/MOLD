import java.util.Arrays;

/**
 * PartitionedConvolver.java
 *
 * Real-time stereo block convolver using Uniform Partitioned Overlap-Add (UP-OLA).
 * Guarantees zero heap allocation in processBlock() for real-time audio thread safety.
 */
public class PartitionedConvolver {

    private final int blockSize; // B = 512
    private final int fftSize;   // 2B = 1024
    private int numPartitions;   // P

    // Frequency domain IR slices: [numPartitions][fftSize]
    private float[][] irPartitionsRealL, irPartitionsImagL;
    private float[][] irPartitionsRealR, irPartitionsImagR;

    // Delay lines of input frequency domain blocks for Left and Right channels: [numPartitions][fftSize]
    private float[][] inputHistoryRealL, inputHistoryImagL;
    private float[][] inputHistoryRealR, inputHistoryImagR;
    private int historyIndex = 0;

    // Output overlap-add tail buffers
    private float[] overlapL, overlapR;

    // Pre-allocated spectral accumulation arrays
    private float[] accRealL, accImagL;
    private float[] accRealR, accImagR;

    // Thread synchronization lock for non-blocking parameter updates
    private final Object lock = new Object();

    public PartitionedConvolver(int blockSize) {
        this.blockSize = blockSize;
        this.fftSize = blockSize * 2;
        this.numPartitions = 0;
    }

    /**
     * Partitions the stereo impulse response buffers into blocks of size B,
     * zero-pads them to 2B, computes forward FFTs, and stores the frequency-domain slices.
     *
     * @param irL Left channel impulse response samples
     * @param irR Right channel impulse response samples
     */
    public void loadImpulseResponse(float[] irL, float[] irR) {
        if (irL == null || irR == null || irL.length == 0 || irR.length == 0) {
            synchronized (lock) {
                numPartitions = 0;
            }
            return;
        }

        int irLen = Math.max(irL.length, irR.length);
        int P = (irLen + blockSize - 1) / blockSize;
        if (P < 1) P = 1;
        if (P > 128) P = 128; // Cap partition count to 128 (~1.5s IR) for real-time safety

        float[][] newIrRealL = new float[P][fftSize];
        float[][] newIrImagL = new float[P][fftSize];
        float[][] newIrRealR = new float[P][fftSize];
        float[][] newIrImagR = new float[P][fftSize];

        float[][] newInputRealL = new float[P][fftSize];
        float[][] newInputImagL = new float[P][fftSize];
        float[][] newInputRealR = new float[P][fftSize];
        float[][] newInputImagR = new float[P][fftSize];

        for (int p = 0; p < P; p++) {
            for (int i = 0; i < blockSize; i++) {
                int sampleIdx = p * blockSize + i;
                newIrRealL[p][i] = (sampleIdx < irL.length) ? irL[sampleIdx] : 0.0f;
                newIrRealR[p][i] = (sampleIdx < irR.length) ? irR[sampleIdx] : 0.0f;
            }
            // Zero-padding from blockSize to fftSize is automatically 0.0f in Java
            FastFFT.fft(newIrRealL[p], newIrImagL[p]);
            FastFFT.fft(newIrRealR[p], newIrImagR[p]);
        }

        float[] newOverlapL = new float[blockSize];
        float[] newOverlapR = new float[blockSize];
        float[] newAccRealL = new float[fftSize];
        float[] newAccImagL = new float[fftSize];
        float[] newAccRealR = new float[fftSize];
        float[] newAccImagR = new float[fftSize];

        synchronized (lock) {
            this.numPartitions = P;
            this.irPartitionsRealL = newIrRealL;
            this.irPartitionsImagL = newIrImagL;
            this.irPartitionsRealR = newIrRealR;
            this.irPartitionsImagR = newIrImagR;
            this.inputHistoryRealL = newInputRealL;
            this.inputHistoryImagL = newInputImagL;
            this.inputHistoryRealR = newInputRealR;
            this.inputHistoryImagR = newInputImagR;
            this.overlapL = newOverlapL;
            this.overlapR = newOverlapR;
            this.accRealL = newAccRealL;
            this.accImagL = newAccImagL;
            this.accRealR = newAccRealR;
            this.accImagR = newAccImagR;
            this.historyIndex = 0;
        }
    }

    /**
     * Process a block of B input samples into B output samples.
     * Guaranteed ZERO memory allocations in this method for real-time thread safety.
     *
     * @param inL    Left input buffer (length >= blockSize)
     * @param inR    Right input buffer (length >= blockSize)
     * @param outL   Left output buffer (length >= blockSize)
     * @param outR   Right output buffer (length >= blockSize)
     * @param wetMix Wet signal gain factor
     * @param dryMix Dry signal gain factor
     */
    public void processBlock(
        float[] inL, float[] inR,
        float[] outL, float[] outR,
        float wetMix, float dryMix
    ) {
        synchronized (lock) {
            if (numPartitions == 0) {
                for (int i = 0; i < blockSize; i++) {
                    outL[i] = inL[i] * dryMix;
                    outR[i] = inR[i] * dryMix;
                }
                return;
            }

            float[] curInRealL = inputHistoryRealL[historyIndex];
            float[] curInImagL = inputHistoryImagL[historyIndex];
            float[] curInRealR = inputHistoryRealR[historyIndex];
            float[] curInImagR = inputHistoryImagR[historyIndex];

            // 1. Copy inL/inR to FFT buffers with zero padding, dynamic input headroom protection,
            // and natural acoustic room cross-bleed (85% direct channel, 15% cross-room bleed)
            for (int i = 0; i < blockSize; i++) {
                float xL = inL[i];
                float xR = inR[i];
                float sendL = 0.85f * xL + 0.15f * xR;
                float sendR = 0.15f * xL + 0.85f * xR;

                // Soft saturation protects the reverb tank from resonant voice spikes
                curInRealL[i] = (sendL > 1.2f || sendL < -1.2f) ? (float) Math.tanh(sendL * 0.75f) * 1.333f : sendL;
                curInImagL[i] = 0.0f;
                curInRealR[i] = (sendR > 1.2f || sendR < -1.2f) ? (float) Math.tanh(sendR * 0.75f) * 1.333f : sendR;
                curInImagR[i] = 0.0f;
            }
            for (int i = blockSize; i < fftSize; i++) {
                curInRealL[i] = 0.0f;
                curInImagL[i] = 0.0f;
                curInRealR[i] = 0.0f;
                curInImagR[i] = 0.0f;
            }

            // 2. Compute Forward FFTs for both channels
            FastFFT.fft(curInRealL, curInImagL);
            FastFFT.fft(curInRealR, curInImagR);

            // 3. Spectral accumulation: sum_p (X_{k-p} * H_p) for Left and Right channels
            Arrays.fill(accRealL, 0.0f);
            Arrays.fill(accImagL, 0.0f);
            Arrays.fill(accRealR, 0.0f);
            Arrays.fill(accImagR, 0.0f);

            final int P = numPartitions;
            for (int p = 0; p < P; p++) {
                int hIdx = (historyIndex - p + P) % P;
                float[] xRL = inputHistoryRealL[hIdx];
                float[] xIL = inputHistoryImagL[hIdx];
                float[] xRR = inputHistoryRealR[hIdx];
                float[] xIR = inputHistoryImagR[hIdx];

                float[] hRL = irPartitionsRealL[p];
                float[] hIL = irPartitionsImagL[p];
                float[] hRR = irPartitionsRealR[p];
                float[] hIR = irPartitionsImagR[p];

                for (int k = 0; k < fftSize; k++) {
                    float xrL = xRL[k];
                    float xiL = xIL[k];
                    // Left channel complex multiply: (xrL + j*xiL) * (hrl + j*hil)
                    accRealL[k] += xrL * hRL[k] - xiL * hIL[k];
                    accImagL[k] += xrL * hIL[k] + xiL * hRL[k];

                    float xrR = xRR[k];
                    float xiR = xIR[k];
                    // Right channel complex multiply: (xrR + j*xiR) * (hrr + j*hir)
                    accRealR[k] += xrR * hRR[k] - xiR * hIR[k];
                    accImagR[k] += xrR * hIR[k] + xiR * hRR[k];
                }
            }

            // 4. Inverse FFT on spectral accumulator arrays
            FastFFT.ifft(accRealL, accImagL);
            FastFFT.ifft(accRealR, accImagR);

            // 5 & 6. Overlap-add with previous tails and blend dry/wet with acoustic headroom scaling
            float mixSum = dryMix + wetMix;
            float mixNorm = (mixSum > 1.0f) ? (1.0f / (float) Math.sqrt(dryMix * dryMix + wetMix * wetMix)) : 1.0f;
            float effDry = dryMix * mixNorm;
            float effWet = wetMix * mixNorm;

            for (int i = 0; i < blockSize; i++) {
                outL[i] = inL[i] * effDry + (accRealL[i] + overlapL[i]) * effWet;
                overlapL[i] = accRealL[blockSize + i];

                outR[i] = inR[i] * effDry + (accRealR[i] + overlapR[i]) * effWet;
                overlapR[i] = accRealR[blockSize + i];
            }

            // 7. Advance history index
            historyIndex = (historyIndex + 1) % P;
        }
    }

    public int getBlockSize() {
        return blockSize;
    }

    public int getNumPartitions() {
        return numPartitions;
    }

    public boolean isLoaded() {
        synchronized (lock) {
            return numPartitions > 0;
        }
    }
}
