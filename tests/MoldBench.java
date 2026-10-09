/**
 * MoldBench.java - headless performance benchmark for the hot paths.
 * Runs the real sketch code (via the generated MoldSketch class) without a window.
 */
public class MoldBench {

    static double msPer(Runnable r, int warm, int iters) {
        for (int i = 0; i < warm; i++) r.run();
        long t0 = System.nanoTime();
        for (int i = 0; i < iters; i++) r.run();
        return (System.nanoTime() - t0) / 1e6 / iters;
    }

    public static void main(String[] args) {
        final MoldSketch s = new MoldSketch();
        s.randomSeed(1234);
        // Mirror setup() without opening a window or starting audio/MIDI
        s.trailMap = new float[s.SIM_W * s.SIM_H];
        s.nextTrailMap = new float[s.SIM_W * s.SIM_H];
        s.agentX = new float[s.MAX_AGENTS];
        s.agentY = new float[s.MAX_AGENTS];
        s.agentHeading = new float[s.MAX_AGENTS];
        s.agentEnergy = new float[s.MAX_AGENTS];
        s.rebuildHarmonicCache();
        s.seedCentralInoculate();
        s.scatterInitialFood(6);

        // Grow the colony to a heavy, realistic load
        for (int i = 0; i < 1500; i++) { s.stepBioenergetics(); s.diffuseAndEvaporate(); s.updateGridBiomassAndFood(); }
        // Pin agent count at max for a worst-case, repeatable measurement
        s.bmr = 0.0f; s.locomotionCost = 0.0f;
        while (s.activeAgentCount < s.MAX_AGENTS) {
            int i = s.activeAgentCount++;
            s.agentX[i] = s.random(s.SIM_W); s.agentY[i] = s.random(s.SIM_H);
            s.agentHeading[i] = s.random(6.283f); s.agentEnergy[i] = 50f;
        }
        while (s.foodNodes.size() < 8) s.addFoodNodule(s.random(40, 380), s.random(40, 380), 16f, 1e9f);

        System.out.printf("Agents: %d  Food: %d%n", s.activeAgentCount, s.foodNodes.size());
        double agents = msPer(s::stepBioenergetics, 200, 400);
        double diffuse = msPer(s::diffuseAndEvaporate, 200, 400);
        double grid = msPer(s::updateGridBiomassAndFood, 200, 400);
        System.out.printf("stepBioenergetics      : %7.3f ms%n", agents);
        System.out.printf("diffuseAndEvaporate    : %7.3f ms%n", diffuse);
        System.out.printf("updateGridBiomassAndFood: %6.3f ms%n", grid);
        System.out.printf("Sim step total (1 step): %6.3f ms  (frame budget @60fps = 16.7 ms)%n",
                agents + diffuse + grid);

        // ---- Audio: convolver with the longest IR (T60 = 8 s) ----
        final int B = 512;
        VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(44100f, 8.0f, 2000f, 10000f, 0.45f, 0.06f, 7L);
        final PartitionedConvolver conv = new PartitionedConvolver(B);
        conv.loadImpulseResponse(ir.left, ir.right);
        final float[] inL = new float[B], inR = new float[B], oL = new float[B], oR = new float[B];
        for (int i = 0; i < B; i++) { inL[i] = (float) Math.sin(i * 0.06); inR[i] = inL[i]; }
        double convMs = msPer(() -> conv.processBlock(inL, inR, oL, oR, 0.6f, 0.8f), 300, 600);
        double blockBudget = 1000.0 * B / 44100.0;
        System.out.printf("Convolver block (T60=8s, %d partitions): %6.3f ms  (%.0f%% of %.1f ms real-time budget)%n",
                conv.getNumPartitions(), convMs, 100 * convMs / blockBudget, blockBudget);

        final MoldSketch.StudioMasterLimiter lim = s.new StudioMasterLimiter(44100f);
        final float[] mL = new float[B], mR = new float[B];
        double limMs = msPer(() -> lim.process(oL, oR, mL, mR, B), 2000, 20000);
        System.out.printf("Master limiter block   : %7.4f ms%n", limMs);
    }
}
