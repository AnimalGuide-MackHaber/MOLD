/**
 * MoldBellAcousticsTest.java
 *
 * Automated verification of Bell Acoustics, Carillon Modal Frequencies,
 * Frequency-Dependent Decay Rates (tau_i = Q_i / (pi * f_i)), Sustain Phase,
 * and Monotonic Dissipation Invariants.
 */
public class MoldBellAcousticsTest {

    public static void main(String[] args) throws Exception {
        System.out.println("================================================================================");
        System.out.println("MOLD BELL ACOUSTICS & HARMONIC DECAY TEST SUITE");
        System.out.println("================================================================================");

        boolean allPassed = true;

        allPassed &= testCarillonModalFrequencyRatios();
        allPassed &= testQualityFactorDecayTimeConstants();
        allPassed &= testStrikeTransientExcitation();
        allPassed &= testSustainPhaseBioExcitation();
        allPassed &= testDecayPhaseHarmonicDissipation();
        allPassed &= testDepletedFoodAcousticPreservationAndPruning();

        System.out.println("================================================================================");
        if (allPassed) {
            System.out.println(">> ALL BELL ACOUSTICS & HARMONIC DECAY INVARIANTS PASSED! <<");
            System.out.println("================================================================================");
            System.exit(0);
        } else {
            System.err.println(">> ONE OR MORE BELL ACOUSTICS CHECKS FAILED! <<");
            System.exit(1);
        }
    }

    private static boolean testCarillonModalFrequencyRatios() {
        System.out.println("\n[Bell Test 1] Verifying Carillon Modal Frequency Ratios & Simpson Tuning...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);
        fn.frequency = 220.0f; // A3 Fundamental (Prime)

        // Simpson Carillon Tuning Ratios:
        // 0: Hum (sub-octave, 0.5x = 110Hz)
        // 1: Prime (fundamental, 1.0x = 220Hz)
        // 2: Tierce (minor 3rd, ~1.1892x = ~261.62Hz)
        // 3: Quint (perfect 5th, ~1.4983x = ~329.63Hz)
        // 4: Nominal (octave, 2.0x = 440Hz)
        // 5: Decime (strike inharmonic, 2.74x = 602.8Hz)

        float[] expectedRatios = {0.50f, 1.00f, 1.1892f, 1.4983f, 2.00f, 2.74f};
        for (int p = 0; p < s.BELL_NUM_PARTIALS; p++) {
            float ratio = s.BELL_RATIOS[p];
            MoldTestUtils.assertEquals(expectedRatios[p], ratio, 1e-4f, "Mode " + p + " ratio mismatch");
            float modalFreq = fn.frequency * ratio;
            MoldTestUtils.assertTrue(modalFreq >= 20.0f && modalFreq <= 20000.0f, "Modal freq out of audible range: " + modalFreq);
        }

        System.out.println("  PASS: All 6 Simpson carillon bell partials match physical tuning ratios (Hum: 0.5x, Prime: 1.0x, Tierce: ~1.19x, Quint: ~1.50x, Nominal: 2.0x, Decime: 2.74x).");
        return true;
    }

    private static boolean testQualityFactorDecayTimeConstants() {
        System.out.println("\n[Bell Test 2] Verifying Quality Factor Frequency-Dependent Decay Rates (tau_i = Q_i / (pi * f_i))...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        float f0 = 220.0f;
        float bellQ = s.bellQ; // 1800.0

        float[] taus = new float[s.BELL_NUM_PARTIALS];
        for (int p = 0; p < s.BELL_NUM_PARTIALS; p++) {
            float f_p = f0 * s.BELL_RATIOS[p];
            float tau = (bellQ * s.BELL_Q_MULTS[p]) / ((float) Math.PI * f_p);
            taus[p] = tau;
        }

        // Invariant: Higher frequencies MUST decay strictly faster than lower frequencies
        // tau_Hum > tau_Prime > tau_Tierce > tau_Quint > tau_Nominal > tau_Decime
        for (int p = 0; p < s.BELL_NUM_PARTIALS - 1; p++) {
            MoldTestUtils.assertTrue(taus[p] > taus[p + 1],
                "Decay constant ordering violated: tau[" + p + "]=" + taus[p] + " <= tau[" + (p+1) + "]=" + taus[p+1]);
        }

        // Hum must have long resonance (tau > 4.0s)
        MoldTestUtils.assertTrue(taus[0] > 4.0f, "Hum decay constant should exceed 4.0s for bronze resonance");
        // Strike mode (Decime) must decay very quickly (tau < 0.6s)
        MoldTestUtils.assertTrue(taus[5] < 0.6f, "Strike inharmonic mode decay constant should be < 0.6s");

        System.out.println("  PASS: tau ordering strictly verified: tau_Hum (" + String.format("%.2f", taus[0]) + "s) > " +
            "tau_Prime (" + String.format("%.2f", taus[1]) + "s) > " +
            "tau_Tierce (" + String.format("%.2f", taus[2]) + "s) > " +
            "tau_Quint (" + String.format("%.2f", taus[3]) + "s) > " +
            "tau_Nominal (" + String.format("%.2f", taus[4]) + "s) > " +
            "tau_Decime (" + String.format("%.2f", taus[5]) + "s).");
        return true;
    }

    private static boolean testStrikeTransientExcitation() {
        System.out.println("\n[Bell Test 3] Verifying Strike Phase Transient Excitation...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);

        // Strike nodule at velocity = 1.0
        fn.strike(1.0f);

        // High modes (Nominal=1.0, Strike=0.9) must start louder than Hum (0.45)
        MoldTestUtils.assertEquals(0.45f, fn.bellAmps[0], 1e-4f, "Hum strike amplitude");
        MoldTestUtils.assertEquals(1.00f, fn.bellAmps[4], 1e-4f, "Nominal strike amplitude");
        MoldTestUtils.assertEquals(0.90f, fn.bellAmps[5], 1e-4f, "Decime strike amplitude");
        MoldTestUtils.assertTrue(fn.bellAmps[4] > fn.bellAmps[0], "Nominal must exceed Hum at impact");

        // Velocity scaling
        for (int p = 0; p < s.BELL_NUM_PARTIALS; p++) fn.bellAmps[p] = 0.0f;
        fn.strike(0.5f);
        MoldTestUtils.assertEquals(0.50f, fn.bellAmps[4], 1e-4f, "Nominal scaled by velocity 0.5");

        System.out.println("  PASS: Strike phase initiates with high-frequency dominance (Nominal: "
            + fn.bellAmps[4] * 2.0f + ", Decime: " + fn.bellAmps[5] * 2.0f + " > Hum: " + fn.bellAmps[0] * 2.0f + ").");
        return true;
    }

    private static boolean testSustainPhaseBioExcitation() {
        System.out.println("\n[Bell Test 4] Verifying Sustain Phase Bio-Excitation While Food is Being Eaten...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);

        // Simulate active eating with strong adjacent biomass
        fn.isBeingEaten = true;
        fn.vcaGain = 0.8f;
        fn.nutrients = 100.0f;

        // Render 100 audio blocks (~1.16s) to allow sustain to reach steady-state
        float[] dryL = new float[512], dryR = new float[512];
        float[] verbL = new float[512], verbR = new float[512];
        float[] sineTable = new float[4096];
        for (int i = 0; i < 4096; i++) sineTable[i] = (float) Math.sin((i / 4096.0) * Math.PI * 2.0);

        MoldSketch.AudioEngine engine = s.new AudioEngine();

        for (int b = 0; b < 100; b++) {
            engine.renderVoiceToBuffer(fn, dryL, dryR, verbL, verbR, 0.24f, 0, sineTable);
        }

        // In sustain, all modes must remain non-zero and stable
        for (int p = 0; p < s.BELL_NUM_PARTIALS; p++) {
            MoldTestUtils.assertTrue(fn.bellAmps[p] > 0.0f, "Mode " + p + " must sustain during active feeding");
            MoldTestUtils.assertTrue(!Float.isNaN(fn.bellAmps[p]) && !Float.isInfinite(fn.bellAmps[p]), "Mode " + p + " NaN/Inf in sustain");
        }

        // Prime (Mode 1) and Tierce (Mode 2) must be prominent singing partials in sustain
        MoldTestUtils.assertTrue(fn.bellAmps[1] > fn.bellAmps[5] * 5.0f,
            "Fundamental Prime (" + fn.bellAmps[1] + ") must heavily dominate strike mode (" + fn.bellAmps[5] + ") during sustain");
        MoldTestUtils.assertTrue(fn.bellAmps[2] > fn.bellAmps[5] * 4.0f,
            "Minor-third Tierce (" + fn.bellAmps[2] + ") must heavily dominate strike mode during sustain");

        System.out.println("  PASS: Sustain phase maintains warm singing body (Prime=" + String.format("%.3f", fn.bellAmps[1])
            + ", Tierce=" + String.format("%.3f", fn.bellAmps[2]) + ", Hum=" + String.format("%.3f", fn.bellAmps[0])
            + ") while metallic strike decays to " + String.format("%.3f", fn.bellAmps[5]) + ".");
        return true;
    }

    private static boolean testDecayPhaseHarmonicDissipation() {
        System.out.println("\n[Bell Test 5] Verifying Exponential Harmonic Decay & Last-Surviving Hum Invariant...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);
        fn.frequency = 220.0f; // Calibrated A3 fundamental (Hum = 110Hz, tau = 5.21s)

        // Strike nodule at velocity = 1.0, but leave not being eaten (free decay)
        fn.strike(1.0f);
        fn.isBeingEaten = false;
        fn.vcaGain = 0.0f;

        float[] dryL = new float[512], dryR = new float[512];
        float[] verbL = new float[512], verbR = new float[512];
        float[] sineTable = new float[4096];
        for (int i = 0; i < 4096; i++) sineTable[i] = (float) Math.sin((i / 4096.0) * Math.PI * 2.0);

        MoldSketch.AudioEngine engine = s.new AudioEngine();

        // 1. After 0.6 seconds (~52 blocks):
        for (int b = 0; b < 52; b++) {
            engine.renderVoiceToBuffer(fn, dryL, dryR, verbL, verbR, 0.24f, 0, sineTable);
        }

        // Decime (Mode 5) must have decayed down significantly
        float decimeAfter06s = fn.bellAmps[5];
        MoldTestUtils.assertTrue(decimeAfter06s < 0.20f, "Decime strike mode must decay rapidly in first 0.6s (got " + decimeAfter06s + ")");
        MoldTestUtils.assertTrue(fn.bellAmps[0] > decimeAfter06s * 2.0f, "Hum must remain significantly stronger than Decime at 0.6s");

        // 2. After 2.5 seconds total (~215 blocks):
        for (int b = 52; b < 215; b++) {
            engine.renderVoiceToBuffer(fn, dryL, dryR, verbL, verbR, 0.24f, 0, sineTable);
        }
        float decimeAfter25s = fn.bellAmps[5];
        float nominalAfter25s = fn.bellAmps[4];
        float humAfter25s = fn.bellAmps[0];

        MoldTestUtils.assertTrue(decimeAfter25s < 0.005f, "Decime should be practically extinguished by 2.5s");
        MoldTestUtils.assertTrue(humAfter25s > nominalAfter25s * 2.0f,
            "Hum (" + humAfter25s + ") must dominate decaying Nominal (" + nominalAfter25s + ") at 2.5s");
        MoldTestUtils.assertTrue(humAfter25s > 0.15f, "Hum must still have substantial resonance at 2.5s");

        System.out.println("  PASS: Natural decay timeline verified: Decime dies first (" + String.format("%.4f", decimeAfter25s)
            + "), Nominal dies next (" + String.format("%.4f", nominalAfter25s) + "), Hum lingers longest (" + String.format("%.4f", humAfter25s) + ").");
        return true;
    }

    private static boolean testDepletedFoodAcousticPreservationAndPruning() {
        System.out.println("\n[Bell Test 6] Verifying Depleted Food Acoustic Ringing & Eventual Clean Removal...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.foodNodes.clear();
        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);
        fn.frequency = 220.0f;
        s.bellQ = 80.0f; // Fast decay for unit test verification

        // Deplete food to 0, but give it active bell energy
        fn.strike(1.0f);
        fn.nutrients = 0.0f;

        // Run updateFoodNodulesAndVoices
        s.updateFoodNodulesAndVoices();

        // While ringing, nodule should NOT be removed from foodNodes
        MoldTestUtils.assertEquals(1, s.foodNodes.size(), 0, "Depleted nodule should not be abruptly dropped while bell rings");
        MoldTestUtils.assertTrue(fn.isDepleted, "fn.isDepleted must be true");

        // Simulate audio decay until silent (400 blocks ~ 4.6 seconds)
        float[] dryL = new float[512], dryR = new float[512];
        float[] verbL = new float[512], verbR = new float[512];
        float[] sineTable = new float[4096];
        for (int i = 0; i < 4096; i++) sineTable[i] = (float) Math.sin((i / 4096.0) * Math.PI * 2.0);
        MoldSketch.AudioEngine engine = s.new AudioEngine();

        for (int b = 0; b < 600; b++) {
            engine.renderVoiceToBuffer(fn, dryL, dryR, verbL, verbR, 0.24f, 0, sineTable);
            s.updateFoodNodulesAndVoices();
            if (s.foodNodes.isEmpty()) break;
        }

        // Once decay tail completes, nodule must be cleanly removed
        MoldTestUtils.assertEquals(0, s.foodNodes.size(), 0, "Depleted nodule must be cleanly removed once bell tail finishes");

        System.out.println("  PASS: Depleted nodule rings out full acoustic decay tail before clean garbage collection.");
        return true;
    }
}
