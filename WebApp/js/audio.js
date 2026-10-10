
    // --- STREAMING_CHUNK:Building Voice, VCA, and Filter DSP logic for Food Nodes ---
    // Food Audio Voice: True 3D Binaural Spatialization, Pinna Spectral Notch, Head Shadow Filter & Bell Modal Synthesizer
    class FoodAudioVoice {
      constructor(food) {
        this.food = food;
        this.bellAmps = new Float32Array(6);
        this.partialOscs = [];
        this.partialGains = [];
        this.osc = null;

        if (audioCtx) {
          this.initAudioNodes();
        }

        if (CONFIG.bellAcousticsMode && CONFIG.bellStrikeIntensity > 0) {
          this.strike(0.6 * CONFIG.bellStrikeIntensity);
        }
      }

      initAudioNodes() {
        if (!audioCtx || this.osc) return;

        this.pinnaNotch = audioCtx.createBiquadFilter();
        this.frontBackShelf = audioCtx.createBiquadFilter();
        this.filterL = audioCtx.createBiquadFilter();
        this.filterR = audioCtx.createBiquadFilter();
        this.delayL = audioCtx.createDelay(0.005);
        this.delayR = audioCtx.createDelay(0.005);
        this.gainL = audioCtx.createGain();
        this.gainR = audioCtx.createGain();
        this.merger = audioCtx.createChannelMerger(2);

        this.voiceSum = audioCtx.createGain();
        this.voiceSum.gain.setValueAtTime(1.0, audioCtx.currentTime);

        const baseF = getCellFrequency(this.food.gridCol, this.food.gridRow);
        this.partialOscs = [];
        this.partialGains = [];

        for (let p = 0; p < 6; p++) {
          const osc = audioCtx.createOscillator();
          const g = audioCtx.createGain();
          osc.type = (p === 1 && !CONFIG.bellAcousticsMode) ? CONFIG.waveform : 'sine';
          osc.frequency.setValueAtTime(baseF * BELL_RATIOS[p], audioCtx.currentTime);
          g.gain.setValueAtTime(0.0, audioCtx.currentTime);
          osc.connect(g);
          g.connect(this.voiceSum);
          try { osc.start(); } catch(e) {}
          this.partialOscs.push(osc);
          this.partialGains.push(g);
        }

        // Backward compatibility reference for legacy properties
        this.osc = this.partialOscs[1];

        // Pinna Notch (Z-Elevation): Peaking / Notch filter sweeping 6.2kHz - 9.2kHz
        this.pinnaNotch.type = 'peaking';
        this.pinnaNotch.frequency.setValueAtTime(6200, audioCtx.currentTime);
        this.pinnaNotch.Q.setValueAtTime(2.5, audioCtx.currentTime);
        this.pinnaNotch.gain.setValueAtTime(-4.0, audioCtx.currentTime);

        // Front vs Back Pinna High-Shelf (4.0kHz)
        this.frontBackShelf.type = 'highshelf';
        this.frontBackShelf.frequency.setValueAtTime(4000, audioCtx.currentTime);
        this.frontBackShelf.gain.setValueAtTime(0.0, audioCtx.currentTime);

        // L/R LowPass filters
        this.filterL.type = 'lowpass';
        this.filterR.type = 'lowpass';
        this.filterL.Q.setValueAtTime(CONFIG.lpfQ, audioCtx.currentTime);
        this.filterR.Q.setValueAtTime(CONFIG.lpfQ, audioCtx.currentTime);
        this.filterL.frequency.setValueAtTime(80, audioCtx.currentTime);
        this.filterR.frequency.setValueAtTime(80, audioCtx.currentTime);

        this.delayL.delayTime.setValueAtTime(0.0, audioCtx.currentTime);
        this.delayR.delayTime.setValueAtTime(0.0, audioCtx.currentTime);

        this.gainL.gain.setValueAtTime(0.0, audioCtx.currentTime);
        this.gainR.gain.setValueAtTime(0.0, audioCtx.currentTime);

        // Signal Chain:
        // voiceSum -> pinnaNotch -> frontBackShelf -> filterL/R -> delayL/R -> gainL/R -> merger -> master/reverb
        this.voiceSum.connect(this.pinnaNotch);
        this.pinnaNotch.connect(this.frontBackShelf);

        this.frontBackShelf.connect(this.filterL);
        this.frontBackShelf.connect(this.filterR);

        this.filterL.connect(this.delayL);
        this.filterR.connect(this.delayR);

        this.delayL.connect(this.gainL);
        this.delayR.connect(this.gainR);

        this.gainL.connect(this.merger, 0, 0); // Merges into Left (ch 0)
        this.gainR.connect(this.merger, 0, 1); // Merges into Right (ch 1)

        if (reverbDryGain) this.merger.connect(reverbDryGain);
        if (reverbConvolver) this.merger.connect(reverbConvolver);
      }

      strike(velocity) {
        if (!this.bellAmps || velocity <= 0) return;
        for (let p = 0; p < 6; p++) {
          const sAmp = BELL_STRIKE_AMPS[p] * velocity;
          if (sAmp > this.bellAmps[p]) {
            this.bellAmps[p] = sAmp;
          }
        }
      }

      getTotalBellEnergy() {
        if (!this.bellAmps) return 0.0;
        let sum = 0.0;
        for (let p = 0; p < 6; p++) sum += this.bellAmps[p];
        return sum;
      }

      update(adjacentMass, isFeeding) {
        // Physical and spatial simulation properties (always update for visual and lifecycle parity)
        const effectiveMass = Math.max(0.0, adjacentMass - (CONFIG.vcaGateThreshold || 120.0));
        const drive = (effectiveMass * CONFIG.vcaSens * 1.25) / 1000.0;
        const targetVca = (isFeeding || this.food.consumptionActivity > 0.05) ? Math.tanh(drive) : 0.0;
        this.food.vcaGain += (targetVca - this.food.vcaGain) * 0.15;

        const targetActivity = isFeeding ? 1.0 : 0.0;
        this.food.consumptionActivity += (targetActivity - this.food.consumptionActivity) * 0.12;

        const targetElev = Math.min(1.0, Math.max(0.0, adjacentMass / 800.0));
        this.food.elevationNorm += (targetElev - this.food.elevationNorm) * 0.12;

        const baseF = getCellFrequency(this.food.gridCol, this.food.gridRow);
        const massRatio = Math.max(0.0, this.food.mass / this.food.initialMass);
        const sustainDrive = (isFeeding && !this.food.isDepleted) ? (this.food.vcaGain * CONFIG.bellSustainLevel * (0.5 + 0.5 * massRatio)) : 0.0;
        const dt = 1.0 / 60.0; // rAF step time

        // Multi-modal bell acoustics decay & sustain calculations
        if (this.bellAmps) {
          for (let p = 0; p < 6; p++) {
            const f_p = baseF * BELL_RATIOS[p];
            if (CONFIG.bellAcousticsMode) {
              const tau_p = Math.min(15.0, Math.max(0.05, (CONFIG.bellQ * BELL_Q_MULTS[p]) / (Math.PI * Math.max(20.0, f_p))));
              const decayFactor = Math.exp(-dt / tau_p);
              const targetS = BELL_SUSTAIN_WEIGHTS[p] * sustainDrive;
              let curAmp = this.bellAmps[p];
              let endAmp;
              if (curAmp < targetS) {
                endAmp = curAmp + (targetS - curAmp) * 0.18;
              } else {
                endAmp = targetS + (curAmp - targetS) * decayFactor;
              }
              if (endAmp < 0.0001) endAmp = 0.0;
              this.bellAmps[p] = endAmp;
            }
          }
        }

        // Web Audio DSP processing (only when audio engine is running and nodes are created)
        if (!audioCtx || !this.osc) return;
        const now = audioCtx.currentTime;

        // 1. Normalized Cartesian 3D coordinates relative to center (worldDim/2)
        const halfDim = CONFIG.worldDim * 0.5;
        const dx = Math.min(1.0, Math.max(-1.0, (this.food.x - halfDim) / halfDim));
        const dy = Math.min(1.0, Math.max(-1.0, (halfDim - this.food.y) / halfDim));

        // 2. Lateral Pan with shaped curve (dx^1.35) and Constant-Power Law
        const sign = (dx < 0.0) ? -1.0 : 1.0;
        const bShaped = sign * Math.pow(Math.abs(dx), 1.35);
        const panNorm = Math.min(1.0, Math.max(0.0, 0.5 + 0.5 * bShaped));
        const panAngle = panNorm * (Math.PI * 0.5);
        const panL = Math.cos(panAngle);
        const panR = Math.sin(panAngle);

        // Distance attenuation
        const distNorm = Math.sqrt(dx * dx + dy * dy);
        const distGain = 1.0 / (1.0 + distNorm * 0.25);

        // Multi-voice headroom scale: 0.24 / sqrt(max(1, 0.75 * N))
        const activeCount = Math.max(1, foodSources.length);
        const voiceHeadroom = 0.24 / Math.sqrt(Math.max(1.0, activeCount * 0.75));

        // 3. Dynamic Filter Cutoff: sweeps down as food is consumed
        const baseCutoff = 80.0 + (massRatio * 3120.0 * (CONFIG.lpfSens / 3.0));
        const cutoffL = Math.min(18000.0, Math.max(40.0, baseCutoff * (1.0 - dx * 0.18)));
        const cutoffR = Math.min(18000.0, Math.max(40.0, baseCutoff * (1.0 + dx * 0.18)));

        this.filterL.frequency.setTargetAtTime(cutoffL, now, 0.04);
        this.filterR.frequency.setTargetAtTime(cutoffR, now, 0.04);
        this.filterL.Q.setTargetAtTime(CONFIG.lpfQ, now, 0.04);
        this.filterR.Q.setTargetAtTime(CONFIG.lpfQ, now, 0.04);

        // 4. Pinna Front/Back Shadowing (+1.5dB front, -4.5dB rear)
        const fbGainDb = (dy >= 0.0) ? (dy * 1.5) : (dy * 4.5);
        this.frontBackShelf.gain.setTargetAtTime(fbGainDb, now, 0.05);

        // 5. 3D Biomass Elevation notch filter (6.2kHz - 9.2kHz, -4dB -> -8dB)
        const notchFreq = 6200.0 + this.food.elevationNorm * 3000.0;
        const notchDepthDb = -4.0 - this.food.elevationNorm * 4.0;
        this.pinnaNotch.frequency.setTargetAtTime(notchFreq, now, 0.05);
        this.pinnaNotch.gain.setTargetAtTime(notchDepthDb, now, 0.05);

        // 6. Haas Micro-Delay (ITD up to 18 samples @ 44.1kHz = ~0.4ms)
        const sr = audioCtx.sampleRate || 44100;
        const itdDelaySec = (Math.abs(bShaped) * 18.0) / sr;
        if (bShaped < 0.0) {
          // Source on left -> right ear is delayed
          this.delayL.delayTime.setTargetAtTime(0.0, now, 0.02);
          this.delayR.delayTime.setTargetAtTime(itdDelaySec, now, 0.02);
        } else {
          // Source on right -> left ear is delayed
          this.delayL.delayTime.setTargetAtTime(itdDelaySec, now, 0.02);
          this.delayR.delayTime.setTargetAtTime(0.0, now, 0.02);
        }

        // Apply oscillator frequencies and modal gains
        for (let p = 0; p < 6; p++) {
          const f_p = baseF * BELL_RATIOS[p];
          if (this.partialOscs[p]) {
            this.partialOscs[p].frequency.setTargetAtTime(f_p, now, 0.03);
          }
          if (CONFIG.bellAcousticsMode) {
            if (this.partialGains[p]) {
              this.partialGains[p].gain.setTargetAtTime(this.bellAmps[p] * 0.35, now, 0.02);
            }
          } else {
            if (this.partialGains[p]) {
              this.partialGains[p].gain.setTargetAtTime(p === 1 ? 1.0 : 0.0, now, 0.02);
            }
          }
        }

        const voiceAmp = CONFIG.bellAcousticsMode ? 1.0 : this.food.vcaGain;
        const voiceGainTotal = voiceAmp * voiceHeadroom * distGain;
        this.gainL.gain.setTargetAtTime(voiceGainTotal * panL, now, 0.04);
        this.gainR.gain.setTargetAtTime(voiceGainTotal * panR, now, 0.04);
      }

      destroy() {
        if (!audioCtx) return;
        const now = audioCtx.currentTime;
        try {
          if (this.gainL) this.gainL.gain.setTargetAtTime(0, now, 0.04);
          if (this.gainR) this.gainR.gain.setTargetAtTime(0, now, 0.04);
          setTimeout(() => {
            if (this.partialOscs) {
              for (let p = 0; p < this.partialOscs.length; p++) {
                try {
                  this.partialOscs[p].stop();
                  this.partialOscs[p].disconnect();
                } catch(e) {}
              }
            }
          }, 60);
        } catch (e) {}
      }
    }


    function updateReverbRouting() {
      if (!audioCtx || !reverbDryGain || !reverbWetGain) return;
      reverbDryGain.gain.setTargetAtTime(CONFIG.reverbDry, audioCtx.currentTime, 0.05);
      reverbWetGain.gain.setTargetAtTime(CONFIG.reverbEnabled ? CONFIG.reverbWet : 0, audioCtx.currentTime, 0.05);
    }

    // Algorithmic Velvet Noise Impulse Response Generator (Direct port of VelvetImpulseGenerator.java)
    function generateReverbIR() {
      if (!audioCtx || !reverbConvolver) return;
      const sr = audioCtx.sampleRate || 44100;
      const t60 = Math.max(0.05, CONFIG.reverbT60);
      const d0 = 2000.0;
      const dMax = 10000.0;
      const highDamping = Math.min(0.95, Math.max(0.05, CONFIG.reverbHighDamping));
      const preDelaySeconds = Math.max(0, CONFIG.reverbPreDelay);
      const seed = (CONFIG.reverbSeed !== undefined) ? (CONFIG.reverbSeed >>> 0) : 1337;

      const totalSamples = Math.max(1, Math.floor(sr * t60));
      const preDelaySamples = Math.max(0, Math.floor(sr * preDelaySeconds));
      const totalLength = totalSamples + preDelaySamples;

      const buffer = audioCtx.createBuffer(2, totalLength, sr);
      const irL = buffer.getChannelData(0);
      const irR = buffer.getChannelData(1);

      // Simple fast Mulberry32 PRNG for predictable, decorrelated stereo seeds
      function createRng(s) {
        let state = (s >>> 0);
        return function() {
          state = (state + 0x6D2B79F5) >>> 0;
          let t = Math.imul(state ^ (state >>> 15), 1 | state);
          t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
          return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
      }

      function generateChannel(buf, rng) {
        const rawPulses = new Float32Array(totalSamples);
        let currSample = 0;
        while (currSample < totalSamples) {
          const normT = Math.min(1.0, Math.max(0.0, currSample / (sr * t60)));
          const d = d0 + (dMax - d0) * Math.sqrt(normT);
          const td = Math.max(1, Math.round(sr / d));
          const jitter = (td > 1) ? Math.floor(rng() * (td - 1)) : 0;
          const pulsePos = currSample + jitter;
          const sign = rng() > 0.5 ? 1.0 : -1.0;
          if (pulsePos < totalSamples) {
            rawPulses[pulsePos] = sign;
          }
          currSample += td;
        }

        const tAttack = Math.min(0.010, t60 * 0.1);
        const nAttack = Math.max(1, Math.floor(sr * tAttack));
        const sigma = nAttack / 3.0;
        const twoSigmaSq = 2.0 * sigma * sigma;

        for (let n = 0; n < totalSamples; n++) {
          if (rawPulses[n] === 0.0) continue;
          let decayEnv = Math.exp(-6.907755 * n / (sr * t60));
          if (n < nAttack) {
            const diff = n - nAttack;
            decayEnv *= Math.exp(-(diff * diff) / twoSigmaSq);
          }
          rawPulses[n] *= decayEnv;
        }

        const alphaBase = 0.05;
        const alphaMax = highDamping;
        let yPrev = 0.0;
        for (let n = 0; n < totalSamples; n++) {
          const alpha = alphaBase + (alphaMax - alphaBase) * (n / totalSamples);
          const y = (1.0 - alpha) * rawPulses[n] + alpha * yPrev;
          yPrev = y;
          buf[preDelaySamples + n] = y;
        }
      }

      generateChannel(irL, createRng(seed));
      generateChannel(irR, createRng((seed ^ 0x5DEECE66) >>> 0));

      // L2 Normalization to -3dBFS
      let sumSq = 0.0;
      for (let i = 0; i < totalLength; i++) {
        sumSq += irL[i] * irL[i] + irR[i] * irR[i];
      }
      const l2Norm = Math.sqrt(sumSq * 0.5);
      if (l2Norm > 1e-7) {
        const normScale = 0.70710678 / l2Norm;
        for (let i = 0; i < totalLength; i++) {
          irL[i] *= normScale;
          irR[i] *= normScale;
        }
      }

      try {
        reverbConvolver.buffer = buffer;
      } catch (err) {
        console.warn("Could not set convolver buffer:", err);
      }
    }

    // Dynamic Bio-Sonification Telemetry (Direct port of updateReverbBioTelemetry)
    let lastIrRegenTime = 0;
    function triggerIrRegenDebounced() {
      const now = performance.now();
      if (now - lastIrRegenTime < 250) return;
      lastIrRegenTime = now;
      generateReverbIR();
    }

    function syncReverbUiSliders() {
      const elWet = document.getElementById('slider-rev-wet');
      const elDry = document.getElementById('slider-rev-dry');
      const elT60 = document.getElementById('slider-rev-t60');
      const elDamp = document.getElementById('slider-rev-damp');
      const elPre = document.getElementById('slider-rev-pre');
      if (elWet && document.activeElement !== elWet) { elWet.value = CONFIG.reverbWet; document.getElementById('lbl-rev-wet').innerText = CONFIG.reverbWet.toFixed(2); }
      if (elDry && document.activeElement !== elDry) { elDry.value = CONFIG.reverbDry; document.getElementById('lbl-rev-dry').innerText = CONFIG.reverbDry.toFixed(2); }
      if (elT60 && document.activeElement !== elT60) { elT60.value = CONFIG.reverbT60; document.getElementById('lbl-rev-t60').innerText = CONFIG.reverbT60.toFixed(1) + 's'; }
      if (elDamp && document.activeElement !== elDamp) { elDamp.value = CONFIG.reverbHighDamping; document.getElementById('lbl-rev-damp').innerText = CONFIG.reverbHighDamping.toFixed(2); }
      if (elPre && document.activeElement !== elPre) { elPre.value = CONFIG.reverbPreDelay; document.getElementById('lbl-rev-pre').innerText = CONFIG.reverbPreDelay.toFixed(3) + 's'; }
    }

    function computePetriDispersion() {
      let maxDistFromCenter = 0.0;
      let occupiedCells = 0;
      for (let i = 0; i < 64; i++) {
        if (cellBiomass[i] > 25.0) {
          occupiedCells++;
          const c = i % CONFIG.gridDim;
          const r = Math.floor(i / CONFIG.gridDim);
          const dx = (c + 0.5) - 3.5;
          const dy = (r + 0.5) - 3.5;
          const distFromCenter = Math.sqrt(dx * dx + dy * dy) / 4.95;
          if (distFromCenter > maxDistFromCenter) maxDistFromCenter = distFromCenter;
        }
      }
      const colonySpread = Math.min(1.0, Math.max(0.0, maxDistFromCenter));
      const spreadRatio = Math.min(2.0, Math.max(0.0, occupiedCells / 32.0));
      return [colonySpread, spreadRatio];
    }

    function computeFeedingRatio() {
      let totalFeeding = 0.0;
      let activeFoodCount = 0;
      for (let f = 0; f < foodSources.length; f++) {
        const fn = foodSources[f];
        activeFoodCount++;
        if (fn.isFeeding || fn.consumptionActivity > 0.05) totalFeeding += fn.consumptionActivity;
      }
      return (activeFoodCount > 0) ? Math.min(1.0, Math.max(0.0, totalFeeding / activeFoodCount)) : 0.0;
    }

    function updateReverbBioTelemetry() {
      if (!CONFIG.autoModulateReverb) return;
      if (CONFIG.reverbBioModDepth <= 0.001) {
        CONFIG.reverbWet = CONFIG.baseReverbWet;
        CONFIG.reverbDry = CONFIG.baseReverbDry;
        CONFIG.reverbT60 = CONFIG.baseReverbT60;
        CONFIG.reverbHighDamping = CONFIG.baseReverbHighDamping;
        CONFIG.reverbPreDelay = CONFIG.baseReverbPreDelay;
        syncReverbUiSliders();
        updateReverbRouting();
        return;
      }

      let totalBiomass = 0.0;
      for (let i = 0; i < 64; i++) totalBiomass += cellBiomass[i];

      const nominalBiomass = Math.max(1000.0, CONFIG.targetAgentCount * 50.0);
      const massRatio = totalBiomass / nominalBiomass;
      const massDelta = massRatio - 1.0;

      const [colonySpread, spreadRatio] = computePetriDispersion();
      const feedingRatio = computeFeedingRatio();

      const locoFactor = Math.min(3.0, Math.max(0.2, CONFIG.locomotionCost / 0.018));
      const sensorFactor = Math.min(3.0, Math.max(0.2, CONFIG.sensorDist / 40.0));

      const wetDelta = massDelta * 0.20 + (colonySpread - 0.4) * 0.15 + feedingRatio * 0.15;
      const targetWet = Math.min(1.0, Math.max(0.0, CONFIG.baseReverbWet + wetDelta * CONFIG.reverbBioModDepth));
      const targetDry = Math.min(1.0, Math.max(0.05, CONFIG.baseReverbDry - (wetDelta * 0.75) * CONFIG.reverbBioModDepth));

      CONFIG.reverbWet += (targetWet - CONFIG.reverbWet) * 0.12;
      CONFIG.reverbDry += (targetDry - CONFIG.reverbDry) * 0.12;

      const dampDelta = feedingRatio * 0.16 + (spreadRatio - 0.5) * 0.12 - (locoFactor - 1.0) * 0.10;
      const targetDamp = Math.min(0.95, Math.max(0.05, CONFIG.baseReverbHighDamping + dampDelta * CONFIG.reverbBioModDepth));

      const preDelta = (colonySpread - 0.3) * 0.015 + (sensorFactor - 1.0) * 0.010;
      const targetPreDelay = Math.min(0.060, Math.max(0.005, CONFIG.baseReverbPreDelay + preDelta * CONFIG.reverbBioModDepth));

      const t60Delta = massDelta * 0.7 + (colonySpread - 0.4) * 0.5 + feedingRatio * 0.4;
      const targetT60 = Math.min(4.0, Math.max(0.5, CONFIG.baseReverbT60 + t60Delta * CONFIG.reverbBioModDepth));

      let needRegen = false;
      const burstThreshold = CONFIG.lastMitosisBiomassThreshold * (1.0 + 0.35 / Math.max(0.5, CONFIG.reverbBioModDepth));
      if (totalBiomass >= burstThreshold && totalBiomass > 2000.0) {
        CONFIG.reverbSeed = (Date.now() ^ Math.floor(totalBiomass)) >>> 0;
        CONFIG.lastMitosisBiomassThreshold = totalBiomass;
        needRegen = true;
      }

      if (Math.abs(CONFIG.reverbHighDamping - targetDamp) > 0.06) {
        CONFIG.reverbHighDamping = targetDamp;
        needRegen = true;
      }
      if (Math.abs(CONFIG.reverbPreDelay - targetPreDelay) > 0.008) {
        CONFIG.reverbPreDelay = targetPreDelay;
        needRegen = true;
      }
      if (Math.abs(CONFIG.reverbT60 - targetT60) > 0.20) {
        CONFIG.reverbT60 = targetT60;
        needRegen = true;
      }

      if (needRegen) triggerIrRegenDebounced();
      updateReverbRouting();
      syncReverbUiSliders();
    }

    // Connect voices to reverb split instead of directly to masterGain

    function toggleAudioEngine() {
      if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        masterGain = audioCtx.createGain();
        masterGain.gain.setValueAtTime(0.8, audioCtx.currentTime);
        
        // Studio Master Dynamics Limiter (Compressor aligned with Processing updates)
        const compressor = audioCtx.createDynamicsCompressor();
        compressor.threshold.setValueAtTime(-3, audioCtx.currentTime);
        compressor.ratio.setValueAtTime(4, audioCtx.currentTime);
        compressor.attack.setValueAtTime(0.005, audioCtx.currentTime);
        compressor.release.setValueAtTime(0.080, audioCtx.currentTime);

        masterGain.connect(compressor);
        compressor.connect(audioCtx.destination);
        
        // Reverb Network
        reverbConvolver = audioCtx.createConvolver();
        reverbWetGain = audioCtx.createGain();
        reverbDryGain = audioCtx.createGain();
        reverbDryGain.gain.setValueAtTime(CONFIG.reverbDry, audioCtx.currentTime);
        reverbWetGain.gain.setValueAtTime(CONFIG.reverbEnabled ? CONFIG.reverbWet : 0, audioCtx.currentTime);
        
        reverbConvolver.connect(reverbWetGain);
        reverbWetGain.connect(masterGain);
        reverbDryGain.connect(masterGain);
        
        generateReverbIR();

      }
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      isAudioActive = !isAudioActive;
      const btn = document.getElementById('btn-audio-toggle');
      
      if (isAudioActive) {
        masterGain.gain.setTargetAtTime(0.8, audioCtx.currentTime, 0.05);
        btn.innerText = 'Audio: ON';
        btn.className = 'py-2 rounded bg-emerald-900/50 hover:bg-emerald-800/70 text-emerald-300 font-semibold border border-emerald-700/60 transition-colors';
        // Revive voices for existing food
        foodSources.forEach(f => {
          if (!f.voice) {
            f.voice = new FoodAudioVoice(f);
          } else if (!f.voice.osc) {
            f.voice.initAudioNodes();
          }
        });
      } else {
        btn.innerText = 'Audio: OFF';
        btn.className = 'py-2 rounded bg-amber-900/40 hover:bg-amber-800/60 text-amber-300 font-semibold border border-amber-700/50 transition-colors';
        masterGain.gain.setTargetAtTime(0.0, audioCtx.currentTime, 0.05);
      }
    }

    function retuneAllNodules() {
      foodSources.forEach(f => {
        if (f.voice && f.voice.osc && audioCtx) {
          const baseF = getCellFrequency(f.gridCol, f.gridRow);
          for (let p = 0; p < 6; p++) {
            if (f.voice.partialOscs && f.voice.partialOscs[p]) {
              f.voice.partialOscs[p].frequency.setTargetAtTime(baseF * BELL_RATIOS[p], audioCtx.currentTime, 0.05);
            }
          }
        }
      });
    }