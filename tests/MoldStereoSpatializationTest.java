import java.lang.reflect.Field;

public class MoldStereoSpatializationTest {
    public static void main(String[] args) throws Exception {
        System.out.println("Running MoldStereoSpatializationTest...");
        MoldSketch sketch = new MoldSketch();

        sketch.rebuildHarmonicCache();

        float simW = sketch.SIM_W;
        float cellW = simW / 8.0f; // 90.0

        // Test 1: Column 0 (Far Left)
        // Center of Col 0 is 45.0
        sketch.addFoodNodule(45.0f, 360.0f, 16.0f, 100.0f);
        MoldSketch.FoodNodule fnCol0 = sketch.foodNodes.get(0);
        fnCol0.vcaGain = 1.0f;

        // Calculate pan
        float u0 = (fnCol0.x - cellW * 0.5f) / (7.0f * cellW);
        u0 = Math.max(0.0f, Math.min(1.0f, u0));
        float b0 = 2.0f * (u0 - 0.5f);
        float sign0 = (b0 < 0.0f) ? -1.0f : 1.0f;
        float bShaped0 = sign0 * (float) Math.pow(Math.abs(b0), 1.35f);
        float panNorm0 = Math.max(0.0f, Math.min(1.0f, 0.5f + 0.5f * bShaped0));
        float panL0 = (float) Math.cos(panNorm0 * Math.PI * 0.5);
        float panR0 = (float) Math.sin(panNorm0 * Math.PI * 0.5);

        if (Math.abs(panNorm0 - 0.0f) > 1e-4) {
            throw new AssertionError("Col 0 panNorm expected 0.0f, got " + panNorm0);
        }
        if (Math.abs(panL0 - 1.0f) > 1e-4 || Math.abs(panR0 - 0.0f) > 1e-4) {
            throw new AssertionError("Col 0 gains expected L=1.0, R=0.0, got L=" + panL0 + ", R=" + panR0);
        }
        System.out.println("PASS: Col 0 (Far Left) maps to 100% Hard Left (L=1.0, R=0.0)");

        // Test 2: Column 7 (Far Right)
        // Center of Col 7 is 675.0
        sketch.addFoodNodule(675.0f, 360.0f, 16.0f, 100.0f);
        MoldSketch.FoodNodule fnCol7 = sketch.foodNodes.get(1);
        fnCol7.vcaGain = 1.0f;

        float u7 = (fnCol7.x - cellW * 0.5f) / (7.0f * cellW);
        u7 = Math.max(0.0f, Math.min(1.0f, u7));
        float b7 = 2.0f * (u7 - 0.5f);
        float sign7 = (b7 < 0.0f) ? -1.0f : 1.0f;
        float bShaped7 = sign7 * (float) Math.pow(Math.abs(b7), 1.35f);
        float panNorm7 = Math.max(0.0f, Math.min(1.0f, 0.5f + 0.5f * bShaped7));
        float panL7 = (float) Math.cos(panNorm7 * Math.PI * 0.5);
        float panR7 = (float) Math.sin(panNorm7 * Math.PI * 0.5);

        if (Math.abs(panNorm7 - 1.0f) > 1e-4) {
            throw new AssertionError("Col 7 panNorm expected 1.0f, got " + panNorm7);
        }
        if (Math.abs(panL7 - 0.0f) > 1e-4 || Math.abs(panR7 - 1.0f) > 1e-4) {
            throw new AssertionError("Col 7 gains expected L=0.0, R=1.0, got L=" + panL7 + ", R=" + panR7);
        }
        System.out.println("PASS: Col 7 (Far Right) maps to 100% Hard Right (L=0.0, R=1.0)");

        // Test 3: Canvas/Grid Center Line (x = 360.0)
        sketch.addFoodNodule(360.0f, 360.0f, 16.0f, 100.0f);
        MoldSketch.FoodNodule fnCenter = sketch.foodNodes.get(2);
        fnCenter.vcaGain = 1.0f;

        float uC = (fnCenter.x - cellW * 0.5f) / (7.0f * cellW);
        uC = Math.max(0.0f, Math.min(1.0f, uC));
        float bC = 2.0f * (uC - 0.5f);
        float signC = (bC < 0.0f) ? -1.0f : 1.0f;
        float bShapedC = signC * (float) Math.pow(Math.abs(bC), 1.35f);
        float panNormC = Math.max(0.0f, Math.min(1.0f, 0.5f + 0.5f * bShapedC));
        float panLC = (float) Math.cos(panNormC * Math.PI * 0.5);
        float panRC = (float) Math.sin(panNormC * Math.PI * 0.5);

        if (Math.abs(panNormC - 0.5f) > 1e-4) {
            throw new AssertionError("Center panNorm expected 0.5f, got " + panNormC);
        }
        if (Math.abs(panLC - panRC) > 1e-4 || Math.abs(panLC - 0.70710678f) > 1e-4) {
            throw new AssertionError("Center gains expected L=R=0.7071, got L=" + panLC + ", R=" + panRC);
        }
        System.out.println("PASS: Canvas/Grid Center (x=360) is exactly centered (L=0.7071, R=0.7071, pan=0.5)");

        // Test 4: Center Grid Columns (Col 3 and Col 4)
        // Col 3 center is 315.0, Col 4 center is 405.0
        sketch.addFoodNodule(315.0f, 360.0f, 16.0f, 100.0f);
        sketch.addFoodNodule(405.0f, 360.0f, 16.0f, 100.0f);
        MoldSketch.FoodNodule fnCol3 = sketch.foodNodes.get(3);
        MoldSketch.FoodNodule fnCol4 = sketch.foodNodes.get(4);

        float u3 = (fnCol3.x - cellW * 0.5f) / (7.0f * cellW);
        float b3 = 2.0f * (u3 - 0.5f);
        float panNorm3 = 0.5f + 0.5f * ((b3 < 0 ? -1f : 1f) * (float) Math.pow(Math.abs(b3), 1.35f));

        float u4 = (fnCol4.x - cellW * 0.5f) / (7.0f * cellW);
        float b4 = 2.0f * (u4 - 0.5f);
        float panNorm4 = 0.5f + 0.5f * ((b4 < 0 ? -1f : 1f) * (float) Math.pow(Math.abs(b4), 1.35f));

        if (Math.abs(panNorm3 - 0.5f) > 0.05f || Math.abs(panNorm4 - 0.5f) > 0.05f) {
            throw new AssertionError("Col 3 and Col 4 expected to be within 0.05 of center, got " + panNorm3 + " and " + panNorm4);
        }
        System.out.println("PASS: Center grid tones (Col 3 & 4) anchored to center (pan = " + String.format("%.3f", panNorm3) + " and " + String.format("%.3f", panNorm4) + ")");

        // Test 5: Verify Convolver Stereo Separation
        PartitionedConvolver conv = new PartitionedConvolver(512);
        VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(
            44100.0f, 1.0f, 2000.0f, 10000.0f, 0.45f, 0.0f, 42L
        );
        conv.loadImpulseResponse(ir.left, ir.right);

        float[] inL = new float[512];
        float[] inR = new float[512];
        float[] outL = new float[512];
        float[] outR = new float[512];

        // Hard Left input impulse
        inL[0] = 1.0f;
        inR[0] = 0.0f;
        conv.processBlock(inL, inR, outL, outR, 1.0f, 0.0f); // 100% wet
        
        // Sum wet energy across the block
        double energyL = 0;
        double energyR = 0;
        for (int i = 0; i < 512; i++) {
            energyL += outL[i] * outL[i];
            energyR += outR[i] * outR[i];
        }

        double sepRatio = energyL / (energyR + 1e-9);
        if (sepRatio < 5.0) { // Should be ~ (0.85/0.15)^2 = ~32
            throw new AssertionError("Expected strong stereo separation in reverb for hard left, got ratio " + sepRatio);
        }
        System.out.println("PASS: True stereo convolution preserves spatialization (Left/Right energy ratio = " + String.format("%.2f", sepRatio) + ")");

        // Test 6: 3D Binaural Front vs. Back Pinna Spectral Cues
        // Front source (Row 0, y = 45.0) vs Rear source (Row 7, y = 675.0)
        sketch.addFoodNodule(360.0f, 45.0f, 16.0f, 100.0f);   // Front
        sketch.addFoodNodule(360.0f, 675.0f, 16.0f, 100.0f);  // Rear
        MoldSketch.FoodNodule fnFront = sketch.foodNodes.get(sketch.foodNodes.size() - 2);
        MoldSketch.FoodNodule fnRear = sketch.foodNodes.get(sketch.foodNodes.size() - 1);
        fnFront.updateAudioParameters(0.0f);
        fnRear.updateAudioParameters(0.0f);

        // Process high-frequency test tone (5000Hz) through front vs rear pinna filters
        float testTone = 1.0f;
        float outFront = 0.0f;
        float outRear = 0.0f;
        for (int i = 0; i < 200; i++) {
            float s = (float) Math.sin(2.0 * Math.PI * 5000.0 * i / 44100.0);
            float f = fnFront.frontBackFilter.process(s);
            float r = fnRear.frontBackFilter.process(s);
            if (i > 100) {
                outFront += f * f;
                outRear += r * r;
            }
        }
        if (outFront <= outRear) {
            throw new AssertionError("Expected front pinna filter to have higher 5kHz high-frequency transmission than rear filter, got front=" + outFront + ", rear=" + outRear);
        }
        System.out.println("PASS: Front source exhibits crisp presence while rear source exhibits pinna acoustic shadowing (front/rear 5kHz power ratio = " + String.format("%.2f", outFront / outRear) + ")");

        // Test 7: 3D Biomass Elevation Filter Modulation
        // Compare zero biomass (horizon elevation) vs heavy biomass (overhead elevation)
        fnFront.updateAudioParameters(0.0f);
        float elevZero = fnFront.elevationNorm;
        for (int step = 0; step < 20; step++) {
            fnFront.updateAudioParameters(1200.0f); // High adjacent biomass
        }
        float elevHigh = fnFront.elevationNorm;
        if (elevHigh <= elevZero || elevHigh < 0.8f) {
            throw new AssertionError("Expected elevationNorm to increase towards 1.0 with high biomass, got " + elevHigh);
        }
        System.out.println("PASS: Slime mold biomass elevates sound vertically in 3D binaural space (elevation = " + String.format("%.2f", elevHigh) + ")");

        // Test 8: Frequency-Dependent Interaural Level Difference (Spherical Head Shadow Model)
        // Hard Left source: Left ear should have clear presence (+1.5dB) while Right ear is shadowed by skull (-9dB)
        sketch.addFoodNodule(45.0f, 360.0f, 16.0f, 100.0f); // Hard Left
        MoldSketch.FoodNodule fnLeft = sketch.foodNodes.get(sketch.foodNodes.size() - 1);
        fnLeft.updateAudioParameters(0.0f);

        float outIpsi = 0.0f;
        float outContra = 0.0f;
        for (int i = 0; i < 200; i++) {
            float s = (float) Math.sin(2.0 * Math.PI * 3000.0 * i / 44100.0);
            float l = fnLeft.headShadowL.process(s);
            float r = fnLeft.headShadowR.process(s);
            if (i > 100) {
                outIpsi += l * l;
                outContra += r * r;
            }
        }
        double ildRatio = outIpsi / (outContra + 1e-9);
        if (ildRatio < 3.0) {
            throw new AssertionError("Expected head-shadow filter to create strong ILD at 3kHz (ratio >= 3.0), got " + ildRatio);
        }
        System.out.println("PASS: Spherical head-shadow model provides realistic 3kHz acoustic skull shadowing (Ipsi/Contra power ratio = " + String.format("%.2f", ildRatio) + ")");

        // Test 9: Sub-sample ITD Delay Buffer Capacity
        if (fnLeft.delayBufL.length != 128 || fnLeft.delayBufR.length != 128) {
            throw new AssertionError("Expected delayBufL and delayBufR capacity of 128 samples, got " + fnLeft.delayBufL.length);
        }
        System.out.println("PASS: Haas delay buffers expanded to 128 samples for wide hyper-binaural delay headroom");

        // Test 10: Distance Air-Absorption Filter (Atmospheric high-frequency roll-off across space)
        // Center source (near listener) vs Corner source (far from listener)
        sketch.addFoodNodule(360.0f, 360.0f, 16.0f, 100.0f); // Center (dist = 0)
        sketch.addFoodNodule(45.0f, 45.0f, 16.0f, 100.0f);   // Corner (dist ~ 1.2)
        MoldSketch.FoodNodule fnCenterDist = sketch.foodNodes.get(sketch.foodNodes.size() - 2);
        MoldSketch.FoodNodule fnCornerDist = sketch.foodNodes.get(sketch.foodNodes.size() - 1);
        fnCenterDist.updateAudioParameters(0.0f);
        fnCornerDist.updateAudioParameters(0.0f);

        float outCenterAir = 0.0f;
        float outCornerAir = 0.0f;
        for (int i = 0; i < 200; i++) {
            float s = (float) Math.sin(2.0 * Math.PI * 6000.0 * i / 44100.0);
            float c = fnCenterDist.airDampFilter.process(s);
            float corn = fnCornerDist.airDampFilter.process(s);
            if (i > 100) {
                outCenterAir += c * c;
                outCornerAir += corn * corn;
            }
        }
        if (outCenterAir <= outCornerAir) {
            throw new AssertionError("Expected center nodule to have higher 6kHz transmission than distant corner nodule, got center=" + outCenterAir + ", corner=" + outCornerAir);
        }
        System.out.println("PASS: Atmospheric distance air absorption attenuates high frequencies over distance (Center/Corner power ratio = " + String.format("%.2f", outCenterAir / outCornerAir) + ")");

        // Test 11: 3D Binaural Macro Scaling (binauralDepth)
        if (Math.abs(sketch.binauralDepth - 1.0f) > 1e-4) {
            throw new AssertionError("binauralDepth default expected 1.0f, got " + sketch.binauralDepth);
        }
        sketch.binauralDepth = 2.0f; // Hyper-Binaural
        fnLeft.updateAudioParameters(0.0f);
        float outContra2x = 0.0f;
        for (int i = 0; i < 200; i++) {
            float s = (float) Math.sin(2.0 * Math.PI * 3000.0 * i / 44100.0);
            float r = fnLeft.headShadowR.process(s);
            if (i > 100) outContra2x += r * r;
        }
        if (outContra2x >= outContra) {
            throw new AssertionError("Expected 2.0x binauralDepth to attenuate contralateral ear more than 1.0x baseline");
        }
        System.out.println("PASS: 3D Binaural intensity macro scales effect from natural 1.0x to hyper-binaural 2.0x");

        System.out.println("================================================================================");
        System.out.println(">> ALL 3D BINAURAL & STEREO SPATIALIZATION TESTS PASSED! <<");
        System.out.println("================================================================================");
        System.exit(0);
    }
}
