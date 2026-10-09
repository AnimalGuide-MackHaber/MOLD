import java.util.ArrayList;
import java.util.List;
import javax.sound.midi.MidiMessage;
import javax.sound.midi.Receiver;
import javax.sound.midi.ShortMessage;

/**
 * MoldTestUtils.java
 *
 * Shared utilities, headless sketch harness, and MIDI mocks for testing.
 */
public class MoldTestUtils {

    /**
     * Creates and initializes a fully working MoldSketch instance for headless testing
     * without opening windows or instantiating OpenGL / soundcard hardware.
     */
    public static MoldSketch createHeadlessSketch() {
        MoldSketch s = new MoldSketch();
        s.randomSeed(42);

        // Allocate simulation buffers
        s.trailMap = new float[s.SIM_W * s.SIM_H];
        s.nextTrailMap = new float[s.SIM_W * s.SIM_H];
        s.agentX = new float[s.MAX_AGENTS];
        s.agentY = new float[s.MAX_AGENTS];
        s.agentHeading = new float[s.MAX_AGENTS];
        s.agentEnergy = new float[s.MAX_AGENTS];

        for (int i = 0; i < 64; i++) {
            s.padDirtyStates[i] = (byte) 255;
        }

        s.rebuildHarmonicCache();
        s.seedCentralInoculate();

        s.midiHandler = s.new MidiHandler();
        s.buildUI();

        return s;
    }

    /**
     * Mock MIDI Receiver for capturing transmitted ShortMessages and SysexMessages in unit tests.
     */
    public static class MockMidiReceiver implements Receiver {
        public final List<ShortMessage> messages = new ArrayList<>();
        public final List<javax.sound.midi.SysexMessage> sysexMessages = new ArrayList<>();

        @Override
        public void send(MidiMessage message, long timeStamp) {
            if (message instanceof ShortMessage) {
                messages.add((ShortMessage) message);
            } else if (message instanceof javax.sound.midi.SysexMessage) {
                sysexMessages.add((javax.sound.midi.SysexMessage) message);
            }
        }

        @Override
        public void close() {
            messages.clear();
            sysexMessages.clear();
        }

        public void clear() {
            messages.clear();
            sysexMessages.clear();
        }

        public ShortMessage getLastMessage() {
            return messages.isEmpty() ? null : messages.get(messages.size() - 1);
        }

        public javax.sound.midi.SysexMessage getLastSysex() {
            return sysexMessages.isEmpty() ? null : sysexMessages.get(sysexMessages.size() - 1);
        }
    }

    public static void assertInRange(float val, float min, float max, String name) {
        if (Float.isNaN(val) || Float.isInfinite(val)) {
            throw new AssertionError(name + " is NaN or Infinite: " + val);
        }
        if (val < min - 1e-5f || val > max + 1e-5f) {
            throw new AssertionError(name + " out of bounds [" + min + ", " + max + "]: got " + val);
        }
    }

    public static void assertEquals(float expected, float actual, float eps, String message) {
        if (Math.abs(expected - actual) > eps) {
            throw new AssertionError(message + " (expected: " + expected + ", got: " + actual + ")");
        }
    }

    public static void assertTrue(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError("Assertion failed: " + message);
        }
    }
}
