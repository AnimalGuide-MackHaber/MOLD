// =============================================================================
// Audio.pde - Sound Engine, UP-OLA Velvet Convolver & Bio-Telemetry Modulation
// =============================================================================

long lastIrRegenTime = 0;

void triggerIrRegenerationAsync() {
  long now = millis();
  if (now - lastIrRegenTime < 250) return; // Debounce rapid regenerations
  lastIrRegenTime = now;

  final float sr = 44100.0f;
  final float t60 = constrain(reverbT60, 0.5f, 4.0f);
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

// Safely synchronize UI sliders with current reverb parameters
void syncReverbUiSliders() {
  if (reverbWetSlider != null && !reverbWetSlider.dragging) reverbWetSlider.setValue(reverbWet, false);
  if (reverbDrySlider != null && !reverbDrySlider.dragging) reverbDrySlider.setValue(reverbDry, false);
  if (reverbT60Slider != null && !reverbT60Slider.dragging) reverbT60Slider.setValue(reverbT60, false);
  if (reverbDampSlider != null && !reverbDampSlider.dragging) reverbDampSlider.setValue(reverbHighDamping, false);
  if (reverbPreSlider != null && !reverbPreSlider.dragging) reverbPreSlider.setValue(reverbPreDelay, false);
}

// Extract spatial arterial dispersion across 8x8 petri grid
float[] computePetriDispersion() {
  float maxDistFromCenter = 0.0f;
  int occupiedCells = 0;
  for (int i = 0; i < 64; i++) {
    if (cellBiomass[i] > 25.0f) {
      occupiedCells++;
      int c = i % GRID_DIM;
      int r = i / GRID_DIM;
      float distFromCenter = dist(c + 0.5f, r + 0.5f, 3.5f, 3.5f) / 4.95f; // [0.0 center, 1.0 outer corners]
      if (distFromCenter > maxDistFromCenter) maxDistFromCenter = distFromCenter;
    }
  }
  float colonySpread = constrain(maxDistFromCenter, 0.0f, 1.0f);
  float spreadRatio = constrain(occupiedCells / 32.0f, 0.0f, 2.0f);
  return new float[]{colonySpread, spreadRatio};
}

// Extract feeding/grazing ratio across food nodules
float computeFeedingRatio() {
  float totalFeeding = 0.0f;
  int activeFoodCount = 0;
  for (int f = 0; f < foodNodes.size(); f++) {
    try {
      FoodNodule fn = foodNodes.get(f);
      activeFoodCount++;
      if (fn.isBeingEaten) totalFeeding += fn.consumptionActivity;
    } catch (Exception e) { break; }
  }
  return (activeFoodCount > 0) ? constrain(totalFeeding / activeFoodCount, 0.0f, 1.0f) : 0.0f;
}

// Bio-sonification modulation telemetry for velvet convolver
void updateReverbBioTelemetry() {
  float totalBiomass = 0.0f;
  for (int i = 0; i < 64; i++) {
    totalBiomass += cellBiomass[i];
  }

  if (!autoModulateReverb) return;

  if (reverbBioModDepth <= 0.001f) {
    // Zero modulation depth: directly follow manual base settings
    reverbWet = baseReverbWet;
    reverbDry = baseReverbDry;
    reverbT60 = baseReverbT60;
    reverbHighDamping = baseReverbHighDamping;
    reverbPreDelay = baseReverbPreDelay;
    syncReverbUiSliders();
    return;
  }

  // --- Dynamic Bio-Telemetry Metrics from Mold State ---
  float nominalBiomass = max(1000.0f, targetAgentCount * 50.0f);
  float massRatio = totalBiomass / nominalBiomass;
  float massDelta = massRatio - 1.0f;

  float[] dispersion = computePetriDispersion();
  float colonySpread = dispersion[0];
  float spreadRatio = dispersion[1];

  float feedingRatio = computeFeedingRatio();

  float locoFactor = constrain(locomotionCost / 0.018f, 0.2f, 3.0f);
  float sensorFactor = constrain(sensorDist / 40.0f, 0.2f, 3.0f);

  // Wet / Dry Balance
  float wetDelta = massDelta * 0.20f + (colonySpread - 0.4f) * 0.15f + feedingRatio * 0.15f;
  float targetWet = constrain(baseReverbWet + wetDelta * reverbBioModDepth, 0.0f, 1.0f);
  float targetDry = constrain(baseReverbDry - (wetDelta * 0.75f) * reverbBioModDepth, 0.05f, 1.0f);

  reverbWet += (targetWet - reverbWet) * 0.12f;
  reverbDry += (targetDry - reverbDry) * 0.12f;

  // High-Frequency Damping (alpha)
  float dampDelta = feedingRatio * 0.16f + (spreadRatio - 0.5f) * 0.12f - (locoFactor - 1.0f) * 0.10f;
  float targetDamp = constrain(baseReverbHighDamping + dampDelta * reverbBioModDepth, 0.05f, 0.95f);

  // Tendril Reach -> Pre-Delay
  float preDelta = (colonySpread - 0.3f) * 0.015f + (sensorFactor - 1.0f) * 0.010f;
  float targetPreDelay = constrain(baseReverbPreDelay + preDelta * reverbBioModDepth, 0.005f, 0.060f);

  // Decay Time (T60)
  float t60Delta = massDelta * 0.7f + (colonySpread - 0.4f) * 0.5f + feedingRatio * 0.4f;
  float targetT60 = constrain(baseReverbT60 + t60Delta * reverbBioModDepth, 0.5f, 4.0f);

  boolean needRegen = false;

  // Mitosis Burst Event -> Impulse Seed Re-trigger on significant biomass surges
  float burstThreshold = lastMitosisBiomassThreshold * (1.0f + 0.35f / max(0.5f, reverbBioModDepth));
  if (totalBiomass >= burstThreshold && totalBiomass > 2000.0f) {
    reverbSeed = System.nanoTime() ^ (long) totalBiomass;
    lastMitosisBiomassThreshold = totalBiomass;
    needRegen = true;
  }

  if (Math.abs(reverbHighDamping - targetDamp) > 0.06f) {
    reverbHighDamping = targetDamp;
    needRegen = true;
  }
  if (Math.abs(reverbPreDelay - targetPreDelay) > 0.008f) {
    reverbPreDelay = targetPreDelay;
    needRegen = true;
  }
  if (Math.abs(reverbT60 - targetT60) > 0.20f) {
    reverbT60 = targetT60;
    needRegen = true;
  }

  if (needRegen) {
    triggerIrRegenerationAsync();
  }

  syncReverbUiSliders();
}

// Biquad lowpass resonant digital filter with thread-safe atomic coefficient updates
class BiquadFilter {
  class Coeffs {
    final float b0, b1, b2, a1, a2;
    Coeffs(float b0, float b1, float b2, float a1, float a2) {
      this.b0 = b0; this.b1 = b1; this.b2 = b2; this.a1 = a1; this.a2 = a2;
    }
  }

  volatile Coeffs coeffs = new Coeffs(1.0f, 0.0f, 0.0f, 0.0f, 0.0f);
  float x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  void setLowPass(float cutoffHz, float q, float sampleRate) {
    float omega = TWO_PI * constrain(cutoffHz, 40.0f, sampleRate * 0.45f) / sampleRate;
    float alpha = sin(omega) / (2.0f * max(0.1f, q));
    float cosW = cos(omega);

    float a0 = 1.0f + alpha;
    float nb0 = ((1.0f - cosW) / 2.0f) / a0;
    float nb1 = (1.0f - cosW) / a0;
    float nb2 = ((1.0f - cosW) / 2.0f) / a0;
    float na1 = (-2.0f * cosW) / a0;
    float na2 = (1.0f - alpha) / a0;
    // Atomic reference assignment prevents torn filter coefficients between animation & audio threads
    coeffs = new Coeffs(nb0, nb1, nb2, na1, na2);
  }

  // Peaking EQ filter for pinna notch elevation modeling (boost/cut in dB)
  void setPeakNotch(float centerHz, float q, float gainDb, float sampleRate) {
    float A = (float) Math.pow(10.0, gainDb / 40.0);
    float omega = TWO_PI * constrain(centerHz, 40.0f, sampleRate * 0.45f) / sampleRate;
    float alpha = sin(omega) / (2.0f * max(0.1f, q));
    float cosW = cos(omega);

    float a0 = 1.0f + alpha / A;
    float nb0 = (1.0f + alpha * A) / a0;
    float nb1 = (-2.0f * cosW) / a0;
    float nb2 = (1.0f - alpha * A) / a0;
    float na1 = (-2.0f * cosW) / a0;
    float na2 = (1.0f - alpha / A) / a0;
    coeffs = new Coeffs(nb0, nb1, nb2, na1, na2);
  }

  // High-shelf filter for front/back pinna shadowing (gain in dB)
  void setHighShelf(float cutoffHz, float gainDb, float sampleRate) {
    float A = (float) Math.pow(10.0, gainDb / 40.0);
    float omega = TWO_PI * constrain(cutoffHz, 40.0f, sampleRate * 0.45f) / sampleRate;
    float cosW = cos(omega);
    float sinW = sin(omega);
    float alpha = sinW * 0.5f * sqrt(2.0f); // Q = 1/sqrt(2) Butterworth
    float twoSqrtAAlpha = 2.0f * sqrt(A) * alpha;

    float a0 = (A + 1.0f) - (A - 1.0f) * cosW + twoSqrtAAlpha;
    float nb0 = (A * ((A + 1.0f) + (A - 1.0f) * cosW + twoSqrtAAlpha)) / a0;
    float nb1 = (-2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosW)) / a0;
    float nb2 = (A * ((A + 1.0f) + (A - 1.0f) * cosW - twoSqrtAAlpha)) / a0;
    float na1 = (2.0f * ((A - 1.0f) - (A + 1.0f) * cosW)) / a0;
    float na2 = ((A + 1.0f) - (A - 1.0f) * cosW - twoSqrtAAlpha) / a0;
    coeffs = new Coeffs(nb0, nb1, nb2, na1, na2);
  }

  float process(float in) {
    return process(in, this.coeffs);
  }

  float process(float in, Coeffs c) {
    float out = c.b0 * in + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    if (Float.isNaN(out) || Float.isInfinite(out)) {
      out = 0.0f;
      x1 = 0; x2 = 0; y1 = 0; y2 = 0;
    } else {
      x2 = x1;
      x1 = in;
      y2 = y1;
      // Fast algebraic soft saturation prevents resonant blow-ups without slow Math.tanh
      if (out > 2.5f) {
        float d = (out - 2.5f) * 0.5f;
        out = 2.5f + (d / (1.0f + Math.abs(d)));
      } else if (out < -2.5f) {
        float d = (out + 2.5f) * 0.5f;
        out = -2.5f + (d / (1.0f + Math.abs(d)));
      }
      y1 = out;
    }
    return out;
  }
}

// Studio Master Dynamics Limiter (Compressor + Lookahead Brickwall Peak Limiter)
// Aligned with studio standards: Threshold -3dB, Ratio 4:1, Attack 5ms, Release 80ms
// True lookahead sliding-window peak limiter (Ceiling -1dB ~ 0.891, Lookahead 64 samples ~ 1.45ms)
class StudioMasterLimiter {
  private float compEnv = 0.0f;
  private final float compAtt;
  private final float compRel;
  private final float compThresh = 0.7071f; // -3 dBFS

  private final int LOOKAHEAD = 64;
  private final float[] delayL = new float[LOOKAHEAD];
  private final float[] delayR = new float[LOOKAHEAD];
  private final float[] peakHistory = new float[LOOKAHEAD];
  private int delayIdx = 0;
  private float limGain = 1.0f;
  private final float limCeiling = 0.891f; // -1 dBFS
  private final float limRel;
  private float maxAhead = 0.0f;

  StudioMasterLimiter(float sampleRate) {
    compAtt = (float) Math.exp(-1.0 / (0.005 * sampleRate)); // 5ms attack
    compRel = (float) Math.exp(-1.0 / (0.080 * sampleRate)); // 80ms release
    limRel  = (float) Math.exp(-1.0 / (0.060 * sampleRate)); // 60ms release
  }

  void process(float[] inL, float[] inR, float[] outL, float[] outR, int numSamples) {
    for (int i = 0; i < numSamples; i++) {
      float xL = inL[i];
      float xR = inR[i];
      float rawPeak = Math.max(Math.abs(xL), Math.abs(xR));

      // 1. Studio Compressor envelope follower
      if (rawPeak > compEnv) {
        compEnv = compAtt * compEnv + (1.0f - compAtt) * rawPeak;
      } else {
        compEnv = compRel * compEnv + (1.0f - compRel) * rawPeak;
      }

      // 4:1 compression above -3dB
      float compGain = 1.0f;
      if (compEnv > compThresh) {
        float r = compThresh / compEnv;
        compGain = (float) Math.sqrt(r * Math.sqrt(r));
      }

      float cL = xL * compGain;
      float cR = xR * compGain;
      float cPeak = Math.max(Math.abs(cL), Math.abs(cR));

      // Fast amortized O(1) sliding lookahead maximum over LOOKAHEAD samples
      float oldPeak = peakHistory[delayIdx];
      delayL[delayIdx] = cL;
      delayR[delayIdx] = cR;
      peakHistory[delayIdx] = cPeak;

      if (cPeak >= maxAhead) {
        maxAhead = cPeak;
      } else if (oldPeak >= maxAhead - 0.0001f) {
        maxAhead = cPeak;
        for (int k = 0; k < LOOKAHEAD; k++) {
          if (peakHistory[k] > maxAhead) maxAhead = peakHistory[k];
        }
      }

      float targetLimGain = 1.0f;
      if (maxAhead > limCeiling) {
        targetLimGain = limCeiling / maxAhead;
      }

      // Instant attack, smooth release
      if (targetLimGain < limGain) {
        limGain = targetLimGain;
      } else {
        limGain = limRel * limGain + (1.0f - limRel) * 1.0f;
      }

      // Read sample exiting the lookahead buffer (LOOKAHEAD is 64, power of 2)
      int readIdx = (delayIdx + 1) & (LOOKAHEAD - 1);
      float outSampleL = delayL[readIdx] * limGain;
      float outSampleR = delayR[readIdx] * limGain;

      delayIdx = readIdx;

      // Guaranteed brickwall bounds <= 0.92, zero distortion
      outL[i] = Math.max(-0.92f, Math.min(0.92f, outSampleL));
      outR[i] = Math.max(-0.92f, Math.min(0.92f, outSampleR));
    }
  }
}

// Multi-threaded stereo PCM audio engine with UP-OLA Velvet Convolver & Master Dynamics Limiter
class AudioEngine extends Thread {
  SourceDataLine line;
  PartitionedConvolver convolver;
  StudioMasterLimiter masterLimiter;
  volatile boolean running = true;
  final int SAMPLE_RATE = 44100;
  final int BUFFER_SAMPLES = 512;

  final Object lineLock = new Object();
  ArrayList<Mixer.Info> outputMixerInfos = new ArrayList<Mixer.Info>();
  String[] deviceNames = {"Default Audio Device"};
  int selectedDeviceIdx = 0; // 0 = Default, 1..N = specific mixers
  String currentDeviceName = "Default Audio Device";

  AudioFormat getAudioFormat() {
    return new AudioFormat(SAMPLE_RATE, 16, 2, true, false);
  }

  void scanAudioDevices() {
    outputMixerInfos.clear();
    ArrayList<String> names = new ArrayList<String>();
    names.add("Default Audio Device");

    AudioFormat fmt = getAudioFormat();
    DataLine.Info info = new DataLine.Info(SourceDataLine.class, fmt);

    try {
      for (Mixer.Info mInfo : AudioSystem.getMixerInfo()) {
        try {
          Mixer mixer = AudioSystem.getMixer(mInfo);
          if (mixer.isLineSupported(info)) {
            String mName = mInfo.getName();
            // Avoid duplicate default entries in the list
            if (!mName.equalsIgnoreCase("Default Audio Device")) {
              outputMixerInfos.add(mInfo);
              names.add(mName);
            }
          }
        } catch (Exception e) {}
      }
    } catch (Exception e) {
      println("Audio Device Scan Notice: " + e.getMessage());
    }

    deviceNames = names.toArray(new String[0]);
    if (selectedDeviceIdx >= deviceNames.length) {
      selectedDeviceIdx = 0;
    }
    currentDeviceName = deviceNames[selectedDeviceIdx];
  }

  boolean openAudioLine(int idx) {
    AudioFormat fmt = getAudioFormat();
    DataLine.Info info = new DataLine.Info(SourceDataLine.class, fmt);
    SourceDataLine newLine = null;

    try {
      if (idx <= 0 || idx > outputMixerInfos.size()) {
        newLine = (SourceDataLine) AudioSystem.getLine(info);
      } else {
        Mixer.Info mInfo = outputMixerInfos.get(idx - 1);
        Mixer mixer = AudioSystem.getMixer(mInfo);
        newLine = (SourceDataLine) mixer.getLine(info);
      }

      newLine.open(fmt, 32768); // ~185ms audio driver buffer headroom prevents under-runs
      newLine.start();

      SourceDataLine oldLine = null;
      synchronized (lineLock) {
        oldLine = line;
        line = newLine;
        selectedDeviceIdx = idx;
        currentDeviceName = (idx >= 0 && idx < deviceNames.length) ? deviceNames[idx] : "Default Audio Device";
      }

      if (oldLine != null) {
        try {
          oldLine.stop();
          oldLine.close();
        } catch (Exception e) {}
      }
      println("Audio output opened on: " + currentDeviceName);
      return true;
    } catch (Exception e) {
      println("Audio Device Open Error on [" + ((idx >= 0 && idx < deviceNames.length) ? deviceNames[idx] : idx) + "]: " + e.getMessage());
      if (newLine != null) {
        try { newLine.close(); } catch (Exception ex) {}
      }
      return false;
    }
  }

  void setAudioDevice(int idx) {
    if (idx == selectedDeviceIdx && line != null && line.isOpen()) return;
    boolean ok = openAudioLine(idx);
    if (!ok && idx != 0) {
      println("Falling back to Default Audio Device...");
      openAudioLine(0);
    }
  }

  public void run() {
    try {
      Thread.currentThread().setPriority(Thread.MAX_PRIORITY);

      convolver = new PartitionedConvolver(BUFFER_SAMPLES);
      masterLimiter = new StudioMasterLimiter(SAMPLE_RATE);
      VelvetImpulseGenerator.StereoIR ir = VelvetImpulseGenerator.generate(
        SAMPLE_RATE, reverbT60, 2000.0f, 10000.0f, reverbHighDamping, reverbPreDelay, reverbSeed
      );
      convolver.loadImpulseResponse(ir.left, ir.right);

      scanAudioDevices();
      openAudioLine(selectedDeviceIdx);

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
      float[] masterOutL = new float[BUFFER_SAMPLES];
      float[] masterOutR = new float[BUFFER_SAMPLES];

      while (running) {
        SourceDataLine currentLine;
        synchronized (lineLock) {
          currentLine = line;
        }

        if (currentLine == null || !currentLine.isOpen()) {
          try { Thread.sleep(10); } catch (Exception e) {}
          continue;
        }

        if (!audioEnabled || foodNodes.isEmpty()) {
          try {
            currentLine.write(silence, 0, silence.length);
          } catch (Exception e) {}
          try { Thread.sleep(8); } catch (Exception e) {}
          continue;
        }

        int wave = waveformIdx; // read once per buffer
        float voiceScale = computeVoiceScale();

        // Clear input block buffers
        for (int i = 0; i < BUFFER_SAMPLES; i++) {
          inL[i] = 0.0f;
          inR[i] = 0.0f;
        }

        // Render each active voice into stereo input buffer
        for (int v = 0; v < foodNodes.size(); v++) {
          FoodNodule fn;
          try {
            fn = foodNodes.get(v);
          } catch (IndexOutOfBoundsException e) { break; }
          
          if (fn.vcaGain >= 0.001f) {
            renderVoiceToBuffer(fn, inL, inR, voiceScale, wave, sineTable);
          }
        }

        // Real-Time UP-OLA Velvet Noise Convolver
        if (reverbEnabled && convolver != null && convolver.isLoaded()) {
          convolver.processBlock(inL, inR, outL, outR, reverbWet, reverbDry);
        } else {
          System.arraycopy(inL, 0, outL, 0, BUFFER_SAMPLES);
          System.arraycopy(inR, 0, outR, 0, BUFFER_SAMPLES);
        }

        // Master Dynamics Limiter (Studio Compressor + Lookahead Peak Limiter)
        masterLimiter.process(outL, outR, masterOutL, masterOutR, BUFFER_SAMPLES);
        encodePcmBytes(masterOutL, masterOutR, byteBuffer);

        try {
          currentLine.write(byteBuffer, 0, byteBuffer.length);
        } catch (Exception e) {}
      }
    } catch (Exception e) {
      println("Audio Engine Exception: " + e.getMessage());
    }
  }

  // Calculate voice scaling headroom: 1 / sqrt(N)
  float computeVoiceScale() {
    int activeVoices = 0;
    for (int v = 0; v < foodNodes.size(); v++) {
      try {
        FoodNodule fn = foodNodes.get(v);
        if (fn.vcaGain >= 0.001f) activeVoices++;
      } catch (IndexOutOfBoundsException e) { break; }
    }
    return (activeVoices > 0) ? (0.24f / (float) Math.sqrt(Math.max(1.0, activeVoices * 0.75))) : 0.24f;
  }

  // Render a single food nodule voice into the stereo block buffer
  void renderVoiceToBuffer(FoodNodule fn, float[] inL, float[] inR, float voiceScale, int wave, float[] sineTable) {
    float dx = spatialNormalizedDx(fn.x);
    float dy = spatialNormalizedDy(fn.y);

    float bShaped = spatialShapedBipolar(dx);
    float panNorm = constrain(0.5f + 0.5f * bShaped, 0.0f, 1.0f);

    // Constant-Power Panning Law: preserves uniform acoustic power (L^2 + R^2 = 1.0)
    float panAngle = panNorm * (float)(Math.PI * 0.5);
    float panL = (float) Math.cos(panAngle);
    float panR = (float) Math.sin(panAngle);

    // Distance attenuation (subtle acoustic roll-off towards grid corners)
    float distNorm = (float) Math.sqrt(dx * dx + dy * dy);
    float distGain = 1.0f / (1.0f + distNorm * 0.25f);

    float voiceGainL = fn.vcaGain * voiceScale * panL * distGain;
    float voiceGainR = fn.vcaGain * voiceScale * panR * distGain;
    float phaseInc = fn.frequency / SAMPLE_RATE;

    int itdDelay = (int) (Math.abs(bShaped) * 18.0f);
    boolean delayRight = (bShaped < 0.0f); // Source is on left -> right ear is delayed

    BiquadFilter.Coeffs cL = fn.filter.coeffs;
    BiquadFilter.Coeffs cR = fn.filterR.coeffs;
    BiquadFilter.Coeffs cElev = fn.pinnaElevationFilter.coeffs;
    BiquadFilter.Coeffs cFB = fn.frontBackFilter.coeffs;

    for (int i = 0; i < BUFFER_SAMPLES; i++) {
      float raw;
      switch (wave) {
        case 0: // Triangle
          raw = (fn.phase < 0.5f) ? (4.0f * fn.phase - 1.0f) : (3.0f - 4.0f * fn.phase);
          break;
        case 1: // Sine
          raw = sineTable[(int)(fn.phase * 4096f) & 4095];
          break;
        case 2: // Sawtooth
          raw = 2.0f * fn.phase - 1.0f;
          break;
        default: // Square
          raw = (fn.phase < 0.5f) ? 0.8f : -0.8f;
          break;
      }

      fn.phase += phaseInc;
      if (fn.phase >= 1.0f) fn.phase -= 1.0f;

      // 1. Slime mold biomass elevation notch filter (HRTF vertical pinna cue)
      float shapedSig = fn.pinnaElevationFilter.process(raw, cElev);

      // 2. Front vs Back pinna spectral tilt filter (high-shelf forward presence / rear shadow)
      shapedSig = fn.frontBackFilter.process(shapedSig, cFB);

      // 3. Stereo head-shadow biquad processing
      float sigL = fn.filter.process(shapedSig, cL);
      float sigR = fn.filterR.process(shapedSig, cR);

      // 4. Haas micro-delay for 3D binaural spatial depth
      if (itdDelay > 0) {
        int wIdx = fn.delayIdx;
        fn.delayBufL[wIdx] = sigL;
        fn.delayBufR[wIdx] = sigR;
        int rIdx = (wIdx - itdDelay + 32) & 31;
        fn.delayIdx = (wIdx + 1) & 31;

        if (delayRight) {
          sigR = fn.delayBufR[rIdx];
        } else {
          sigL = fn.delayBufL[rIdx];
        }
      }

      inL[i] += sigL * voiceGainL;
      inR[i] += sigR * voiceGainR;
    }
  }

  // Convert 32-bit float master bus to 16-bit signed little-endian PCM
  void encodePcmBytes(float[] masterOutL, float[] masterOutR, byte[] byteBuffer) {
    for (int i = 0; i < BUFFER_SAMPLES; i++) {
      short pcmL = (short) (masterOutL[i] * 32760.0f);
      short pcmR = (short) (masterOutR[i] * 32760.0f);

      int bIdx = i * 4;
      byteBuffer[bIdx]     = (byte) (pcmL & 0xFF);
      byteBuffer[bIdx + 1] = (byte) ((pcmL >> 8) & 0xFF);
      byteBuffer[bIdx + 2] = (byte) (pcmR & 0xFF);
      byteBuffer[bIdx + 3] = (byte) ((pcmR >> 8) & 0xFF);
    }
  }

  void closeEngine() {
    running = false;
    synchronized (lineLock) {
      if (line != null) {
        try {
          line.stop();
          line.close();
        } catch (Exception e) {}
        line = null;
      }
    }
  }
}
