// =============================================================================
// Audio.pde - Sound Engine, UP-OLA Velvet Convolver & Bio-Telemetry Modulation
// =============================================================================

void triggerIrRegenerationAsync() {
  final float sr = 44100.0f;
  final float t60 = reverbT60;
  final float d0 = 2000.0f;
  final float dMax = 10000.0f;
  final float damp = reverbHighDamping;
  final float pre = reverbPreDelay;
  final long s = reverbSeed;

  irExecutor.submit(() -> {
    try {
      VelvetImpulseGenerator.StereoIR newIr = VelvetImpulseGenerator.generate(
        sr, t60, d0, dMax, damp, pre, s
      );
      if (audioEngine != null && audioEngine.convolver != null) {
        audioEngine.convolver.loadImpulseResponse(newIr.left, newIr.right);
      }
    } catch (Exception e) {
      println("Async IR Generation Error: " + e.getMessage());
    }
  });
}

// Bio-sonification modulation telemetry for velvet convolver
void updateReverbBioTelemetry() {
  float totalBiomass = 0.0f;
  for (int i = 0; i < 64; i++) {
    totalBiomass += cellBiomass[i];
  }

  if (autoModulateReverb) {
    // 1. Total Colony Biomass -> Wet / Dry Balance: Wet = tanh(Biomass / 10000) * 0.8
    float wet = (float) Math.tanh(totalBiomass / 10000.0f) * 0.8f;
    float dry = 1.0f - (wet * 0.4f);
    reverbWet = constrain(wet, 0.0f, 1.0f);
    reverbDry = constrain(dry, 0.0f, 1.0f);

    // 2. Locomotion Exploration Cost -> High-Frequency Damping (alpha_max): alpha_max = 0.2 + 0.6 * (Cost / 0.1)
    float targetDamp = constrain(0.2f + 0.6f * (locomotionCost / 0.1f), 0.05f, 0.95f);

    // 3. Longest Active Artery (Tendril Reach) -> Pre-Delay: t_pre = 5ms + (Reach / 45px) * 40ms
    float targetPreDelay = constrain(0.005f + (sensorDist / 45.0f) * 0.040f, 0.005f, 0.060f);

    boolean needRegen = false;

    // 4. Mitosis Burst Event -> Impulse Seed Re-trigger on mass doubling
    if (totalBiomass >= lastMitosisBiomassThreshold * 2.0f && totalBiomass > 2000.0f) {
      reverbSeed = System.nanoTime() ^ (long) totalBiomass;
      lastMitosisBiomassThreshold = totalBiomass;
      needRegen = true;
    }

    if (Math.abs(reverbHighDamping - targetDamp) > 0.08f) {
      reverbHighDamping = targetDamp;
      needRegen = true;
    }
    if (Math.abs(reverbPreDelay - targetPreDelay) > 0.010f) {
      reverbPreDelay = targetPreDelay;
      needRegen = true;
    }

    if (needRegen) {
      triggerIrRegenerationAsync();
    }

    if (reverbWetSlider != null) reverbWetSlider.setValue(reverbWet, false);
    if (reverbDrySlider != null) reverbDrySlider.setValue(reverbDry, false);
    if (reverbDampSlider != null) reverbDampSlider.setValue(reverbHighDamping, false);
    if (reverbPreSlider != null) reverbPreSlider.setValue(reverbPreDelay, false);
  }
}

// Biquad lowpass resonant digital filter
class BiquadFilter {
  float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  float x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  void setLowPass(float cutoffHz, float q, float sampleRate) {
    float omega = TWO_PI * constrain(cutoffHz, 40.0f, sampleRate * 0.45f) / sampleRate;
    float alpha = sin(omega) / (2.0f * max(0.1f, q));
    float cosW = cos(omega);

    float a0 = 1.0f + alpha;
    b0 = ((1.0f - cosW) / 2.0f) / a0;
    b1 = (1.0f - cosW) / a0;
    b2 = ((1.0f - cosW) / 2.0f) / a0;
    a1 = (-2.0f * cosW) / a0;
    a2 = (1.0f - alpha) / a0;
  }

  float process(float in) {
    float out = b0 * in + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = in;
    y2 = y1;
    y1 = out;
    return out;
  }
}

// Multi-threaded stereo PCM audio engine with UP-OLA Velvet Convolver & Master Dynamics Limiter
class AudioEngine extends Thread {
  SourceDataLine line;
  PartitionedConvolver convolver;
  volatile boolean running = true;
  final int SAMPLE_RATE = 44100;
  final int BUFFER_SAMPLES = 512;

  // Master Dynamics Limiter & AGC envelope follower
  float env = 0.0f;
  // Attack ~2ms, Release ~100ms
  final float attackCoeff = (float) Math.exp(-1.0 / (0.002 * 44100.0));
  final float releaseCoeff = (float) Math.exp(-1.0 / (0.100 * 44100.0));

  public void run() {
    try {
      convolver = new PartitionedConvolver(BUFFER_SAMPLES);
      VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(
        SAMPLE_RATE, reverbT60, 2000.0f, 10000.0f, reverbHighDamping, reverbPreDelay, reverbSeed
      );
      convolver.loadImpulseResponse(ir.left, ir.right);

      AudioFormat format = new AudioFormat(SAMPLE_RATE, 16, 2, true, false);
      DataLine.Info info = new DataLine.Info(SourceDataLine.class, format);
      line = (SourceDataLine) AudioSystem.getLine(info);
      line.open(format, BUFFER_SAMPLES * 4 * 4);
      line.start();

      float[] sineTable = new float[4096];
      for (int i = 0; i < 4096; i++) {
        sineTable[i] = (float) Math.sin((i / 4096.0) * Math.PI * 2.0);
      }

      byte[] byteBuffer = new byte[BUFFER_SAMPLES * 4];
      byte[] silence = new byte[BUFFER_SAMPLES * 4];
      float[] inL = new float[BUFFER_SAMPLES];
      float[] inR = new float[BUFFER_SAMPLES];
      float[] outL = new float[BUFFER_SAMPLES];
      float[] outR = new float[BUFFER_SAMPLES];

      while (running) {
        if (!audioEnabled || foodNodes.isEmpty()) {
          line.write(silence, 0, silence.length);
          try { Thread.sleep(8); } catch (Exception e) {}
          continue;
        }

        int wave = waveformIdx; // read once per buffer

        // Count active voices and apply proportional headroom scaling (1 / sqrt(N))
        int activeVoices = 0;
        for (int v = 0; v < foodNodes.size(); v++) {
          try {
            FoodNodule fn = foodNodes.get(v);
            if (fn.vcaGain >= 0.001f) activeVoices++;
          } catch (IndexOutOfBoundsException e) { break; }
        }
        float voiceScale = (activeVoices > 0) ? (0.24f / (float) Math.sqrt(Math.max(1.0, activeVoices * 0.75))) : 0.24f;

        // Clear input block buffers
        for (int i = 0; i < BUFFER_SAMPLES; i++) {
          inL[i] = 0.0f;
          inR[i] = 0.0f;
        }

        for (int v = 0; v < foodNodes.size(); v++) {
          FoodNodule fn;
          try {
            fn = foodNodes.get(v);
          } catch (IndexOutOfBoundsException e) { break; }
          
          if (fn.vcaGain < 0.001f) continue;

          // Pan voices across stereo field based on canvas horizontal location
          float panNorm = constrain(fn.x / (float) SIM_W, 0.05f, 0.95f);
          float panL = (float) Math.cos(panNorm * Math.PI * 0.5);
          float panR = (float) Math.sin(panNorm * Math.PI * 0.5);
          float voiceGainL = fn.vcaGain * voiceScale * panL;
          float voiceGainR = fn.vcaGain * voiceScale * panR;

          for (int i = 0; i < BUFFER_SAMPLES; i++) {
            float raw;
            if (wave == 0) {        // Triangle
              raw = (fn.phase < 0.5f) ? (4.0f * fn.phase - 1.0f) : (3.0f - 4.0f * fn.phase);
            } else if (wave == 1) { // Sine
              int idx = (int)(fn.phase * 4096f) & 4095;
              raw = sineTable[idx];
            } else if (wave == 2) { // Sawtooth
              raw = 2.0f * fn.phase - 1.0f;
            } else {                // Square
              raw = (fn.phase < 0.5f) ? 0.8f : -0.8f;
            }

            fn.phase = (fn.phase + fn.frequency / SAMPLE_RATE) % 1.0f;

            float filtered = fn.filter.process(raw);
            inL[i] += filtered * voiceGainL;
            inR[i] += filtered * voiceGainR;
          }
        }

        // Real-Time UP-OLA Velvet Noise Convolver
        if (reverbEnabled && convolver != null && convolver.isLoaded()) {
          convolver.processBlock(inL, inR, outL, outR, reverbWet, reverbDry);
        } else {
          for (int i = 0; i < BUFFER_SAMPLES; i++) {
            outL[i] = inL[i];
            outR[i] = inR[i];
          }
        }

        for (int i = 0; i < BUFFER_SAMPLES; i++) {
          // Stereo peak detector envelope follower
          float absSample = Math.max(Math.abs(outL[i]), Math.abs(outR[i]));
          if (absSample > env) {
            env = attackCoeff * env + (1.0f - attackCoeff) * absSample;
          } else {
            env = releaseCoeff * env + (1.0f - releaseCoeff) * absSample;
          }

          // Fast-acting transparent limiter: threshold = 0.75 (~ -2.5 dB)
          float limiterGain = 1.0f;
          final float threshold = 0.75f;
          if (env > threshold) {
            limiterGain = threshold / env;
          }

          float limitedL = outL[i] * limiterGain;
          float limitedR = outR[i] * limiterGain;

          // Transparent soft knee ceiling as a safety brickwall (guaranteed <= 0.98, zero harsh distortion)
          float finalL = softKnee(limitedL);
          float finalR = softKnee(limitedR);

          short pcmL = (short) (finalL * 32000.0f);
          short pcmR = (short) (finalR * 32000.0f);

          int bIdx = i * 4;
          byteBuffer[bIdx]     = (byte) (pcmL & 0xFF);
          byteBuffer[bIdx + 1] = (byte) ((pcmL >> 8) & 0xFF);
          byteBuffer[bIdx + 2] = (byte) (pcmR & 0xFF);
          byteBuffer[bIdx + 3] = (byte) ((pcmR >> 8) & 0xFF);
        }

        line.write(byteBuffer, 0, byteBuffer.length);
      }
    } catch (Exception e) {
      println("Audio Engine Exception: " + e.getMessage());
    }
  }

  private float fastTanh(float x) {
    if (x < -3.0f) return -1.0f;
    if (x > 3.0f) return 1.0f;
    float x2 = x * x;
    return x * (27.0f + x2) / (27.0f + 9.0f * x2);
  }

  private float softKnee(float v) {
    if (v > 0.85f) {
      return 0.85f + 0.13f * fastTanh((v - 0.85f) / 0.13f);
    } else if (v < -0.85f) {
      return -0.85f + 0.13f * fastTanh((v + 0.85f) / 0.13f);
    } else {
      return v;
    }
  }

  void closeEngine() {
    running = false;
    if (line != null) {
      line.stop();
      line.close();
    }
  }
}
