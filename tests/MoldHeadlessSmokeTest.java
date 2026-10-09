import java.util.concurrent.atomic.AtomicBoolean;

/**
 * MoldHeadlessSmokeTest.java
 *
 * Full headless integration smoke & regression test:
 * 1. Simulates 300 continuous real-time frames with bioenergetics, trail diffusion,
 *    food nodule updates, audio parameter modulation, and dynamic user interactions.
 * 2. Verifies thread-safety and concurrency during asynchronous reinoculation.
 */
public class MoldHeadlessSmokeTest {

    public static void main(String[] args) throws Exception {
        System.out.println("================================================================================");
        System.out.println("MOLD HEADLESS INTEGRATION & SMOKE REGRESSION SUITE");
        System.out.println("================================================================================");

        boolean allPassed = true;

        allPassed &= testContinuous300FrameRun();
        allPassed &= testAsynchronousReinoculateConcurrency();

        System.out.println("================================================================================");
        if (allPassed) {
            System.out.println(">> ALL HEADLESS INTEGRATION & SMOKE TESTS PASSED! <<");
            System.exit(0);
        } else {
            System.err.println(">> ONE OR MORE HEADLESS SMOKE CHECKS FAILED! <<");
            System.exit(1);
        }
        System.out.println("================================================================================");
    }

    private static boolean testContinuous300FrameRun() {
        System.out.println("\n[Smoke Test 1] Running 300-Frame Continuous Simulation & Parameter Update Loop...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.scatterInitialFood(6);
        s.midiEnabled = true;

        MoldTestUtils.MockMidiReceiver mockLp = new MoldTestUtils.MockMidiReceiver();
        s.midiHandler.lpReceiver = mockLp;

        long startTime = System.currentTimeMillis();

        for (int frame = 0; frame < 300; frame++) {
            // Emulate draw() simulation loop
            if (!s.isPaused) {
                s.speedAccumulator += s.simSpeed * 0.4f;
                while (s.speedAccumulator >= 1.0f) {
                    s.stepBioenergetics();
                    s.diffuseAndEvaporate();
                    s.speedAccumulator -= 1.0f;
                }
                s.updateGridBiomassAndFood();
                s.updateReverbBioTelemetry();
            }

            // Update food nodule audio parameters
            for (MoldSketch.FoodNodule fn : s.foodNodes) {
                int cellIdx = fn.gridRow * s.GRID_DIM + fn.gridCol;
                float adjacentMass = s.cellBiomass[cellIdx];
                fn.updateAudioParameters(adjacentMass);
            }

            s.lastMidiLedUpdate = 0; // ensure LED pipeline executes
            s.flushLaunchpadLeds();

            // Inject runtime events
            if (frame == 50) {
                s.addFoodNodule(200f, 200f, 16f, 150f);
            } else if (frame == 100) {
                s.simSpeed = 2.5f;
            } else if (frame == 150) {
                s.reinoculate();
            } else if (frame == 200) {
                s.scatterInitialFood(4);
            } else if (frame == 250) {
                s.clearAllFood();
            }
        }

        long elapsedMs = System.currentTimeMillis() - startTime;

        // Verify end state integrity
        MoldTestUtils.assertTrue(s.activeAgentCount > 0 && s.activeAgentCount <= s.MAX_AGENTS, "Active agents must be valid");

        // Verify trailMap has zero NaNs
        for (int i = 0; i < s.trailMap.length; i++) {
            float val = s.trailMap[i];
            if (Float.isNaN(val) || Float.isInfinite(val)) {
                throw new AssertionError("trailMap corrupted with NaN/Inf at index " + i);
            }
        }

        // Verify cellBiomass
        for (int i = 0; i < s.cellBiomass.length; i++) {
            float b = s.cellBiomass[i];
            if (Float.isNaN(b) || b < 0.0f) {
                throw new AssertionError("cellBiomass corrupted at cell " + i + ": " + b);
            }
        }

        // Verify Reverb parameters
        MoldTestUtils.assertInRange(s.reverbWet, 0.0f, 1.0f, "reverbWet");
        MoldTestUtils.assertInRange(s.reverbDry, 0.05f, 1.0f, "reverbDry");
        MoldTestUtils.assertInRange(s.reverbT60, 0.5f, 4.0f, "reverbT60");

        System.out.println("  PASS: 300 simulated frames completed in " + elapsedMs + " ms with zero errors, zero NaNs, and consistent state.");
        return true;
    }

    private static boolean testAsynchronousReinoculateConcurrency() throws Exception {
        System.out.println("\n[Smoke Test 2] Verifying Concurrency During Asynchronous Reinoculate()...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.scatterInitialFood(8);

        AtomicBoolean threadRunning = new AtomicBoolean(true);
        AtomicBoolean errorDetected = new AtomicBoolean(false);

        // Background worker simulating asynchronous MIDI / thread events
        Thread worker = new Thread(() -> {
            try {
                for (int i = 0; i < 20; i++) {
                    Thread.sleep(5);
                    s.reinoculate();
                    s.clearAllFood();
                    s.scatterInitialFood(4);
                }
            } catch (Throwable t) {
                t.printStackTrace();
                errorDetected.set(true);
            } finally {
                threadRunning.set(false);
            }
        });

        worker.start();

        // Main simulation thread running concurrently
        int simSteps = 0;
        while (threadRunning.get() && simSteps < 200) {
            s.stepBioenergetics();
            s.diffuseAndEvaporate();
            s.updateGridBiomassAndFood();
            simSteps++;
            Thread.sleep(1);
        }

        worker.join(3000);

        MoldTestUtils.assertTrue(!errorDetected.get(), "Exception detected during concurrent reinoculation");
        MoldTestUtils.assertTrue(s.pendingReinoculateFboClear, "pendingReinoculateFboClear should be set after reinoculate");

        System.out.println("  PASS: Concurrent reinoculation executed safely without ConcurrentModificationException or memory corruption.");
        return true;
    }
}
