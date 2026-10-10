    function getLaunchpadUserNote(col, row) {
      const quadX = Math.floor(col / 4);
      const quadY = Math.floor(row / 4);
      const subX = col % 4;
      const subY = 3 - (row % 4);
      let baseNote = 36;
      if (quadX === 0 && quadY === 1) baseNote = 36;      // Q1 (Bottom-Left)
      else if (quadX === 0 && quadY === 0) baseNote = 52; // Q3 (Top-Left)
      else if (quadX === 1 && quadY === 1) baseNote = 68; // Q2 (Bottom-Right)
      else baseNote = 84;                               // Q4 (Top-Right)
      return baseNote + (subY * 4) + subX;
    }

    function decodeLaunchpadUserNote(note) {
      const index = note - 36;
      const quad = Math.floor(index / 16);
      const sub = index % 16;
      const subRow = Math.floor(sub / 4);
      const subCol = sub % 4;
      const col = (quad >= 2 ? 4 : 0) + subCol;
      const row = (quad % 2 === 0 ? 7 : 3) - subRow;
      return [col, row];
    }

    function triggerPadRipple(col, row) {
      padRipples.push({
        originCol: col,
        originRow: row,
        birthTime: performance.now(),
        durationMs: 900.0,
        maxRadius: 11.5
      });
    }

    function resetPadDirtyCaches() {
      padDirtyBuffer.fill(255);
      padDirtyChannels.fill(-1);
      lastSentPadR.fill(-1);
      lastSentPadG.fill(-1);
      lastSentPadB.fill(-1);
    }


    // --- STREAMING_CHUNK:Connecting Web MIDI SysEx and bidirectional LED heatmap ---
    async function initializeWebMidi() {
      if (!navigator.requestMIDIAccess) {
        document.getElementById('midi-error-msg').classList.remove('hidden');
        document.getElementById('chk-midi-active').checked = false;
        midiEnabled = false;
        return;
      }
      try {
        midiAccess = await navigator.requestMIDIAccess({ sysex: true });
        scanMidiPorts();
        midiAccess.onstatechange = scanMidiPorts;
      } catch (err) {
        console.error("MIDI Init Failure:", err);
      }
    }

    function scanMidiPorts() {
      const inSel = document.getElementById('sel-midi-in');
      const outSel = document.getElementById('sel-midi-out');
      inSel.innerHTML = '<option value="">(Select Input Device)</option>';
      outSel.innerHTML = '<option value="">(Select Output Device)</option>';

      let foundLaunchpadIn = false;
      let foundLaunchpadOut = false;

      for (const input of midiAccess.inputs.values()) {
        const opt = document.createElement('option');
        opt.value = input.id;
        opt.innerText = input.name;
        if (input.name.toLowerCase().includes('launchpad')) { opt.selected = true; foundLaunchpadIn = true; }
        inSel.appendChild(opt);
      }
      for (const output of midiAccess.outputs.values()) {
        const opt = document.createElement('option');
        opt.value = output.id;
        opt.innerText = output.name;
        if (output.name.toLowerCase().includes('launchpad')) { opt.selected = true; foundLaunchpadOut = true; }
        outSel.appendChild(opt);
      }

      if(foundLaunchpadIn && foundLaunchpadOut) bindMidiEndpoints();
    }

    function bindMidiEndpoints() {
      if (!midiAccess) return;
      const inId = document.getElementById('sel-midi-in').value;
      const outId = document.getElementById('sel-midi-out').value;

      if (midiIn) midiIn.onmidimessage = null;
      midiIn = midiAccess.inputs.get(inId);
      if (midiIn) {
        midiIn.onmidimessage = onMidiMessageReceived;
      }

      midiOut = midiAccess.outputs.get(outId);
      if (midiOut && midiEnabled) {
        // SysEx: Enter Programmer Mode (Launchpad Mini MK3 ref page 7)
        try {
            midiOut.send([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]);
            document.getElementById('midi-status').innerText = 'LP MK3 ON';
            document.getElementById('midi-status').className = 'px-2 py-0.5 rounded text-[10px] font-mono bg-cyan-900/60 text-cyan-300';
            syncLpSideLeds();
        } catch(e) {}
      }
    }

    function onMidiMessageReceived(event) {
      if (!midiEnabled) return;
      const [status, data1, data2] = event.data;
      const isMidimix = (midiIn && midiIn.name && midiIn.name.toLowerCase().includes('midimix'));

      if (isMidimix) {
        handleMidimix(status, data1, data2);
      } else {
        // Launchpad handling (Notes & Perimeter CC side buttons)
        const cmd = status & 0xF0;
        if (cmd === 0x90 && data2 > 0) {
          let row = -1;
          let col = -1;

          // Auto-detect Programmer vs User Mode
          if (data1 >= 11 && data1 < 36) {
            CONFIG.lpUserMode = false;
          } else if (data1 > 88 && data1 <= 99) {
            CONFIG.lpUserMode = true;
          } else if (data1 >= 36 && data1 <= 88) {
            const c10 = data1 % 10;
            if (c10 === 9 || c10 === 0) CONFIG.lpUserMode = true;
          }

          if (CONFIG.lpUserMode) {
            if (data1 >= 36 && data1 <= 99) {
              const cr = decodeLaunchpadUserNote(data1);
              col = cr[0];
              row = cr[1];
            }
          } else {
            const r10 = Math.floor(data1 / 10);
            const c10 = data1 % 10;
            if (r10 >= 1 && r10 <= 8 && c10 >= 1 && c10 <= 8) {
              row = 8 - r10;
              col = c10 - 1;
            }
          }

          if (row >= 0 && row < 8 && col >= 0 && col < 8) {
            spawnNoduleInGrid(col, row);
          }
        } else if (cmd === 0xB0) {
          // Launchpad side buttons (Scene Launch column: CC 89, 79, 39, 29, 19)
          if (data2 > 0) {
            if (data1 === 89) {
              lpTopSidePressed = true;
              document.getElementById('btn-reinoculate').click();
              sendLpCc(1, 89, 13); // Flash brilliant yellow
            } else if (data1 === 79) {
              lpSecSidePressed = true;
              document.getElementById('btn-clear-food').click();
              sendLpCc(1, 79, 5); // Flash brilliant red
            } else if (data1 === 39) {
              document.getElementById('btn-lp-slime').click();
            } else if (data1 === 29) {
              document.getElementById('btn-lp-food').click();
            } else if (data1 === 19) {
              document.getElementById('btn-lp-eat').click();
            }
          } else {
            if (data1 === 89) {
              lpTopSidePressed = false;
              sendLpCc(1, 89, 15);
            } else if (data1 === 79) {
              lpSecSidePressed = false;
              sendLpCc(1, 79, 7);
            }
          }
        }
      }
    }

    function sendLpCc(channel, cc, val) {
      if (!midiOut || !midiEnabled) return;
      try {
        midiOut.send([0xB0 | ((channel - 1) & 0x0F), cc, val & 0x7F]);
      } catch(e) {}
    }

    function syncLpSideLeds() {
      if (!midiOut || !midiEnabled) return;
      sendLpCc(1, 89, lpTopSidePressed ? 13 : 15);
      sendLpCc(1, 79, lpSecSidePressed ? 5 : 7);
      sendLpCc(1, 39, CONFIG.lpShowSlime ? 13 : 0);
      sendLpCc(1, 29, CONFIG.lpShowFood ? 37 : 0);
      sendLpCc(1, 19, CONFIG.lpShowEating ? 53 : 0);
    }

    function setSliderVal(id, minVal, maxVal, normVal, formatCb) {
      const el = document.getElementById(id);
      if (!el) return;
      const val = minVal + (maxVal - minVal) * normVal;
      el.value = val;
      el.dispatchEvent(new Event('input'));
    }

    function handleMidimix(status, d1, d2) {
      const cmd = status & 0xF0;
      
      if (cmd === 0x90 && d2 > 0) { // Note On
        // Actions
        if (d1 === 3) { const b = document.getElementById('btn-seed-food'); if (b) b.click(); }
        else if (d1 === 6) { const b = document.getElementById('btn-clear-food'); if (b) b.click(); }
        else if (d1 === 9) { const b = document.getElementById('btn-reinoculate'); if (b) b.click(); }
        else if (d1 === 12) { const b = document.getElementById('btn-rescan-midi'); if (b) b.click(); }
        else if (d1 === 15) { const b = document.getElementById('btn-regen-ir'); if (b) b.click(); }
        else if (d1 === 21) { addFoodNodule(Math.random() * (SIM_W - 80) + 40, Math.random() * (SIM_H - 80) + 40, 16, 512); }
        else if (d1 === 24) { retuneAllNodules(); }

        // Row 1 Toggles (MUTE)
        else if (d1 === 1) { const b = document.getElementById('btn-engine-toggle'); if (b) b.click(); }
        else if (d1 === 4) { const b = document.getElementById('btn-audio-toggle'); if (b) b.click(); }
        else if (d1 === 7) { const b = document.getElementById('btn-fullscreen'); if (b) b.click(); }
        else if (d1 === 10) { const b = document.getElementById('chk-show-overlay'); if (b) b.click(); }
        else if (d1 === 13) { const b = document.getElementById('chk-reverb-active'); if (b) b.click(); }
        else if (d1 === 16) { const b = document.getElementById('chk-biomod-active'); if (b) b.click(); }
        else if (d1 === 19) { const b = document.getElementById('chk-midi-active'); if (b) b.click(); }
        else if (d1 === 22) { const b = document.getElementById('btn-lp-usermode'); if (b) b.click(); }

        // Row 2 Toggles / Selectors (SOLO)
        else if (d1 === 2) { const b = document.getElementById('btn-lp-slime'); if (b) b.click(); }
        else if (d1 === 5) { const b = document.getElementById('btn-lp-food'); if (b) b.click(); }
        else if (d1 === 8) { const b = document.getElementById('btn-lp-eat'); if (b) b.click(); }
        else if (d1 === 11) { const b = document.getElementById('btn-lp-rgb'); if (b) b.click(); }
        else if (d1 === 20) {
          const sel = document.getElementById('sel-octave-shift');
          if (sel) {
            let nextVal = parseInt(sel.value, 10) + 1;
            if (nextVal > 1) nextVal = -1;
            sel.value = nextVal;
            sel.dispatchEvent(new Event('change'));
          }
        }
        else if (d1 === 23) {
          const sel = document.getElementById('sel-scale-type');
          if (sel) {
            const nextIdx = (sel.selectedIndex + 1) % sel.options.length;
            sel.selectedIndex = nextIdx;
            sel.dispatchEvent(new Event('change'));
          }
        }
        
        // Turn on LED
        if (midiOut) {
            try { midiOut.send([0x90, d1, 127]); } catch(e){}
        }
      } else if (cmd === 0x80 || (cmd === 0x90 && d2 === 0)) { // Note Off
        // Turn off momentary LEDs
        if ([3, 6, 9, 12, 15, 18, 21, 24, 14, 17, 20, 23].includes(d1)) {
          if (midiOut) { try { midiOut.send([0x90, d1, 0]); } catch(e){} }
        }
      } else if (cmd === 0xB0) { // CC
        const val = d2 / 127.0;
        // Faders (1-8 + Master)
        if (d1 === 19 || d1 === 50) setSliderVal('slider-lpf-sens', 0.2, 3.0, val);
        else if (d1 === 23 || d1 === 51) setSliderVal('slider-lpf-q', 0.5, 18.0, val);
        else if (d1 === 27 || d1 === 52) setSliderVal('slider-vca-sens', 0.2, 3.0, val);
        else if (d1 === 31 || d1 === 54 || d1 === 28) setSliderVal('slider-rev-wet', 0.0, 1.0, val);
        else if (d1 === 49 || d1 === 55 || d1 === 29) setSliderVal('slider-rev-dry', 0.0, 1.0, val);
        else if (d1 === 53 || d1 === 56 || d1 === 30) setSliderVal('slider-rev-t60', 0.5, 8.0, val);
        else if (d1 === 57 || d1 === 58) setSliderVal('slider-rev-damp', 0.05, 0.95, val);
        else if (d1 === 61 || d1 === 59 || d1 === 33) setSliderVal('slider-rev-pre', 0.005, 0.060, val);
        else if (d1 === 62 || d1 === 60 || d1 === 11) setSliderVal('slider-speed', 0.1, 30.0, val);
        
        // Row 1 Knobs
        else if (d1 === 16) setSliderVal('slider-sensor-dist', 6, 160, val);
        else if (d1 === 20) setSliderVal('slider-bmr', 0.001, 0.050, val);
        else if (d1 === 24) setSliderVal('slider-loco', 0.002, 0.080, val);
        
        // Row 2 Knobs
        else if (d1 === 17) setSliderVal('slider-sharpness', 0.0, 1.0, val);
        else if (d1 === 21) setSliderVal('slider-agents', 1000, 64000, val);
        else if (d1 === 25) setSliderVal('slider-visual-blur', 0.0, 8.0, val);
        else if (d1 === 29) setSliderVal('slider-ripple-width', 1.0, 5.0, val);
        else if (d1 === 47) {
          const sel = document.getElementById('sel-scale-type');
          if (sel) {
            const idx = Math.min(sel.options.length - 1, Math.round(val * (sel.options.length - 1)));
            if (sel.selectedIndex !== idx) {
              sel.selectedIndex = idx;
              sel.dispatchEvent(new Event('change'));
            }
          }
        }

        // Row 3 Knobs
        else if (d1 === 18) {
          const octIdx = Math.round(val * 2.0) - 1; // -1, 0, +1
          const sel = document.getElementById('sel-octave-shift');
          if (sel && parseInt(sel.value, 10) !== octIdx) {
            sel.value = octIdx;
            sel.dispatchEvent(new Event('change'));
          }
        }
        else if (d1 === 22) setSliderVal('slider-led-thresh', 20.0, 1000.0, val);
        else if (d1 === 26) setSliderVal('slider-biomod-depth', 0.0, 4.0, val);
        else if (d1 === 48) {
          const sel = document.getElementById('sel-root-note');
          if (sel) {
            const idx = Math.min(sel.options.length - 1, Math.round(val * (sel.options.length - 1)));
            if (sel.selectedIndex !== idx) {
              sel.selectedIndex = idx;
              sel.dispatchEvent(new Event('change'));
            }
          }
        }
      }
    }

    // Update active ripples and calculate crest intensities for each pad
    function computeRippleIntensities(now) {
      const rippleIntensities = new Float32Array(64);
      padRipples = padRipples.filter(pr => (now - pr.birthTime) < pr.durationMs);

      for (let i = 0; i < padRipples.length; i++) {
        const pr = padRipples[i];
        const tau = (now - pr.birthTime) / pr.durationMs;
        if (tau < 0 || tau >= 1.0) continue;
        const rWave = pr.maxRadius * tau;
        const amp = Math.max(0.0, 1.0 - tau * 0.65);
        const sigma = Math.max(0.35, (CONFIG.lpRippleWidth || 3.0) * 0.38);
        const twoSigmaSq = 2.0 * sigma * sigma;

        for (let r = 0; r < 8; r++) {
          for (let c = 0; c < 8; c++) {
            const idx = r * 8 + c;
            const d = Math.sqrt((c - pr.originCol)**2 + (r - pr.originRow)**2);
            const delta = Math.abs(d - rWave);
            let crest = amp * Math.exp(-(delta * delta) / twoSigmaSq);
            if (c === pr.originCol && r === pr.originRow && tau < 0.25) {
              const flash = Math.pow(1.0 - (tau / 0.25), 1.5);
              crest = Math.max(crest, flash);
            }
            rippleIntensities[idx] = Math.min(1.0, rippleIntensities[idx] + crest);
          }
        }
      }
      return rippleIntensities;
    }

    function evaluateBiomassGradient(mass, threshold, outRgb) {
      const u = Math.min(1.0, Math.max(0.0, (mass - threshold) / (threshold * 7.0)));
      const up = Math.pow(u, 0.75);
      if (up <= 0.001) { outRgb[0] = 0; outRgb[1] = 0; outRgb[2] = 0; return; }

      if (CONFIG.palette === 'mono') {
        const r = 12.0 + (122.0 - 12.0) * up;
        outRgb[0] = r; outRgb[1] = r; outRgb[2] = r;
      } else if (CONFIG.palette === 'cyan') {
        if (up < 0.5) {
          const f = up * 2.0;
          outRgb[0] = 2.0 + (17.0 - 2.0) * f;
          outRgb[1] = 26.0 + (105.0 - 26.0) * f;
          outRgb[2] = 37.0 + (119.0 - 37.0) * f;
        } else {
          const f = (up - 0.5) * 2.0;
          outRgb[0] = 17.0 + (103.0 - 17.0) * f;
          outRgb[1] = 105.0 + (125.0 - 105.0) * f;
          outRgb[2] = 119.0 + (127.0 - 119.0) * f;
        }
      } else { // Yellow (Zorn)
        if (up < 0.33) {
          const f = up / 0.33;
          outRgb[0] = 12.0 + (65.0 - 12.0) * f;
          outRgb[1] = 6.0 + (38.0 - 6.0) * f;
          outRgb[2] = 1.0 + (4.0 - 1.0) * f;
        } else if (up < 0.66) {
          const f = (up - 0.33) / 0.33;
          outRgb[0] = 65.0 + (117.0 - 65.0) * f;
          outRgb[1] = 38.0 + (90.0 - 38.0) * f;
          outRgb[2] = 4.0 + (6.0 - 4.0) * f;
        } else {
          const f = (up - 0.66) / 0.34;
          outRgb[0] = 117.0 + (127.0 - 117.0) * f;
          outRgb[1] = 90.0 + (120.0 - 90.0) * f;
          outRgb[2] = 6.0 + (69.0 - 6.0) * f;
        }
      }
    }

    function flushMidiLeds() {
      if (!midiEnabled || !midiOut) return;
      const isMidimix = (midiOut && midiOut.name && midiOut.name.toLowerCase().includes('midimix'));
      if (isMidimix) return; // handled via note events

      const now = performance.now();
      if (now - lastMidiFlushTime < 45) return; // ~22Hz dirty update
      lastMidiFlushTime = now;

      const rippleIntensities = computeRippleIntensities(now);
      const moldRgb = [0, 0, 0];

      if (CONFIG.lpUseRgbSysex) {
        // Continuous 7-bit RGB Gradient SysEx (Command 03h)
        const dirtyIndices = [];
        for (let r = 0; r < 8; r++) {
          for (let c = 0; c < 8; c++) {
            const idx = r * 8 + c;
            const matchingFoods = foodSources.filter(f => f.gridCol === c && f.gridRow === r);
            const hasFood = (matchingFoods.length > 0 && matchingFoods[0].mass > 0);
            const cellFood = hasFood ? matchingFoods[0] : null;
            const isEating = hasFood && (cellFood.isFeeding || cellFood.consumptionActivity > 0.05);

            let tR = 0, tG = 0, tB = 0;
            if (CONFIG.lpShowSlime) {
              smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18;
              const mass = smoothBiomass[idx];
              const t = Math.max(10.0, CONFIG.ledMassThreshold || 120.0);
              evaluateBiomassGradient(mass, t, moldRgb);
              tR = moldRgb[0]; tG = moldRgb[1]; tB = moldRgb[2];
            }

            if (hasFood && CONFIG.lpShowFood && !isEating) {
              const breath = 0.85 + 0.15 * Math.sin(now * 0.005 + (r + c) * 0.5);
              tR = Math.max(tR, 0);
              tG = Math.max(tG, 110.0 * breath);
              tB = Math.max(tB, 127.0 * breath);
            }

            if (isEating && CONFIG.lpShowEating) {
              const targetRatio = cellFood.mass / cellFood.initialMass;
              smoothFoodRatio[idx] += (targetRatio - smoothFoodRatio[idx]) * 0.25;
              const fr = smoothFoodRatio[idx];
              const feedPulse = 0.85 + 0.15 * Math.sin(now * 0.012);
              const eatR = (60.0 + (127.0 - 60.0) * fr) * feedPulse;
              const eatG = 0;
              const eatB = (110.0 + (75.0 - 110.0) * fr) * feedPulse;
              const act = Math.min(1.0, Math.max(0.0, cellFood.consumptionActivity));
              tR = tR + (eatR - tR) * act;
              tG = tG + (eatG - tG) * act;
              tB = tB + (eatB - tB) * act;
            }

            const rip = rippleIntensities[idx];
            if (rip > 0.001) {
              const rRip = (rip > 0.6) ? ((rip - 0.6) / 0.4) * 127.0 : 0.0;
              tR = tR + (rRip - tR) * rip;
              tG = tG + (127.0 - tG) * rip;
              tB = tB + (127.0 - tB) * rip;
            }

            currentPadR[idx] += (tR - currentPadR[idx]) * 0.28;
            currentPadG[idx] += (tG - currentPadG[idx]) * 0.28;
            currentPadB[idx] += (tB - currentPadB[idx]) * 0.28;

            const qR = Math.min(127, Math.max(0, Math.round(currentPadR[idx])));
            const qG = Math.min(127, Math.max(0, Math.round(currentPadG[idx])));
            const qB = Math.min(127, Math.max(0, Math.round(currentPadB[idx])));

            if (qR !== lastSentPadR[idx] || qG !== lastSentPadG[idx] || qB !== lastSentPadB[idx]) {
              dirtyIndices.push(idx);
            }
          }
        }

        if (dirtyIndices.length > 0) {
          const chunkSize = 50;
          for (let i = 0; i < dirtyIndices.length; i += chunkSize) {
            const count = Math.min(chunkSize, dirtyIndices.length - i);
            const sysex = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x03];
            for (let k = 0; k < count; k++) {
              const idx = dirtyIndices[i + k];
              const r = Math.floor(idx / 8);
              const c = idx % 8;
              const ledIndex = (8 - r) * 10 + (c + 1);
              const qR = Math.min(127, Math.max(0, Math.round(currentPadR[idx])));
              const qG = Math.min(127, Math.max(0, Math.round(currentPadG[idx])));
              const qB = Math.min(127, Math.max(0, Math.round(currentPadB[idx])));
              lastSentPadR[idx] = qR;
              lastSentPadG[idx] = qG;
              lastSentPadB[idx] = qB;
              sysex.push(0x03, ledIndex, qR, qG, qB);
            }
            sysex.push(0xF7);
            try { midiOut.send(sysex); } catch(e) {}
          }
        }
      } else {
        // Standard Channel-Based MIDI Streaming (Static Ch 1, Flashing Ch 2, Pulsing Ch 3 with Trilateral Domain)
        for (let r = 0; r < 8; r++) {
          for (let c = 0; c < 8; c++) {
            const idx = r * 8 + c;
            const progNote = (8 - r) * 10 + (c + 1);
            const userNote = getLaunchpadUserNote(c, r);
            const note = CONFIG.lpUserMode ? userNote : progNote;

            const matchingFoods = foodSources.filter(f => f.gridCol === c && f.gridRow === r);
            const hasFood = (matchingFoods.length > 0 && matchingFoods[0].mass > 0);
            const cellFood = hasFood ? matchingFoods[0] : null;
            const isEating = hasFood && (cellFood.isFeeding || cellFood.consumptionActivity > 0.05);

            let targetChan = 1; // 1 = Static, 2 = Flashing, 3 = Pulsing
            let targetVel = 0;

            if (CONFIG.lpShowSlime) {
              smoothBiomass[idx] += (cellBiomass[idx] - smoothBiomass[idx]) * 0.18;
              const mass = smoothBiomass[idx];
              const t = Math.max(10.0, CONFIG.ledMassThreshold || 120.0);

              if (mass >= t * 0.7) {
                if (CONFIG.palette === 'cyan') {
                  if (mass >= t * 6.0) { targetChan = 1; targetVel = 3; }
                  else if (mass >= t * 4.0) { targetChan = 1; targetVel = 78; }
                  else if (mass >= t * 2.5) { targetChan = 1; targetVel = 37; }
                  else if (mass >= t * 1.5) { targetChan = 1; targetVel = 38; }
                  else if (mass >= t * 1.0) { targetChan = 1; targetVel = 39; }
                  else { targetChan = 3; targetVel = 39; }
                } else if (CONFIG.palette === 'mono') {
                  if (mass >= t * 6.0) { targetChan = 1; targetVel = 3; }
                  else if (mass >= t * 3.5) { targetChan = 1; targetVel = 2; }
                  else if (mass >= t * 1.5) { targetChan = 1; targetVel = 1; }
                  else { targetChan = 3; targetVel = 1; }
                } else { // Yellow / Zorn
                  if (mass >= t * 8.0) { targetChan = 1; targetVel = 12; }
                  else if (mass >= t * 5.0) { targetChan = 1; targetVel = 13; }
                  else if (mass >= t * 3.0) { targetChan = 1; targetVel = 14; }
                  else if (mass >= t * 1.8) { targetChan = 1; targetVel = 15; }
                  else if (mass >= t * 1.0) { targetChan = 1; targetVel = 62; }
                  else if (mass >= t * 0.7) { targetChan = 1; targetVel = 84; }
                  else { targetChan = 3; targetVel = 11; }
                }
              }
            }

            if (hasFood && CONFIG.lpShowFood && !isEating) {
              targetChan = 3; // Pulsing
              targetVel = 37; // Electric Cyan
            }

            if (isEating && CONFIG.lpShowEating) {
              targetChan = 3; // Pulsing
              const ratio = cellFood.mass / cellFood.initialCapacity;
              if (ratio > 0.65) targetVel = 53;      // Brilliant Magenta
              else if (ratio > 0.35) targetVel = 54; // Deep Magenta
              else if (ratio > 0.15) targetVel = 55; // Medium Purple
              else targetVel = 52;                   // Soft Lavender
            }

            const rip = rippleIntensities[idx];
            if (rip > 0.05) {
              targetChan = 1;
              if (rip > 0.75) targetVel = 3;       // White
              else if (rip > 0.45) targetVel = 78;  // Aqua Cyan
              else if (rip > 0.20) targetVel = 37;  // Cyan
              else targetVel = 39;                  // Deep Cyan
            }

            if (padDirtyBuffer[idx] !== targetVel || padDirtyChannels[idx] !== targetChan) {
              padDirtyBuffer[idx] = targetVel;
              padDirtyChannels[idx] = targetChan;
              const ch = (targetChan - 1) & 0x0F;
              try { midiOut.send([0x90 | ch, note, targetVel]); } catch(e){}
            }
          }
        }
      }
    }

    // --- STREAMING_CHUNK:Binding UI event listeners to simulation parameters ---