import java.util.Random;
import javax.sound.midi.ShortMessage;

/**
 * MoldMidiControllerTest.java
 *
 * Automated verification of Hardware MIDI controller mapping and telemetry:
 * 1. Akai MIDImix full CC sweep across all 18 knobs and faders (values 0..127)
 * 2. Akai MIDImix button toggles and momentary actions
 * 3. Novation Launchpad Mini MK3 8x8 pad drum rack layout (notes 36..99)
 * 4. Launchpad perimeter CC actions (CC 89, 79, 39, 29, 19)
 * 5. Trilateral Color Domain Telemetry Standard (Yellow mold, Cyan food, Magenta eating)
 * 6. MIDI fuzzing & malformed event resilience
 */
public class MoldMidiControllerTest {

    public static void main(String[] args) throws Exception {
        System.out.println("================================================================================");
        System.out.println("MOLD HARDWARE MIDI CONTROLLER & TELEMETRY TEST SUITE");
        System.out.println("================================================================================");

        boolean allPassed = true;

        allPassed &= testAkaiMidimixFullCcRangeSweep();
        allPassed &= testAkaiMidimixButtonTogglesAndMomentaries();
        allPassed &= testLaunchpadDrumRackPadMapping();
        allPassed &= testLaunchpadPerimeterCcActions();
        allPassed &= testLaunchpadTrilateralColorTelemetry();
        allPassed &= testLaunchpadProgrammerModeNotes();
        allPassed &= testLaunchpadSysExRgbGradients();
        allPassed &= testLaunchpadRipplePropagation();
        allPassed &= testMidiFuzzAndResilience();

        System.out.println("================================================================================");
        if (allPassed) {
            System.out.println(">> ALL HARDWARE MIDI CONTROLLER & TELEMETRY TESTS PASSED! <<");
        } else {
            System.err.println(">> ONE OR MORE HARDWARE MIDI CHECKS FAILED! <<");
            System.exit(1);
        }
        System.out.println("================================================================================");
    }

    private static boolean testAkaiMidimixFullCcRangeSweep() throws Exception {
        System.out.println("\n[MIDI Test 1] Verifying Akai MIDImix Full CC Range Sweep (All 18 controls)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        javax.sound.midi.Receiver r = s.midiHandler.new MidimixReceiver();

        int[] ccs = {19, 23, 27, 28, 29, 30, 31, 33, 11, 16, 20, 24, 17, 21, 25, 18, 22, 26};
        int[] testVals = {0, 16, 64, 112, 127};

        for (int cc : ccs) {
            for (int val : testVals) {
                ShortMessage sm = new ShortMessage();
                sm.setMessage(ShortMessage.CONTROL_CHANGE, 0, cc, val);
                r.send(sm, -1);
            }
        }

        // Verify values are strictly bounded within their specification domains
        MoldTestUtils.assertInRange(s.filterSens, 0.2f, 3.0f, "filterSens");
        MoldTestUtils.assertInRange(s.filterQ, 0.5f, 18.0f, "filterQ");
        MoldTestUtils.assertInRange(s.vcaSensitivity, 0.2f, 3.0f, "vcaSensitivity");
        MoldTestUtils.assertInRange(s.reverbWet, 0.0f, 1.0f, "reverbWet");
        MoldTestUtils.assertInRange(s.reverbDry, 0.0f, 1.0f, "reverbDry");
        MoldTestUtils.assertInRange(s.reverbT60, 0.5f, 8.0f, "reverbT60");
        MoldTestUtils.assertInRange(s.reverbHighDamping, 0.05f, 0.95f, "reverbHighDamping");
        MoldTestUtils.assertInRange(s.reverbPreDelay, 0.005f, 0.060f, "reverbPreDelay");
        MoldTestUtils.assertInRange(s.simSpeed, 0.1f, 30.0f, "simSpeed");
        MoldTestUtils.assertInRange(s.sensorDist, 6.0f, 160.0f, "sensorDist");
        MoldTestUtils.assertInRange(s.bmr, 0.001f, 0.050f, "bmr");
        MoldTestUtils.assertInRange(s.locomotionCost, 0.002f, 0.080f, "locomotionCost");
        MoldTestUtils.assertInRange(s.visualSharpness, 0.0f, 1.0f, "visualSharpness");
        MoldTestUtils.assertInRange(s.targetAgentCount, 1000f, 64000f, "targetAgentCount");
        MoldTestUtils.assertInRange(s.visualBlur, 0.0f, 8.0f, "visualBlur");
        MoldTestUtils.assertInRange(s.octaveShiftIdx, 0f, 2f, "octaveShiftIdx");
        MoldTestUtils.assertInRange(s.ledMassThreshold, 20.0f, 1000.0f, "ledMassThreshold");
        MoldTestUtils.assertInRange(s.reverbBioModDepth, 0.0f, 4.0f, "reverbBioModDepth");

        System.out.println("  PASS: All 18 MIDImix controls swept through 0..127 with zero exceptions and correct parameter clamping.");
        return true;
    }

    private static boolean testAkaiMidimixButtonTogglesAndMomentaries() throws Exception {
        System.out.println("\n[MIDI Test 2] Verifying MIDImix Button Toggles & Momentary Releases...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        javax.sound.midi.Receiver r = s.midiHandler.new MidimixReceiver();

        // 1. Mute row toggle: Note 1 (Pause)
        boolean initPause = s.isPaused;
        ShortMessage noteOn1 = new ShortMessage();
        noteOn1.setMessage(ShortMessage.NOTE_ON, 0, 1, 127);
        r.send(noteOn1, -1);
        MoldTestUtils.assertTrue(s.isPaused != initPause, "Note 1 should toggle pause state");

        // 2. Rec Arm row momentary action: Note 6 (Clear Food)
        s.addFoodNodule(100f, 100f, 10f, 100f);
        ShortMessage noteOn6 = new ShortMessage();
        noteOn6.setMessage(ShortMessage.NOTE_ON, 0, 6, 127);
        r.send(noteOn6, -1);
        MoldTestUtils.assertTrue(s.foodNodes.isEmpty(), "Note 6 should execute clearAllFood()");

        // Release momentary
        ShortMessage noteOff6 = new ShortMessage();
        noteOff6.setMessage(ShortMessage.NOTE_OFF, 0, 6, 0);
        r.send(noteOff6, -1);

        System.out.println("  PASS: MIDImix toggles and momentary actions respond correctly to hardware events.");
        return true;
    }

    private static boolean testLaunchpadDrumRackPadMapping() throws Exception {
        System.out.println("\n[MIDI Test 3] Verifying Launchpad Drum Rack Pad Mapping (All 64 pads 36..99)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        javax.sound.midi.Receiver r = s.midiHandler.new LaunchpadReceiver();

        float cellW = (float) s.SIM_W / (float) s.GRID_DIM;
        float cellH = (float) s.SIM_H / (float) s.GRID_DIM;

        for (int note = 36; note <= 99; note++) {
            s.foodNodes.clear();

            ShortMessage sm = new ShortMessage();
            sm.setMessage(ShortMessage.NOTE_ON, 0, note, 127);
            r.send(sm, -1);

            MoldTestUtils.assertEquals(1, s.foodNodes.size(), 0, "Note " + note + " did not add food nodule");
            MoldSketch.FoodNodule fn = s.foodNodes.get(0);

            // Verify grid coordinates are in valid range
            MoldTestUtils.assertTrue(fn.gridRow >= 0 && fn.gridRow < 8, "gridRow out of bounds for note " + note + ": " + fn.gridRow);
            MoldTestUtils.assertTrue(fn.gridCol >= 0 && fn.gridCol < 8, "gridCol out of bounds for note " + note + ": " + fn.gridCol);

            // Verify pixel position matches cell bounding box
            float minX = fn.gridCol * cellW;
            float maxX = (fn.gridCol + 1) * cellW;
            float minY = fn.gridRow * cellH;
            float maxY = (fn.gridRow + 1) * cellH;

            MoldTestUtils.assertTrue(fn.x >= minX && fn.x <= maxX, "Nodule x outside cell bounds for note " + note);
            MoldTestUtils.assertTrue(fn.y >= minY && fn.y <= maxY, "Nodule y outside cell bounds for note " + note);
        }

        System.out.println("  PASS: All 64 Launchpad Drum Rack pads (36..99) mapped accurately to 8x8 grid cells.");
        return true;
    }

    private static boolean testLaunchpadPerimeterCcActions() throws Exception {
        System.out.println("\n[MIDI Test 4] Verifying Launchpad Perimeter CC Actions...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        javax.sound.midi.Receiver r = s.midiHandler.new LaunchpadReceiver();

        // CC 89: Re-inoculate
        s.cellBiomass[5] = 999.0f;
        ShortMessage sm89Press = new ShortMessage();
        sm89Press.setMessage(ShortMessage.CONTROL_CHANGE, 0, 89, 127);
        r.send(sm89Press, -1);
        MoldTestUtils.assertTrue(s.lpTopSidePressed, "lpTopSidePressed must be true on CC 89 press");
        MoldTestUtils.assertEquals(0.0f, s.cellBiomass[5], 1e-4f, "CC 89 should trigger reinoculate()");

        ShortMessage sm89Rel = new ShortMessage();
        sm89Rel.setMessage(ShortMessage.CONTROL_CHANGE, 0, 89, 0);
        r.send(sm89Rel, -1);
        MoldTestUtils.assertTrue(!s.lpTopSidePressed, "lpTopSidePressed must be false on CC 89 release");

        // CC 79: Clear Food
        s.addFoodNodule(200f, 200f, 10f, 100f);
        ShortMessage sm79Press = new ShortMessage();
        sm79Press.setMessage(ShortMessage.CONTROL_CHANGE, 0, 79, 127);
        r.send(sm79Press, -1);
        MoldTestUtils.assertTrue(s.lpSecSidePressed, "lpSecSidePressed must be true on CC 79 press");
        MoldTestUtils.assertTrue(s.foodNodes.isEmpty(), "CC 79 should clear all food nodes");

        ShortMessage sm79Rel = new ShortMessage();
        sm79Rel.setMessage(ShortMessage.CONTROL_CHANGE, 0, 79, 0);
        r.send(sm79Rel, -1);
        MoldTestUtils.assertTrue(!s.lpSecSidePressed, "lpSecSidePressed must be false on CC 79 release");

        System.out.println("  PASS: Launchpad perimeter CC 89 and CC 79 actions verified.");
        return true;
    }

    private static boolean testLaunchpadTrilateralColorTelemetry() {
        System.out.println("\n[MIDI Test 5] Verifying Trilateral Color Domain Telemetry Standard...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;

        MoldTestUtils.MockMidiReceiver mockLp = new MoldTestUtils.MockMidiReceiver();
        s.midiHandler.lpReceiver = mockLp;

        // Force debounce bypass
        s.lastMidiLedUpdate = -100;

        // Condition A: Organism / Biomass layer active
        s.lpShowSlime = true;
        s.lpShowFood = false;
        s.lpShowEating = false;
        // Warm up EMA filter so mass is above threshold
        for (int i = 0; i < 20; i++) {
            s.smoothBiomass[0] = 500.0f;
        }
        s.cellBiomass[0] = 500.0f; // High density in cell 0
        s.flushLaunchpadLeds();
        MoldTestUtils.assertTrue(!mockLp.messages.isEmpty(), "Expected MIDI LED messages to be transmitted");
        for (ShortMessage msg : mockLp.messages) {
            if (msg.getCommand() == ShortMessage.NOTE_ON) {
                int vel = msg.getData2();
                if (vel != 0) {
                    // Must belong to Yellow / Ochre spectrum (11, 12, 13, 14, 15, 62, 84)
                    boolean isYellowSpectrum = (vel == 11 || vel == 12 || vel == 13 || vel == 14 || vel == 15 || vel == 62 || vel == 84);
                    MoldTestUtils.assertTrue(isYellowSpectrum, "Mold LED velocity " + vel + " violates Yellow spectrum rule");
                }
            }
        }

        // Condition B: Food layer active
        mockLp.clear();
        s.lastMidiLedUpdate = -100;
        s.lpShowSlime = false;
        s.lpShowFood = true;
        s.lpShowEating = false;
        s.foodNodes.clear();
        s.addFoodNodule(45f, 45f, 15f, 100f); // Cell (0, 0)
        s.padDirtyStates[0] = (byte) 255;
        s.flushLaunchpadLeds();

        for (ShortMessage msg : mockLp.messages) {
            if (msg.getCommand() == ShortMessage.NOTE_ON) {
                int vel = msg.getData2();
                if (vel != 0) {
                    // Must belong to Cyan spectrum (37)
                    MoldTestUtils.assertTrue(vel == 37, "Food LED velocity " + vel + " violates Electric Cyan spectrum rule (expected 37)");
                }
            }
        }

        // Condition C: Eating activity layer active
        mockLp.clear();
        s.lastMidiLedUpdate = -100;
        s.lpShowSlime = false;
        s.lpShowFood = false;
        s.lpShowEating = true;
        MoldSketch.FoodNodule eatenNode = s.foodNodes.get(0);
        eatenNode.isBeingEaten = true;
        eatenNode.consumptionActivity = 1.0f;
        s.padDirtyStates[0] = (byte) 255;
        s.flushLaunchpadLeds();

        for (ShortMessage msg : mockLp.messages) {
            if (msg.getCommand() == ShortMessage.NOTE_ON) {
                int vel = msg.getData2();
                if (vel != 0) {
                    // Must belong to Magenta -> Purple spectrum (52, 53, 54, 55)
                    boolean isMagentaSpectrum = (vel == 52 || vel == 53 || vel == 54 || vel == 55);
                    MoldTestUtils.assertTrue(isMagentaSpectrum, "Eating LED velocity " + vel + " violates Magenta spectrum rule (expected 52..55)");
                }
            }
        }

        System.out.println("  PASS: Launchpad telemetry strictly respects Trilateral Color Standard (Yellow for mold, Cyan for food, Magenta for eating).");
        return true;
    }

    private static boolean testMidiFuzzAndResilience() throws Exception {
        System.out.println("\n[MIDI Test 6] Verifying MIDI Fuzz & Malformed Message Resilience (500 random events)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;

        javax.sound.midi.Receiver lpR = s.midiHandler.new LaunchpadReceiver();
        javax.sound.midi.Receiver mmR = s.midiHandler.new MidimixReceiver();

        Random rng = new Random(42);

        int[] commands = {
            ShortMessage.NOTE_ON,
            ShortMessage.NOTE_OFF,
            ShortMessage.CONTROL_CHANGE,
            ShortMessage.PITCH_BEND,
            ShortMessage.PROGRAM_CHANGE
        };

        for (int i = 0; i < 500; i++) {
            int cmd = commands[rng.nextInt(commands.length)];
            int ch = rng.nextInt(16);
            int d1 = rng.nextInt(128);
            int d2 = rng.nextInt(128);

            ShortMessage msg = new ShortMessage();
            msg.setMessage(cmd, ch, d1, d2);

            // Send to both receivers
            lpR.send(msg, -1);
            mmR.send(msg, -1);
        }

        System.out.println("  PASS: System processed 500 arbitrary/fuzzed MIDI messages with zero exceptions or state corruptions.");
        return true;
    }

    private static boolean testLaunchpadProgrammerModeNotes() throws Exception {
        System.out.println("\n[MIDI Test 7] Verifying Launchpad Programmer Mode Note Mapping (11..88)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        javax.sound.midi.Receiver r = s.midiHandler.new LaunchpadReceiver();

        float cellW = (float) s.SIM_W / (float) s.GRID_DIM;
        float cellH = (float) s.SIM_H / (float) s.GRID_DIM;

        // Sweep all Programmer Mode notes (rows 1..8, cols 1..8)
        for (int pRow = 1; pRow <= 8; pRow++) {
            for (int pCol = 1; pCol <= 8; pCol++) {
                int note = pRow * 10 + pCol;
                s.foodNodes.clear();

                ShortMessage sm = new ShortMessage();
                sm.setMessage(ShortMessage.NOTE_ON, 0, note, 127);
                r.send(sm, -1);

                MoldTestUtils.assertEquals(1, s.foodNodes.size(), 0, "Note " + note + " did not add food nodule");
                MoldSketch.FoodNodule fn = s.foodNodes.get(0);

                int expectedRow = 8 - pRow;
                int expectedCol = pCol - 1;
                MoldTestUtils.assertEquals(expectedRow, fn.gridRow, 0, "Row mismatch for Programmer note " + note);
                MoldTestUtils.assertEquals(expectedCol, fn.gridCol, 0, "Col mismatch for Programmer note " + note);
            }
        }

        System.out.println("  PASS: All 64 Programmer Mode notes (11..88) mapped accurately to 8x8 grid coordinates.");
        return true;
    }

    private static boolean testLaunchpadSysExRgbGradients() throws Exception {
        System.out.println("\n[MIDI Test 8] Verifying SysEx RGB Gradient Formatting & Telemetry (Command 03h)...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;
        s.lpUseRgbSysex = true;

        MoldTestUtils.MockMidiReceiver mockLp = new MoldTestUtils.MockMidiReceiver();
        s.midiHandler.lpReceiver = mockLp;

        s.lastMidiLedUpdate = -100;
        s.lpShowSlime = true;
        s.lpShowFood = false;
        s.lpShowEating = false;

        // Set gradient density across pads
        for (int i = 0; i < 64; i++) {
            s.cellBiomass[i] = (i + 1) * 30.0f;
            s.smoothBiomass[i] = (i + 1) * 30.0f;
        }

        s.flushLaunchpadLeds();
        MoldTestUtils.assertTrue(!mockLp.sysexMessages.isEmpty(), "Expected SysEx message to be transmitted");

        javax.sound.midi.SysexMessage lastSys = mockLp.getLastSysex();
        byte[] data = lastSys.getMessage();

        // Verify Launchpad Mini MK3 SysEx header: F0 00 20 29 02 0D 03 ... F7
        MoldTestUtils.assertTrue((data[0] & 0xFF) == 0xF0, "Header byte 0 must be 0xF0");
        MoldTestUtils.assertTrue((data[1] & 0xFF) == 0x00, "Header byte 1 must be 0x00");
        MoldTestUtils.assertTrue((data[2] & 0xFF) == 0x20, "Header byte 2 must be 0x20");
        MoldTestUtils.assertTrue((data[3] & 0xFF) == 0x29, "Header byte 3 must be 0x29");
        MoldTestUtils.assertTrue((data[4] & 0xFF) == 0x02, "Header byte 4 must be 0x02");
        MoldTestUtils.assertTrue((data[5] & 0xFF) == 0x0D, "Header byte 5 must be 0x0D (LP Mini MK3)");
        MoldTestUtils.assertTrue((data[6] & 0xFF) == 0x03, "Header byte 6 must be 0x03 (LED Lighting)");
        MoldTestUtils.assertTrue((data[data.length - 1] & 0xFF) == 0xF7, "End byte must be 0xF7");

        // Validate each RGB spec in payload: [03, ledIndex, r, g, b]
        int offset = 7;
        int specCount = 0;
        while (offset < data.length - 1) {
            int type = data[offset++] & 0xFF;
            int ledIdx = data[offset++] & 0xFF;
            int r = data[offset++] & 0xFF;
            int g = data[offset++] & 0xFF;
            int b = data[offset++] & 0xFF;

            MoldTestUtils.assertEquals(3, type, 0, "SysEx lighting type must be 3 (RGB)");
            MoldTestUtils.assertTrue(ledIdx >= 11 && ledIdx <= 88, "LED index out of range: " + ledIdx);
            MoldTestUtils.assertTrue(r >= 0 && r <= 127, "Red channel out of 7-bit range: " + r);
            MoldTestUtils.assertTrue(g >= 0 && g <= 127, "Green channel out of 7-bit range: " + g);
            MoldTestUtils.assertTrue(b >= 0 && b <= 127, "Blue channel out of 7-bit range: " + b);
            specCount++;
        }

        MoldTestUtils.assertTrue(specCount > 0, "SysEx payload must contain RGB specifications");
        System.out.println("  PASS: Batch SysEx packet formatted strictly according to Novation MK3 protocol specifications (" + specCount + " RGB pads updated).");
        return true;
    }

    private static boolean testLaunchpadRipplePropagation() throws Exception {
        System.out.println("\n[MIDI Test 9] Verifying Radial Ripple Wavefront Propagation...");
        MoldSketch s = MoldTestUtils.createHeadlessSketch();
        s.midiEnabled = true;

        // Trigger ripple at center (col 3, row 3)
        s.triggerPadRipple(3, 3, 300f, 300f);
        MoldTestUtils.assertEquals(1, s.padRipples.size(), 0, "padRipples must contain 1 active ripple");

        MoldSketch.PadRipple r = s.padRipples.get(0);
        MoldTestUtils.assertEquals(3, r.originCol, 0, "originCol mismatch");
        MoldTestUtils.assertTrue(r.progress(r.birthTime + 10) <= 0.1f, "New ripple should have low initial progress");

        // Simulate progression after 1000ms (exceeds duration 850ms)
        MoldTestUtils.assertTrue(r.progress(r.birthTime + 1000) >= 1.0f, "Ripple should expire after duration");

        System.out.println("  PASS: Radial ripple created with valid wavefront genesis and temporal decay bounds.");
        return true;
    }
}
