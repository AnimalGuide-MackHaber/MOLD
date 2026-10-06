/**
 * FastFFT.java
 *
 * Zero-allocation, in-place Radix-2 Cooley-Tukey Fast Fourier Transform (FFT)
 * and Inverse Fast Fourier Transform (IFFT) for real and imaginary float arrays.
 * Array length N must be a power of two (N = 2^k).
 */
public final class FastFFT {

    private FastFFT() {
        // Utility class
    }

    /**
     * In-place Forward FFT.
     * Computes X[k] = sum_{n=0}^{N-1} x[n] * exp(-j * 2 * pi * k * n / N)
     *
     * @param real Real components of input/output signal (length N = 2^k)
     * @param imag Imaginary components of input/output signal (length N = 2^k)
     */
    public static void fft(float[] real, float[] imag) {
        transform(real, imag, false);
    }

    /**
     * In-place Inverse FFT with 1/N normalization.
     * Computes x[n] = (1/N) * sum_{k=0}^{N-1} X[k] * exp(+j * 2 * pi * k * n / N)
     *
     * @param real Real components of input spectrum / output signal (length N = 2^k)
     * @param imag Imaginary components of input spectrum / output signal (length N = 2^k)
     */
    public static void ifft(float[] real, float[] imag) {
        transform(real, imag, true);
    }

    private static void transform(float[] real, float[] imag, boolean inverse) {
        int n = real.length;
        if (n <= 1) return;

        // In-place Bit-Reversal Permutation
        int j = 0;
        for (int i = 0; i < n - 1; i++) {
            if (i < j) {
                float tr = real[i];
                real[i] = real[j];
                real[j] = tr;

                float ti = imag[i];
                imag[i] = imag[j];
                imag[j] = ti;
            }
            int k = n >> 1;
            while (k <= j) {
                j -= k;
                k >>= 1;
            }
            j += k;
        }

        // Cooley-Tukey Radix-2 Butterfly Computation
        for (int len = 2; len <= n; len <<= 1) {
            double angle = (inverse ? 2.0 * Math.PI : -2.0 * Math.PI) / len;
            float wStepR = (float) Math.cos(angle);
            float wStepI = (float) Math.sin(angle);
            int halfLen = len >> 1;

            for (int i = 0; i < n; i += len) {
                float wR = 1.0f;
                float wI = 0.0f;

                for (int k = 0; k < halfLen; k++) {
                    int uIdx = i + k;
                    int vIdx = i + k + halfLen;

                    float uR = real[uIdx];
                    float uI = imag[uIdx];
                    float vR = real[vIdx];
                    float vI = imag[vIdx];

                    // Complex multiply: v * w
                    float tr = vR * wR - vI * wI;
                    float ti = vR * wI + vI * wR;

                    real[uIdx] = uR + tr;
                    imag[uIdx] = uI + ti;
                    real[vIdx] = uR - tr;
                    imag[vIdx] = uI - ti;

                    // Update twiddle factor
                    float nextWR = wR * wStepR - wI * wStepI;
                    float nextWI = wR * wStepI + wI * wStepR;
                    wR = nextWR;
                    wI = nextWI;
                }
            }
        }

        // Apply 1/N scaling for inverse FFT
        if (inverse) {
            float invN = 1.0f / n;
            for (int i = 0; i < n; i++) {
                real[i] *= invN;
                imag[i] *= invN;
            }
        }
    }
}
