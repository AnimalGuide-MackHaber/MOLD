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

    // Delay line of input frequency domain blocks: [numPartitions][fftSize]
    private float[][] inputHistoryReal, inputHistoryImag;
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

        float[][] newIrRealL = new float[P][fftSize];
        float[][] newIrImagL = new float[P][fftSize];
        float[][] newIrRealR = new float[P][fftSize];
        float[][] newIrImagR = new float[P][fftSize];

        float[][] newInputReal = new float[P][fftSize];
        float[][] newInputImag = new float[P][fftSize];

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
            this.inputHistoryReal = newInputReal;
            this.inputHistoryImag = newInputImag;
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

            float[] curInReal = inputHistoryReal[historyIndex];
            float[] curInImag = inputHistoryImag[historyIndex];

            // 1. Copy inL/inR to FFT buffers with zero padding
            for (int i = 0; i < blockSize; i++) {
                curInReal[i] = 0.5f * (inL[i] + inR[i]);
                curInImag[i] = 0.0f;
            }
            for (int i = blockSize; i < fftSize; i++) {
                curInReal[i] = 0.0f;
                curInImag[i] = 0.0f;
            }

            // 2. Compute Forward FFT -> stored in inputHistory at historyIndex
            FastFFT.fft(curInReal, curInImag);

            // 3. Spectral accumulation: sum_p (X_{k-p} * H_p)
            Arrays.fill(accRealL, 0.0f);
            Arrays.fill(accImagL, 0.0f);
            Arrays.fill(accRealR, 0.0f);
            Arrays.fill(accImagR, 0.0f);

            final int P = numPartitions;
            for (int p = 0; p < P; p++) {
                int hIdx = (historyIndex - p + P) % P;
                float[] xR = inputHistoryReal[hIdx];
                float[] xI = inputHistoryImag[hIdx];

                float[] hRL = irPartitionsRealL[p];
                float[] hIL = irPartitionsImagL[p];
                float[] hRR = irPartitionsRealR[p];
                float[] hIR = irPartitionsImagR[p];

                for (int k = 0; k < fftSize; k++) {
                    float xr = xR[k];
                    float xi = xI[k];

                    // Left channel complex multiply: (xr + j*xi) * (hrl + j*hil)
                    accRealL[k] += xr * hRL[k] - xi * hIL[k];
                    accImagL[k] += xr * hIL[k] + xi * hRL[k];

                    // Right channel complex multiply: (xr + j*xi) * (hrr + j*hir)
                    accRealR[k] += xr * hRR[k] - xi * hIR[k];
                    accImagR[k] += xr * hIR[k] + xi * hRR[k];
                }
            }

            // 4. Inverse FFT on spectral accumulator arrays
            FastFFT.ifft(accRealL, accImagL);
            FastFFT.ifft(accRealR, accImagR);

            // 5 & 6. Overlap-add with previous tails and blend dry/wet
            for (int i = 0; i < blockSize; i++) {
                outL[i] = inL[i] * dryMix + (accRealL[i] + overlapL[i]) * wetMix;
                overlapL[i] = accRealL[blockSize + i];

                outR[i] = inR[i] * dryMix + (accRealR[i] + overlapR[i]) * wetMix;
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
