import java.lang.reflect.Field;

public class MoldReverbModTest {
    public static void main(String[] args) throws Exception {
        System.out.println("Running MoldReverbModTest...");
        MoldSketch sketch = new MoldSketch();

        // 1. Check startup defaults
        if (Math.abs(sketch.filterSens - 3.0f) > 1e-4) {
            throw new AssertionError("filterSens default expected 3.0f, got " + sketch.filterSens);
        }
        System.out.println("PASS: filterSens default = " + sketch.filterSens + " (maximum)");

        if (Math.abs(sketch.filterQ - 18.0f) > 1e-4) {
            throw new AssertionError("filterQ default expected 18.0f, got " + sketch.filterQ);
        }
        System.out.println("PASS: filterQ default = " + sketch.filterQ + " (maximum)");

        if (Math.abs(sketch.reverbBioModDepth - 2.0f) > 1e-4) {
            throw new AssertionError("reverbBioModDepth default expected 2.0f, got " + sketch.reverbBioModDepth);
        }
        System.out.println("PASS: reverbBioModDepth default = " + sketch.reverbBioModDepth + " (2x pronounced)");

        // Verify settings() sets fullScreen flag properly
        try {
            java.lang.reflect.Field inSettings = processing.core.PApplet.class.getDeclaredField("insideSettings");
            inSettings.setAccessible(true);
            inSettings.setBoolean(sketch, true);
            sketch.settings();
            inSettings.setBoolean(sketch, false);
            if (!sketch.sketchFullScreen()) {
                throw new AssertionError("sketchFullScreen expected true after settings()");
            }
            System.out.println("PASS: sketchFullScreen is true after settings()");
        } catch (Exception e) {
            throw new RuntimeException(e);
        }

        // 2. Build UI controls and verify slider initial states
        sketch.midiHandler = sketch.new MidiHandler();
        sketch.buildUI();
        if (sketch.filterSensSlider == null || Math.abs(sketch.filterSensSlider.value - 3.0f) > 1e-4) {
            throw new AssertionError("filterSensSlider expected 3.0f");
        }
        System.out.println("PASS: filterSensSlider initialized to maximum (3.0x)");

        if (sketch.filterQSlider == null || Math.abs(sketch.filterQSlider.value - 18.0f) > 1e-4) {
            throw new AssertionError("filterQSlider expected 18.0f");
        }
        System.out.println("PASS: filterQSlider initialized to maximum (18.0)");

        if (sketch.reverbBioModSlider == null || Math.abs(sketch.reverbBioModSlider.value - 2.0f) > 1e-4) {
            throw new AssertionError("reverbBioModSlider expected 2.0f");
        }
        System.out.println("PASS: reverbBioModSlider initialized to 2.0x");

        // 3. Test telemetry modulation at depth 0.0x vs 1.0x vs 2.0x
        // Setup a test biomass state
        for (int i = 0; i < 64; i++) {
            sketch.cellBiomass[i] = 20000.0f; // total = 1,280,000 (colony blooming)
        }
        
        // Depth 0: should match base exactly
        sketch.reverbBioModDepth = 0.0f;
        sketch.updateReverbBioTelemetry();
        if (Math.abs(sketch.reverbWet - sketch.baseReverbWet) > 1e-4) {
            throw new AssertionError("At depth 0.0, reverbWet should equal baseReverbWet");
        }
        System.out.println("PASS: At depth 0.0x, reverb matches baseReverbWet exactly (" + sketch.reverbWet + ")");

        // Depth 1.0x
        sketch.reverbWet = sketch.baseReverbWet;
        sketch.reverbDry = sketch.baseReverbDry;
        sketch.reverbBioModDepth = 1.0f;
        // Run several steps to settle the filter
        for (int step = 0; step < 50; step++) {
            sketch.updateReverbBioTelemetry();
        }
        float wetDeltaAt1 = sketch.reverbWet - sketch.baseReverbWet;
        System.out.println("INFO: Wet delta at 1.0x depth = " + wetDeltaAt1);

        // Depth 2.0x
        sketch.reverbWet = sketch.baseReverbWet;
        sketch.reverbDry = sketch.baseReverbDry;
        sketch.reverbBioModDepth = 2.0f;
        for (int step = 0; step < 50; step++) {
            sketch.updateReverbBioTelemetry();
        }
        float wetDeltaAt2 = sketch.reverbWet - sketch.baseReverbWet;
        System.out.println("INFO: Wet delta at 2.0x depth = " + wetDeltaAt2);

        if (wetDeltaAt2 < wetDeltaAt1 * 1.8f) {
            throw new AssertionError("2.0x depth expected to be ~2x of 1.0x depth, got " + wetDeltaAt2 + " vs " + wetDeltaAt1);
        }
        System.out.println("PASS: Modulation at 2.0x depth is twice as pronounced as 1.0x baseline!");

        // 4. Test Launchpad side button routing (Top button = Re-inoculate, 2nd button = Clear Food)
        sketch.midiEnabled = true;
        // Allocate simulation buffers needed if reinoculate runs
        sketch.trailMap = new float[sketch.SIM_W * sketch.SIM_H];
        sketch.agentX = new float[sketch.MAX_AGENTS];
        sketch.agentY = new float[sketch.MAX_AGENTS];
        sketch.agentHeading = new float[sketch.MAX_AGENTS];
        sketch.agentEnergy = new float[sketch.MAX_AGENTS];

        // Initialize harmonics and seed some food nodes
        sketch.rebuildHarmonicCache();
        sketch.addFoodNodule(100f, 100f, 10f, 100f);
        sketch.addFoodNodule(200f, 200f, 10f, 100f);
        if (sketch.foodNodes.size() != 2) {
            throw new AssertionError("Expected 2 food nodes before clear test");
        }

        // Test second side button: CC 79 -> Clear All Food
        javax.sound.midi.ShortMessage msgPress79 = new javax.sound.midi.ShortMessage();
        msgPress79.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 79, 127);
        sketch.midiHandler.new LaunchpadReceiver().send(msgPress79, -1);
        if (!sketch.lpSecSidePressed) {
            throw new AssertionError("lpSecSidePressed should be true on press");
        }
        if (!sketch.foodNodes.isEmpty()) {
            throw new AssertionError("CC 79 failed to clear food nodes!");
        }
        System.out.println("PASS: Launchpad 2nd side button (CC 79) clears all food nodules");

        javax.sound.midi.ShortMessage msgRelease79 = new javax.sound.midi.ShortMessage();
        msgRelease79.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 79, 0);
        sketch.midiHandler.new LaunchpadReceiver().send(msgRelease79, -1);
        if (sketch.lpSecSidePressed) {
            throw new AssertionError("lpSecSidePressed should be false on release");
        }
        System.out.println("PASS: Launchpad 2nd side button (CC 79) release state tracked correctly");

        // Test top side button: CC 89 -> Re-inoculate
        sketch.cellBiomass[10] = 555.0f;
        javax.sound.midi.ShortMessage msgPress89 = new javax.sound.midi.ShortMessage();
        msgPress89.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 89, 127);
        sketch.midiHandler.new LaunchpadReceiver().send(msgPress89, -1);
        if (!sketch.lpTopSidePressed) {
            throw new AssertionError("lpTopSidePressed should be true on press");
        }
        if (sketch.cellBiomass[10] != 0.0f) {
            throw new AssertionError("CC 89 failed to reinoculate (cellBiomass[10] was not reset)!");
        }
        System.out.println("PASS: Launchpad top side button (CC 89) triggers reinoculate()");

        javax.sound.midi.ShortMessage msgRelease89 = new javax.sound.midi.ShortMessage();
        msgRelease89.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 89, 0);
        sketch.midiHandler.new LaunchpadReceiver().send(msgRelease89, -1);
        if (sketch.lpTopSidePressed) {
            throw new AssertionError("lpTopSidePressed should be false on release");
        }
        System.out.println("PASS: Launchpad top side button (CC 89) release state tracked correctly");

        // Test bottom 3 side buttons: CC 39 (Mold LED), CC 29 (Food LED), CC 19 (Eating LED)
        // CC 39: Slime Mold LED toggle
        boolean initSlime = sketch.lpShowSlime;
        javax.sound.midi.ShortMessage msgPress39 = new javax.sound.midi.ShortMessage();
        msgPress39.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 39, 127);
        sketch.midiHandler.new LaunchpadReceiver().send(msgPress39, -1);
        if (sketch.lpShowSlime == initSlime) {
            throw new AssertionError("CC 39 failed to toggle lpShowSlime!");
        }
        System.out.println("PASS: Launchpad side button CC 39 toggles lpShowSlime");

        // CC 29: Food LED toggle
        boolean initFood = sketch.lpShowFood;
        javax.sound.midi.ShortMessage msgPress29 = new javax.sound.midi.ShortMessage();
        msgPress29.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 29, 127);
        sketch.midiHandler.new LaunchpadReceiver().send(msgPress29, -1);
        if (sketch.lpShowFood == initFood) {
            throw new AssertionError("CC 29 failed to toggle lpShowFood!");
        }
        System.out.println("PASS: Launchpad side button CC 29 toggles lpShowFood");

        // CC 19: Eating LED toggle
        boolean initEat = sketch.lpShowEating;
        javax.sound.midi.ShortMessage msgPress19 = new javax.sound.midi.ShortMessage();
        msgPress19.setMessage(javax.sound.midi.ShortMessage.CONTROL_CHANGE, 0, 19, 127);
        sketch.midiHandler.new LaunchpadReceiver().send(msgPress19, -1);
        if (sketch.lpShowEating == initEat) {
            throw new AssertionError("CC 19 failed to toggle lpShowEating!");
        }
        System.out.println("PASS: Launchpad side button CC 19 toggles lpShowEating");

        System.out.println("================================================================================");
        System.out.println(">> ALL REVERB BIO-MODULATION & MIDI ROUTING TESTS PASSED! <<");
        System.out.println("================================================================================");
    }
}
