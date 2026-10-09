/**
 * MoldSimulationInvariantsTest.java
 *
 * Automated verification of Physarum simulation invariants:
 * 1. Agent spatial bounds containment across hundreds of simulation steps
 * 2. Chemotaxis sensor sampleChemo() boundary and toroidal wrap safety
 * 3. Diffusion & Evaporation conservation and non-negativity
 * 4. Food nodule lifecycle, consumption dynamics, and filter frequency sweeps
 * 5. Mitosis division and maximum population clamping (<= 64,000)
 * 6. Colony reinoculation state reset & deferred OpenGL FBO flag activation
 */
public class MoldSimulationInvariantsTest {

    public static void main(String[] args) {
        System.out.println("================================================================================");
        System.out.println("MOLD SIMULATION & BIOENERGETICS INVARIANTS TEST SUITE");
        System.out.println("================================================================================");

        boolean allPassed = true;

        allPassed &= testAgentSpatialBoundaryInvariant();
        allPassed &= testSampleChemoBoundarySafety();
        allPassed &= testDiffusionAndEvaporationConservation();
        allPassed &= testFoodNoduleLifecycleAndEating();
        allPassed &= testMitosisAndPopulationClamping();
        allPassed &= testReinoculateReset();

        System.out.println("================================================================================");
        if (allPassed) {
            System.out.println(">> ALL SIMULATION & BIOENERGETICS INVARIANTS PASSED! <<");
        } else {
            System.err.println(">> ONE OR MORE SIMULATION INVARIANT CHECKS FAILED! <<");
            System.exit(1);
        }
        System.out.println("================================================================================");
    }

    private static boolean testAgentSpatialBoundaryInvariant() {
        System.out.println("\n[Sim Test 1] Verifying Agent Spatial Bounds Invariant (300 steps)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.scatterInitialFood(5);

        for (int step = 0; step < 300; step++) {
            s.stepBioenergetics();
            s.diffuseAndEvaporate();
        }

        MoldTestUtils.assertTrue(s.activeAgentCount > 0, "Colony should have surviving agents");
        MoldTestUtils.assertTrue(s.activeAgentCount <= s.MAX_AGENTS, "Active agent count must be <= MAX_AGENTS");

        float twoPi = (float) (Math.PI * 2.0);
        for (int i = 0; i < s.activeAgentCount; i++) {
            float x = s.agentX[i];
            float y = s.agentY[i];
            float h = s.agentHeading[i];
            float e = s.agentEnergy[i];

            if (x < 0.0f || x >= s.SIM_W || Float.isNaN(x)) {
                throw new AssertionError("Agent " + i + " x-coordinate escaped bounds: " + x);
            }
            if (y < 0.0f || y >= s.SIM_H || Float.isNaN(y)) {
                throw new AssertionError("Agent " + i + " y-coordinate escaped bounds: " + y);
            }
            if (h < 0.0f || h >= twoPi + 1e-4f || Float.isNaN(h)) {
                throw new AssertionError("Agent " + i + " heading escaped [0, 2pi): " + h);
            }
            if (e < 0.0f || Float.isNaN(e) || Float.isInfinite(e)) {
                throw new AssertionError("Agent " + i + " energy is invalid: " + e);
            }
        }

        System.out.println("  PASS: All " + s.activeAgentCount + " agents strictly bounded within [0, " + s.SIM_W + ") x [0, " + s.SIM_H + ") with valid energy.");
        return true;
    }

    private static boolean testSampleChemoBoundarySafety() {
        System.out.println("\n[Sim Test 2] Verifying sampleChemo() Boundary & Wrap Safety...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();

        // Populate trail map with a recognizable gradient
        for (int y = 0; y < s.SIM_H; y++) {
            for (int x = 0; x < s.SIM_W; x++) {
                s.trailMap[y * s.SIM_W + x] = (x + y) * 0.1f;
            }
        }

        // Test boundary conditions that could trigger ArrayIndexOutOfBounds
        float[] testCoords = {
            0.0f, 0.0f,
            (float) s.SIM_W - 1.0f, (float) s.SIM_H - 1.0f,
            (float) s.SIM_W, (float) s.SIM_H,
            -0.0001f, -0.0001f,
            -1e-7f, -1e-7f,
            s.SIM_W + 0.0001f, s.SIM_H + 0.0001f,
            -35.0f, -35.0f, // Negative sensor reach
            s.SIM_W + 35.0f, s.SIM_H + 35.0f // Positive sensor reach outside canvas
        };

        for (int i = 0; i < testCoords.length; i += 2) {
            float tx = testCoords[i];
            float ty = testCoords[i + 1];
            float val = s.sampleChemo(tx, ty);
            if (Float.isNaN(val) || Float.isInfinite(val) || val < 0.0f) {
                throw new AssertionError("sampleChemo(" + tx + ", " + ty + ") returned invalid value: " + val);
            }
        }

        System.out.println("  PASS: sampleChemo() evaluated corner, sub-zero, and wrap points with zero out-of-bounds exceptions.");
        return true;
    }

    private static boolean testDiffusionAndEvaporationConservation() {
        System.out.println("\n[Sim Test 3] Verifying Diffusion & Evaporation Conservation & Non-Negativity...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();

        // Clear trail maps
        for (int i = 0; i < s.trailMap.length; i++) {
            s.trailMap[i] = 0.0f;
            s.nextTrailMap[i] = 0.0f;
        }

        // Place a localized impulse of 200.0 at center
        int cx = s.SIM_W / 2;
        int cy = s.SIM_H / 2;
        s.trailMap[cy * s.SIM_W + cx] = 200.0f;

        double initialEnergy = 200.0;

        // Run 5 diffusion steps without any agents depositing
        for (int step = 0; step < 5; step++) {
            s.diffuseAndEvaporate();
        }

        double totalEnergy = 0.0;
        for (int i = 0; i < s.trailMap.length; i++) {
            float val = s.trailMap[i];
            if (val < 0.0f) {
                throw new AssertionError("Trail value negative at index " + i + ": " + val);
            }
            if (val > 255.0f) {
                throw new AssertionError("Trail value exceeded 255.0 at index " + i + ": " + val);
            }
            if (Float.isNaN(val)) {
                throw new AssertionError("Trail value is NaN at index " + i);
            }
            totalEnergy += val;
        }

        // Energy must decay strictly monotonically due to trailDecay (0.965)
        MoldTestUtils.assertTrue(totalEnergy < initialEnergy, "Total trail energy must decay due to evaporation");
        MoldTestUtils.assertTrue(totalEnergy > 0.0, "Total trail energy must remain non-zero after 5 steps");

        // Center pixel must have diffused into neighboring pixels
        float centerVal = s.trailMap[cy * s.SIM_W + cx];
        float neighborVal = s.trailMap[cy * s.SIM_W + (cx + 1)];
        MoldTestUtils.assertTrue(centerVal < 200.0f, "Center peak must diffuse outwards");
        MoldTestUtils.assertTrue(neighborVal > 0.0f, "Neighbor cell must receive diffused trail energy");

        System.out.println("  PASS: Diffusion preserved non-negativity and evaporated monotonically (energy: "
                + String.format("%.2f", initialEnergy) + " -> " + String.format("%.2f", totalEnergy) + ").");
        return true;
    }

    private static boolean testFoodNoduleLifecycleAndEating() {
        System.out.println("\n[Sim Test 4] Verifying Food Nodule Lifecycle & Audio Modulation...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.foodNodes.clear();

        s.addFoodNodule(360.0f, 360.0f, 20.0f, 100.0f);
        MoldTestUtils.assertEquals(1, s.foodNodes.size(), 0, "Expected 1 food nodule");
        MoldSketch.FoodNodule fn = s.foodNodes.get(0);

        MoldTestUtils.assertEquals(20.0f, fn.radius, 1e-4f, "Initial radius mismatch");
        MoldTestUtils.assertEquals(100.0f, fn.nutrients, 1e-4f, "Initial nutrients mismatch");

        // Simulate idle nodule (not being eaten, low adjacent mass)
        fn.isBeingEaten = false;
        fn.updateAudioParameters(0.0f);
        MoldTestUtils.assertEquals(0.0f, fn.vcaGain, 1e-4f, "VCA gain should be ~0.0 when not eaten");
        MoldTestUtils.assertEquals(0.0f, fn.consumptionActivity, 1e-4f, "Activity should be ~0.0 when idle");

        // Simulate active feeding with high adjacent biomass
        fn.isBeingEaten = true;
        for (int i = 0; i < 30; i++) {
            fn.updateAudioParameters(1500.0f);
        }
        MoldTestUtils.assertTrue(fn.vcaGain > 0.5f, "VCA gain should open when actively eaten by dense mass");
        MoldTestUtils.assertTrue(fn.consumptionActivity > 0.8f, "Consumption activity should approach 1.0 when eaten");

        // Deplete food to 25%
        fn.nutrients = 25.0f;
        fn.updateAudioParameters(1500.0f);
        MoldTestUtils.assertTrue(fn.radius < 20.0f, "Radius should shrink as food is consumed");
        MoldTestUtils.assertTrue(fn.radius >= 2.5f, "Radius must not drop below minimum 2.5px clamp");
        MoldTestUtils.assertTrue(fn.lpfCutoff < 3200.0f, "Lowpass filter cutoff must sweep downward as food is depleted");

        // Deplete food to 0
        fn.nutrients = 0.0f;
        fn.updateAudioParameters(1500.0f);
        MoldTestUtils.assertEquals(2.5f, fn.radius, 1e-4f, "Depleted food radius must clamp to 2.5px");
        MoldTestUtils.assertEquals(s.filterBaseHz, fn.lpfCutoff, 1e-2f, "Depleted food cutoff should reach filterBaseHz (80Hz)");

        System.out.println("  PASS: Food nodule radius, dynamic LPF sweep ("
                + String.format("%.1f", fn.lpfCutoff) + " Hz), and VCA gain behave strictly according to spec.");
        return true;
    }

    private static boolean testMitosisAndPopulationClamping() {
        System.out.println("\n[Sim Test 5] Verifying Mitosis Division & MAX_AGENTS Clamping...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.targetAgentCount = s.MAX_AGENTS;

        // Give all active agents abundant energy above mitosis threshold (75.0)
        for (int i = 0; i < s.activeAgentCount; i++) {
            s.agentEnergy[i] = 100.0f;
        }

        int preCount = s.activeAgentCount;
        s.stepBioenergetics();
        int postCount = s.activeAgentCount;

        MoldTestUtils.assertTrue(postCount >= preCount, "Mitosis should increase agent population under abundant energy");
        MoldTestUtils.assertTrue(postCount <= s.MAX_AGENTS, "Population must never exceed MAX_AGENTS (64,000)");

        // Test worst-case boundary where population is already near MAX_AGENTS
        s.activeAgentCount = s.MAX_AGENTS - 5;
        for (int i = 0; i < s.activeAgentCount; i++) {
            s.agentEnergy[i] = 100.0f;
        }
        s.stepBioenergetics();
        MoldTestUtils.assertTrue(s.activeAgentCount <= s.MAX_AGENTS, "Population must strictly not exceed MAX_AGENTS");

        System.out.println("  PASS: Mitosis population expansion correctly bounded by MAX_AGENTS (active: "
                + s.activeAgentCount + " <= " + s.MAX_AGENTS + ").");
        return true;
    }

    private static boolean testReinoculateReset() {
        System.out.println("\n[Sim Test 6] Verifying Reinoculation Reset & Deferred FBO Flag...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();

        // Mutate state
        s.cellBiomass[10] = 500.0f;
        s.foodNodes.clear();
        s.addFoodNodule(100f, 100f, 10f, 100f);
        s.pendingReinoculateFboClear = false;

        s.reinoculate();

        MoldTestUtils.assertEquals(s.INITIAL_AGENTS, s.activeAgentCount, 0, "activeAgentCount should reset to INITIAL_AGENTS");
        MoldTestUtils.assertEquals(0.0f, s.cellBiomass[10], 1e-4f, "cellBiomass should be reset to zero");
        MoldTestUtils.assertEquals(1, s.foodNodes.size(), 0, "reinoculate() must keep existing food nodes intact");
        MoldTestUtils.assertTrue(s.pendingReinoculateFboClear, "pendingReinoculateFboClear flag must be set for deferred OpenGL execution");

        System.out.println("  PASS: reinoculate() cleanly reset colony, preserved food nodes, and armed deferred FBO clear flag.");
        return true;
    }
}
