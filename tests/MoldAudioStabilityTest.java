import java.util.Random;

/**
 * MoldAudioStabilityTest.java
 *
 * Automated verification of Audio Engine stability and DSP invariants:
 * 1. Biquad lowpass filter numerical stability & algebraic saturation bounds under extreme Q and cutoffs
 * 2. Studio Master Dynamics Limiter brickwall bounds (<= 0.92) under severe multi-voice overload (+36 dBFS)
 * 3. Exhaustive harmonic tuning matrix coverage across all 12 root keys, 6 scales, 3 octave shifts, and 64 cells
 * 4. Bio-sonification telemetry stability and boundary containment under extreme colony biomass conditions
 */
public class MoldAudioStabilityTest {

    public static void main(String[] args) {
        System.out.println("================================================================================");
        System.out.println("MOLD AUDIO STABILITY & DSP INVARIANTS TEST SUITE");
        System.out.println("================================================================================");

        boolean allPassed = true;

        allPassed &= testBiquadFilterStabilityAndSaturation();
        allPassed &= testStudioMasterLimiterBrickwall();
        allPassed &= testHarmonicTuningMatrixFullCoverage();
        allPassed &= testReverbBioTelemetryStress();

        System.out.println("================================================================================");
        if (allPassed) {
            System.out.println(">> ALL AUDIO STABILITY & DSP INVARIANTS PASSED! <<");
        } else {
            System.err.println(">> ONE OR MORE AUDIO INVARIANT CHECKS FAILED! <<");
            System.exit(1);
        }
        System.out.println("================================================================================");
    }

    private static boolean testBiquadFilterStabilityAndSaturation() {
        System.out.println("\n[Audio Test 1] Verifying BiquadFilter Numerical Stability & Algebraic Saturation...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        MoldSketch.BiquadFilter filter = s.new BiquadFilter();

        float[] testCutoffs = {20.0f, 40.0f, 100.0f, 1000.0f, 10000.0f, 19000.0f, 22000.0f};
        float[] testQs = {0.1f, 0.5f, 1.0f, 5.0f, 18.0f, 50.0f};

        Random rng = new Random(1337);

        for (float cutoff : testCutoffs) {
            for (float q : testQs) {
                filter.setLowPass(cutoff, q, 44100.0f);

                // 1. Impulse test
                float outImpulse = filter.process(1.0f);
                if (Float.isNaN(outImpulse) || Float.isInfinite(outImpulse)) {
                    throw new AssertionError("BiquadFilter NaN/Inf on impulse at cutoff=" + cutoff + ", Q=" + q);
                }
                for (int i = 0; i < 200; i++) {
                    float out = filter.process(0.0f);
                    if (Float.isNaN(out) || Float.isInfinite(out)) {
                        throw new AssertionError("BiquadFilter tail NaN/Inf at cutoff=" + cutoff + ", Q=" + q);
                    }
                }

                // 2. High-energy DC offset / overdrive test (+50.0)
                for (int i = 0; i < 100; i++) {
                    float out = filter.process(50.0f);
                    if (Float.isNaN(out) || Float.isInfinite(out)) {
                        throw new AssertionError("BiquadFilter DC overload produced NaN/Inf");
                    }
                    if (Math.abs(out) > 3.5f) {
                        throw new AssertionError("BiquadFilter saturation failed to bound DC output: " + out);
                    }
                }

                // 3. White noise stress test
                for (int i = 0; i < 500; i++) {
                    float in = (rng.nextFloat() * 20.0f) - 10.0f;
                    float out = filter.process(in);
                    if (Float.isNaN(out) || Float.isInfinite(out)) {
                        throw new AssertionError("BiquadFilter noise burst produced NaN/Inf");
                    }
                    if (Math.abs(out) > 3.5f) {
                        throw new AssertionError("BiquadFilter saturation failed to bound noise output: " + out);
                    }
                }
            }
        }

        System.out.println("  PASS: BiquadFilter evaluated across 42 cutoff/Q combinations with zero NaNs, zero Infs, and strict saturation bounds (|out| <= 3.5).");
        return true;
    }

    private static boolean testStudioMasterLimiterBrickwall() {
        System.out.println("\n[Audio Test 2] Verifying StudioMasterLimiter Brickwall Bounds Under Extreme Overload...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        MoldSketch.StudioMasterLimiter limiter = s.new StudioMasterLimiter(44100.0f);

        final int B = 512;
        float[] inL = new float[B];
        float[] inR = new float[B];
        float[] outL = new float[B];
        float[] outR = new float[B];

        // Severe Multi-Voice Overload (+36 dBFS): 64 simultaneous voices summed at full amplitude
        for (int i = 0; i < B; i++) {
            inL[i] = (i % 2 == 0 ? 64.0f : -64.0f);
            inR[i] = inL[i];
        }

        // Process 100 consecutive overload blocks (~1.16 seconds of brutal clipping input)
        for (int block = 0; block < 100; block++) {
            limiter.process(inL, inR, outL, outR, B);

            for (int i = 0; i < B; i++) {
                float sampleL = outL[i];
                float sampleR = outR[i];

                if (Float.isNaN(sampleL) || Float.isNaN(sampleR) ||
                    Float.isInfinite(sampleL) || Float.isInfinite(sampleR)) {
                    throw new AssertionError("Limiter produced NaN or Inf at block " + block + ", sample " + i);
                }

                if (Math.abs(sampleL) > 0.92001f || Math.abs(sampleR) > 0.92001f) {
                    throw new AssertionError("Limiter brickwall violated: L=" + sampleL + ", R=" + sampleR + " (exceeded 0.92 ceiling)");
                }
            }
        }

        // Verify recovery after overload drops back to normal level (-12 dBFS)
        for (int i = 0; i < B; i++) {
            inL[i] = 0.25f * (float) Math.sin(i * 0.1);
            inR[i] = inL[i];
        }
        for (int block = 0; block < 50; block++) {
            limiter.process(inL, inR, outL, outR, B);
        }

        float recoveredPeak = 0.0f;
        for (int i = 0; i < B; i++) {
            recoveredPeak = Math.max(recoveredPeak, Math.abs(outL[i]));
        }
        MoldTestUtils.assertTrue(recoveredPeak > 0.15f, "Limiter gain should smoothly recover after overload ends (got peak " + recoveredPeak + ")");

        System.out.println("  PASS: StudioMasterLimiter maintained strictly bounded output ([-0.92, +0.92]) under +36 dBFS overload and recovered smoothly.");
        return true;
    }

    private static boolean testHarmonicTuningMatrixFullCoverage() {
        System.out.println("\n[Audio Test 3] Exhaustive Harmonic Tuning Matrix Verification (13,824 cell configurations)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();

        int checkedConfigurations = 0;

        for (int rootKey = 0; rootKey < 12; rootKey++) {
            s.keyRootIndex = rootKey;
            for (int scaleIdx = 0; scaleIdx < 6; scaleIdx++) {
                s.currentScaleIdx = scaleIdx;
                for (int octShift = 0; octShift < 3; octShift++) {
                    s.octaveShiftIdx = octShift;

                    for (int r = 0; r < 8; r++) {
                        for (int c = 0; c < 8; c++) {
                            MoldSketch.HarmonicData hd = s.getCellHarmonics(c, r);
                            float freq = hd.freq;

                            if (Float.isNaN(freq) || Float.isInfinite(freq)) {
                                throw new AssertionError("Harmonic freq NaN/Inf at root=" + rootKey + ", scale=" + scaleIdx + ", oct=" + octShift + ", r=" + r + ", c=" + c);
                            }

                            // Must be within audible human hearing range (20Hz - 20,000Hz)
                            if (freq < 20.0f || freq > 20000.0f) {
                                throw new AssertionError("Harmonic freq outside audible band: " + freq + " Hz at root=" + rootKey + ", scale=" + scaleIdx + ", oct=" + octShift + ", cell (" + c + ", " + r + ")");
                            }

                            if (hd.label == null || hd.label.trim().isEmpty()) {
                                throw new AssertionError("Missing note label for cell (" + c + ", " + r + ")");
                            }

                            if (hd.hz != Math.round(freq)) {
                                throw new AssertionError("hd.hz (" + hd.hz + ") does not match rounded freq (" + Math.round(freq) + ")");
                            }

                            checkedConfigurations++;
                        }
                    }
                }
            }
        }

        System.out.println("  PASS: All " + checkedConfigurations + " harmonic cell combinations generated valid audible frequencies (20Hz <= f <= 20kHz) and clean labels.");
        return true;
    }

    private static boolean testReverbBioTelemetryStress() {
        System.out.println("\n[Audio Test 4] Verifying Reverb Bio-Telemetry Under Boundary Biomass States...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();

        float[] modDepths = {0.0f, 1.0f, 2.0f, 4.0f};
        float[] testBiomasses = {0.0f, 500.0f, 800000.0f, 5000000.0f};

        for (float depth : modDepths) {
            s.reverbBioModDepth = depth;
            for (float mass : testBiomasses) {
                for (int i = 0; i < 64; i++) {
                    s.cellBiomass[i] = mass / 64.0f;
                }

                for (int step = 0; step < 50; step++) {
                    s.updateReverbBioTelemetry();
                }

                MoldTestUtils.assertInRange(s.reverbWet, 0.0f, 1.0f, "reverbWet");
                MoldTestUtils.assertInRange(s.reverbDry, 0.05f, 1.0f, "reverbDry");
                MoldTestUtils.assertInRange(s.reverbT60, 0.5f, 4.0f, "reverbT60");
                MoldTestUtils.assertInRange(s.reverbHighDamping, 0.05f, 0.95f, "reverbHighDamping");
                MoldTestUtils.assertInRange(s.reverbPreDelay, 0.005f, 0.060f, "reverbPreDelay");
            }
        }

        System.out.println("  PASS: Reverb bio-telemetry modulation bounded strictly within safe acoustic operational ceilings under all biomass conditions.");
        return true;
    }
}
