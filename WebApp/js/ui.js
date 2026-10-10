
    // --- UI Accoridion Logic ---
    function handleAccordionToggle(buttonElement) {
      const content = buttonElement.nextElementSibling;
      const arrow = buttonElement.querySelector('.accordion-icon');
      const isOpen = content.classList.contains('expanded');

      // Close all
      document.querySelectorAll('.accordion-content').forEach(c => c.classList.remove('expanded'));
      document.querySelectorAll('.accordion-icon').forEach(a => a.style.transform = 'rotate(0deg)');

      // Open target
      if (!isOpen) {
        content.classList.add('expanded');
        arrow.style.transform = 'rotate(180deg)';
      }
    }


    document.getElementById('btn-audio-toggle').addEventListener('click', toggleAudioEngine);

    document.getElementById('btn-engine-toggle').addEventListener('click', () => {
      isRunning = !isRunning;
      document.getElementById('btn-engine-toggle').innerText = isRunning ? 'Pause' : 'Resume';
    });

    document.getElementById('btn-clear-food').addEventListener('click', () => {
      foodSources.forEach(f => f.destroy());
      foodSources = [];
    });

    document.getElementById('btn-seed-food').addEventListener('click', () => {
      for (let i = 0; i < 4; i++) {
        const c = Math.floor(Math.random() * 8);
        const r = Math.floor(Math.random() * 8);
        spawnNoduleInGrid(c, r);
      }
    });


    document.getElementById('slider-agents').addEventListener('input', (e) => {
      CONFIG.targetAgentCount = parseInt(e.target.value);
      document.getElementById('lbl-agents').innerText = CONFIG.targetAgentCount;
    });

    document.getElementById('btn-reinoculate').addEventListener('click', () => {
      // Reinoculate colony (Keep food nodules, reset colony & trail field)
      trailMap.fill(0);
      nextTrailMap.fill(0);
      cellBiomass.fill(0);
      agents = [];
      const cx = CONFIG.worldDim / 2;
      const cy = CONFIG.worldDim / 2;
      for (let i = 0; i < CONFIG.targetAgentCount; i++) {
        const th = Math.random() * Math.PI * 2;
        const r = Math.random() * 8;
        agents.push(new Agent(cx + Math.cos(th) * r, cy + Math.sin(th) * r, Math.random() * Math.PI * 2));
      }
      foodSources.forEach(f => {
        f.grazingBuffer = 0;
        f.isFeeding = false;
        f.vcaGain = 0;
        f.elevationNorm = 0;
      });
      CONFIG.lastMitosisBiomassThreshold = 8000.0;
      CONFIG.reverbSeed = Date.now() >>> 0;
      generateReverbIR(); // Reset IR just like Processing
    });

    document.getElementById('btn-fullscreen').addEventListener('click', () => {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(err => {
          console.log(`Error attempting to enable fullscreen: ${err.message}`);
        });
      } else {
        document.exitFullscreen();
      }
    });

    document.getElementById('chk-reverb-active').addEventListener('change', (e) => {
      CONFIG.reverbEnabled = e.target.checked;
      updateReverbRouting();
    });

    document.getElementById('chk-biomod-active').addEventListener('change', (e) => {
      CONFIG.autoModulateReverb = e.target.checked;
    });

    document.getElementById('slider-rev-wet').addEventListener('input', (e) => {
      CONFIG.reverbWet = parseFloat(e.target.value);
      document.getElementById('lbl-rev-wet').innerText = CONFIG.reverbWet.toFixed(2);
      updateReverbRouting();
    });

    document.getElementById('slider-rev-dry').addEventListener('input', (e) => {
      CONFIG.reverbDry = parseFloat(e.target.value);
      document.getElementById('lbl-rev-dry').innerText = CONFIG.reverbDry.toFixed(2);
      updateReverbRouting();
    });

    document.getElementById('slider-rev-t60').addEventListener('input', (e) => {
      CONFIG.reverbT60 = parseFloat(e.target.value);
      document.getElementById('lbl-rev-t60').innerText = CONFIG.reverbT60.toFixed(1) + 's';
      generateReverbIR();
    });

    document.getElementById('slider-rev-damp').addEventListener('input', (e) => {
      CONFIG.reverbHighDamping = parseFloat(e.target.value);
      document.getElementById('lbl-rev-damp').innerText = CONFIG.reverbHighDamping.toFixed(2);
      generateReverbIR();
    });

    document.getElementById('slider-rev-pre').addEventListener('input', (e) => {
      CONFIG.reverbPreDelay = parseFloat(e.target.value);
      document.getElementById('lbl-rev-pre').innerText = CONFIG.reverbPreDelay.toFixed(3) + 's';
      generateReverbIR();
    });

    document.getElementById('btn-regen-ir').addEventListener('click', () => {
      CONFIG.reverbSeed = Date.now() >>> 0;
      generateReverbIR();
    });

    document.getElementById('slider-biomod-depth').addEventListener('input', (e) => {
      CONFIG.reverbBioModDepth = parseFloat(e.target.value);
      document.getElementById('lbl-biomod-depth').innerText = `${CONFIG.reverbBioModDepth.toFixed(1)}x`;
    });

    document.getElementById('slider-led-thresh').addEventListener('input', (e) => {
      CONFIG.ledMassThreshold = parseFloat(e.target.value);
      document.getElementById('lbl-led-thresh').innerText = Math.round(CONFIG.ledMassThreshold);
      resetPadDirtyCaches();
    });

    document.getElementById('slider-ripple-width').addEventListener('input', (e) => {
      CONFIG.lpRippleWidth = parseFloat(e.target.value);
      document.getElementById('lbl-ripple-width').innerText = `${CONFIG.lpRippleWidth.toFixed(1)} px`;
    });

    document.getElementById('btn-lp-slime').addEventListener('click', () => {
      CONFIG.lpShowSlime = !CONFIG.lpShowSlime;
      const btn = document.getElementById('btn-lp-slime');
      btn.innerText = CONFIG.lpShowSlime ? 'MOLD ON' : 'MOLD OFF';
      btn.className = CONFIG.lpShowSlime ? 'py-1 rounded bg-yellow-950 text-yellow-300 border border-yellow-700 font-mono text-[10px] transition-colors' : 'py-1 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 font-mono text-[10px] transition-colors';
      resetPadDirtyCaches();
      syncLpSideLeds();
    });

    document.getElementById('btn-lp-food').addEventListener('click', () => {
      CONFIG.lpShowFood = !CONFIG.lpShowFood;
      const btn = document.getElementById('btn-lp-food');
      btn.innerText = CONFIG.lpShowFood ? 'FOOD ON' : 'FOOD OFF';
      btn.className = CONFIG.lpShowFood ? 'py-1 rounded bg-cyan-950 text-cyan-300 border border-cyan-700 font-mono text-[10px] transition-colors' : 'py-1 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 font-mono text-[10px] transition-colors';
      resetPadDirtyCaches();
      syncLpSideLeds();
    });

    document.getElementById('btn-lp-eat').addEventListener('click', () => {
      CONFIG.lpShowEating = !CONFIG.lpShowEating;
      const btn = document.getElementById('btn-lp-eat');
      btn.innerText = CONFIG.lpShowEating ? 'EAT ON' : 'EAT OFF';
      btn.className = CONFIG.lpShowEating ? 'py-1 rounded bg-fuchsia-950 text-fuchsia-300 border border-fuchsia-700 font-mono text-[10px] transition-colors' : 'py-1 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 font-mono text-[10px] transition-colors';
      resetPadDirtyCaches();
      syncLpSideLeds();
    });

    document.getElementById('btn-lp-usermode').addEventListener('click', () => {
      CONFIG.lpUserMode = !CONFIG.lpUserMode;
      const btn = document.getElementById('btn-lp-usermode');
      btn.innerText = CONFIG.lpUserMode ? 'USER MODE' : 'PROGRAMMER';
      resetPadDirtyCaches();
    });

    document.getElementById('btn-lp-rgb').addEventListener('click', () => {
      CONFIG.lpUseRgbSysex = !CONFIG.lpUseRgbSysex;
      const btn = document.getElementById('btn-lp-rgb');
      btn.innerText = CONFIG.lpUseRgbSysex ? 'RGB GRADIENT' : 'PALETTE LED';
      btn.className = CONFIG.lpUseRgbSysex ? 'py-1 rounded bg-cyan-950 text-cyan-300 border border-cyan-700 font-mono text-[10px] transition-colors' : 'py-1 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 font-mono text-[10px] transition-colors';
      resetPadDirtyCaches();
    });

    document.getElementById('btn-rescan-midi').addEventListener('click', () => {
      if (midiAccess) scanMidiPorts();
      else initializeWebMidi();
    });

    const sliderGradientColors = document.getElementById('slider-gradient-colors');
    if (sliderGradientColors) {
      sliderGradientColors.addEventListener('input', (e) => {
        const val = parseInt(e.target.value, 10);
        CONFIG.gradientColorCount = val;
        const lbl = document.getElementById('lbl-gradient-colors');
        if (lbl) lbl.innerText = val;
      });
    }

    document.getElementById('slider-sharpness').addEventListener('input', (e) => {
      CONFIG.visualSharpness = parseFloat(e.target.value);
      document.getElementById('lbl-sharpness').innerText = CONFIG.visualSharpness.toFixed(2);
    });

    document.getElementById('slider-speed').addEventListener('input', (e) => {
      CONFIG.simSpeed = parseFloat(e.target.value);
      document.getElementById('lbl-speed').innerText = `${CONFIG.simSpeed.toFixed(2)}x`;
    });

    document.getElementById('chk-midi-active').addEventListener('change', (e) => {
      midiEnabled = e.target.checked;
      if (midiEnabled) {
        initializeWebMidi();
      } else {
        if (midiOut) {
          // SysEx: Exit to Live Mode
          try { midiOut.send([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00, 0xF7]); } catch(e){}
        }
        document.getElementById('midi-status').innerText = 'MIDI OFF';
        document.getElementById('midi-status').className = 'px-2 py-0.5 rounded text-[10px] font-mono bg-neutral-800 text-neutral-500 transition-colors';
      }
    });

    document.getElementById('sel-midi-in').addEventListener('change', bindMidiEndpoints);
    document.getElementById('sel-midi-out').addEventListener('change', bindMidiEndpoints);


    document.getElementById('sel-octave-shift').addEventListener('change', e => {
      CONFIG.octaveShift = parseInt(e.target.value, 10);
      foodSources.forEach(f => {
          if (f.voice && f.voice.osc) {
              try {
                  f.voice.osc.frequency.setTargetAtTime(getCellFrequency(f.gridCol, f.gridRow), audioCtx.currentTime, 0.1);
              } catch(err) {}
          }
      });
    });

    document.getElementById('slider-visual-blur').addEventListener('input', e => {
      CONFIG.visualBlur = parseFloat(e.target.value);
      document.getElementById('lbl-visual-blur').textContent = parseFloat(e.target.value).toFixed(1) + ' px';
    });

    document.getElementById('sel-root-note').addEventListener('change', (e) => {
      CONFIG.rootNote = parseInt(e.target.value);
      foodSources.forEach(f => {
        if (f.voice.osc) f.voice.osc.frequency.setTargetAtTime(getCellFrequency(f.gridCol, f.gridRow), audioCtx.currentTime, 0.05);
      });
    });

    document.getElementById('sel-scale-type').addEventListener('change', (e) => {
      CONFIG.scaleType = e.target.value;
      foodSources.forEach(f => {
        if (f.voice.osc) f.voice.osc.frequency.setTargetAtTime(getCellFrequency(f.gridCol, f.gridRow), audioCtx.currentTime, 0.05);
      });
    });

    document.querySelectorAll('.btn-wave-sel').forEach(btn => {
      btn.addEventListener('click', (e) => {
        document.querySelectorAll('.btn-wave-sel').forEach(b => {
          b.className = 'btn-wave-sel py-1 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 font-mono transition-colors';
        });
        e.target.className = 'btn-wave-sel py-1 rounded bg-cyan-950 text-cyan-300 border border-cyan-700 font-mono transition-colors';
        CONFIG.waveform = e.target.dataset.wave;
        foodSources.forEach(f => {
          if (f.voice.osc) f.voice.osc.type = CONFIG.waveform;
        });
      });
    });

    document.getElementById('chk-bell-mode').addEventListener('change', (e) => {
      CONFIG.bellAcousticsMode = e.target.checked;
    });

    document.getElementById('slider-bell-q').addEventListener('input', (e) => {
      CONFIG.bellQ = parseFloat(e.target.value);
      document.getElementById('lbl-bell-q').innerText = Math.round(CONFIG.bellQ);
    });

    document.getElementById('slider-bell-sustain').addEventListener('input', (e) => {
      CONFIG.bellSustainLevel = parseFloat(e.target.value);
      document.getElementById('lbl-bell-sustain').innerText = `${CONFIG.bellSustainLevel.toFixed(1)}x`;
    });

    document.getElementById('slider-bell-strike').addEventListener('input', (e) => {
      CONFIG.bellStrikeIntensity = parseFloat(e.target.value);
      document.getElementById('lbl-bell-strike').innerText = `${CONFIG.bellStrikeIntensity.toFixed(1)}x`;
    });

    document.getElementById('chk-show-overlay').addEventListener('change', (e) => {
      CONFIG.showGridOverlay = e.target.checked;
    });

    document.getElementById('slider-lpf-sens').addEventListener('input', (e) => {
      CONFIG.lpfSens = parseFloat(e.target.value);
      document.getElementById('lbl-lpf-sens').innerText = `${CONFIG.lpfSens.toFixed(1)}x`;
    });

    document.getElementById('slider-lpf-q').addEventListener('input', (e) => {
      CONFIG.lpfQ = parseFloat(e.target.value);
      document.getElementById('lbl-lpf-q').innerText = CONFIG.lpfQ.toFixed(1);
    });

    document.getElementById('slider-vca-sens').addEventListener('input', (e) => {
      CONFIG.vcaSens = parseFloat(e.target.value);
      document.getElementById('lbl-vca-sens').innerText = `${CONFIG.vcaSens.toFixed(1)}x`;
    });

    document.getElementById('slider-sensor-dist').addEventListener('input', (e) => {
      CONFIG.sensorDist = parseFloat(e.target.value);
      document.getElementById('lbl-sensor-dist').innerText = `${Math.round(CONFIG.sensorDist)} px`;
    });

    document.getElementById('slider-bmr').addEventListener('input', (e) => {
      CONFIG.bmr = parseFloat(e.target.value);
      document.getElementById('lbl-bmr').innerText = CONFIG.bmr.toFixed(4);
    });

    document.getElementById('slider-loco').addEventListener('input', (e) => {
      CONFIG.locomotionCost = parseFloat(e.target.value);
      document.getElementById('lbl-loco').innerText = CONFIG.locomotionCost.toFixed(4);
    });

    document.querySelectorAll('.btn-palette-sel').forEach(btn => {
      btn.addEventListener('click', (e) => {
        document.querySelectorAll('.btn-palette-sel').forEach(b => {
          b.className = 'btn-palette-sel py-1.5 rounded bg-neutral-800 text-neutral-400 border border-neutral-700 transition-colors';
        });
        e.target.className = 'btn-palette-sel py-1.5 rounded bg-cyan-950 text-cyan-300 border border-cyan-700/60 font-semibold transition-colors';
        CONFIG.palette = e.target.dataset.pal;
      });
    });
  