// Main P5 Instance
    new p5((p) => {
      let pixelBuffer;
      let containerResizeObserver;

      p.setup = () => {
        const container = document.getElementById('canvas-container');
        const d = Math.min(container.clientWidth, container.clientHeight);
        const canvas = p.createCanvas(d, d);
        canvas.parent('canvas-container');
        p.pixelDensity(1);
        p.noSmooth();

        trailMap = new Float32Array(CONFIG.worldDim * CONFIG.worldDim);
        nextTrailMap = new Float32Array(CONFIG.worldDim * CONFIG.worldDim);
        pixelBuffer = p.createImage(CONFIG.worldDim, CONFIG.worldDim);

        resetColony();

        // Responsive resize
        containerResizeObserver = new ResizeObserver(entries => {
            for (let entry of entries) {
                const w = entry.contentRect.width;
                const h = entry.contentRect.height;
                const size = Math.min(w, h);
                p.resizeCanvas(size, size);
            }
        });
        containerResizeObserver.observe(container);
      };

      function resetColony() {
        agents = [];
        foodSources.forEach(f => f.destroy());
        foodSources = [];
        trailMap.fill(0);
        nextTrailMap.fill(0);

        const cx = CONFIG.worldDim / 2;
        const cy = CONFIG.worldDim / 2;
        for (let i = 0; i < CONFIG.initialAgents; i++) {
          const r = Math.random() * 14;
          const th = Math.random() * Math.PI * 2;
          agents.push(new Agent(cx + Math.cos(th) * r, cy + Math.sin(th) * r, Math.random() * Math.PI * 2));
        }

        spawnNoduleInGrid(2, 2);
        spawnNoduleInGrid(5, 2);
        spawnNoduleInGrid(4, 5);
      }

      function sampleTrail(x, y) {
        const ix = Math.floor(x);
        const iy = Math.floor(y);
        if (ix < 0 || ix >= CONFIG.worldDim || iy < 0 || iy >= CONFIG.worldDim) return 0;
        return trailMap[iy * CONFIG.worldDim + ix];
      }


      function stepModel() {
        cellBiomass.fill(0);

        // Population Control
        const popDiff = agents.length - CONFIG.targetAgentCount;
        if (popDiff > 0) {
          agents.splice(agents.length - Math.min(popDiff, 500));
        } else if (popDiff < 0 && agents.length > 0) {
          const spawnCount = Math.min(-popDiff, 500);
          for (let i = 0; i < spawnCount; i++) {
            if (agents.length >= CONFIG.maxAgents) break;
            const srcIdx = Math.floor(Math.random() * agents.length);
            const parent = agents[srcIdx];
            agents.push(new Agent(parent.x + (Math.random()*4-2), parent.y + (Math.random()*4-2), Math.random() * Math.PI * 2));
            agents[agents.length-1].energy = 40.0;
          }
        }

        const grazeGain = 0.015 * 8.0; // grazingRate * assimilationYield
        
        for (let i = agents.length - 1; i >= 0; i--) {
          const ag = agents[i];
          ag.energy -= CONFIG.bmr;

          const lTh = ag.angle - CONFIG.sensorAngle;
          const rTh = ag.angle + CONFIG.sensorAngle;
          const fTh = ag.angle;

          const sL = sampleTrail(ag.x + Math.cos(lTh) * CONFIG.sensorDist, ag.y + Math.sin(lTh) * CONFIG.sensorDist);
          const sF = sampleTrail(ag.x + Math.cos(fTh) * CONFIG.sensorDist, ag.y + Math.sin(fTh) * CONFIG.sensorDist);
          const sR = sampleTrail(ag.x + Math.cos(rTh) * CONFIG.sensorDist, ag.y + Math.sin(rTh) * CONFIG.sensorDist);

          if (sF > sL && sF > sR) {
            ag.angle += (Math.random() * 0.08 - 0.04);
          } else if (sL > sR) {
            ag.angle -= (CONFIG.turnAngle + (Math.random() * 0.06 - 0.03));
          } else if (sR > sL) {
            ag.angle += (CONFIG.turnAngle + (Math.random() * 0.06 - 0.03));
          } else {
            ag.angle += (Math.random() * 0.8 - 0.4);
          }

          if (ag.energy < 28.0) {
            ag.angle += (Math.random() * 0.7 - 0.35);
          }
          
          if (ag.angle < 0) ag.angle += Math.PI * 2;
          else if (ag.angle >= Math.PI * 2) ag.angle -= Math.PI * 2;

          const localTrail = sampleTrail(ag.x, ag.y);
          const territoryCost = Math.max(0.25, 1.0 - (localTrail * (1.0 / 80.0)));
          ag.energy -= CONFIG.locomotionCost * territoryCost;

          let nx = ag.x + Math.cos(ag.angle) * CONFIG.stepSize;
          let ny = ag.y + Math.sin(ag.angle) * CONFIG.stepSize;

          if (nx < 0) nx += CONFIG.worldDim; else if (nx >= CONFIG.worldDim) nx -= CONFIG.worldDim;
          if (ny < 0) ny += CONFIG.worldDim; else if (ny >= CONFIG.worldDim) ny -= CONFIG.worldDim;
          
          ag.x = nx;
          ag.y = ny;

          const px = Math.floor(ag.x);
          const py = Math.floor(ag.y);
          if (px >= 0 && px < CONFIG.worldDim && py >= 0 && py < CONFIG.worldDim) {
            const idx = py * CONFIG.worldDim + px;
            trailMap[idx] = Math.min(trailMap[idx] + 14.0, 255.0);

            const c = Math.min(CONFIG.gridDim - 1, Math.max(0, Math.floor((px / CONFIG.worldDim) * CONFIG.gridDim)));
            const r = Math.min(CONFIG.gridDim - 1, Math.max(0, Math.floor((py / CONFIG.worldDim) * CONFIG.gridDim)));
            cellBiomass[r * CONFIG.gridDim + c] += ag.energy;
          }

          let hitFood = false;
          for (let f = 0; f < foodSources.length; f++) {
            const food = foodSources[f];
            if (food.isDepleted) continue;
            const dx = ag.x - food.x;
            const dy = ag.y - food.y;
            if (dx * dx + dy * dy < food.radius * food.radius) {
              hitFood = true;
              ag.energy += grazeGain;
              food.grazingBuffer += 0.015;
              if (!food.wasFeeding) {
                if (CONFIG.bellAcousticsMode && CONFIG.bellStrikeIntensity > 0 && food.voice) {
                  food.voice.strike(1.0 * CONFIG.bellStrikeIntensity);
                }
                food.wasFeeding = true;
              }
              food.isFeeding = true;
            }
          }

          if (ag.energy > CONFIG.mitosisThreshold && agents.length < CONFIG.maxAgents) {
            ag.energy *= 0.48;
            agents.push(new Agent(ag.x + (Math.random()*3-1.5), ag.y + (Math.random()*3-1.5), ag.angle + (Math.random()*2-1.0)));
            agents[agents.length-1].energy = ag.energy;
          }

          if (ag.energy <= 0) {
            agents[i] = agents[agents.length - 1];
            agents.pop();
          }
        }

        // 2. Manage Food Sources

        for (let i = foodSources.length - 1; i >= 0; i--) {
          const f = foodSources[i];
          const loss = f.grazingBuffer + 0.02;
          f.mass -= loss;
          f.grazingBuffer = 0;
          const ratio = Math.max(0.0, f.mass / f.initialMass);
          f.radius = Math.max(2.5, f.initialRadius * Math.pow(ratio, 0.65));

          if (f.mass <= 0 || f.radius <= 2.5) {
            if (!f.isDepleted) {
              f.isDepleted = true;
              // Quench Depleted Nodule Attractant Core
              const fx = Math.floor(f.x);
              const fy = Math.floor(f.y);
              const clearR = Math.floor(f.radius * 1.5);
              const rSqClear = clearR * clearR;
              for (let dy = -clearR; dy <= clearR; dy++) {
                for (let dx = -clearR; dx <= clearR; dx++) {
                  if (dx * dx + dy * dy <= rSqClear) {
                    const tx = ((fx + dx) % CONFIG.worldDim + CONFIG.worldDim) % CONFIG.worldDim;
                    const ty = ((fy + dy) % CONFIG.worldDim + CONFIG.worldDim) % CONFIG.worldDim;
                    trailMap[ty * CONFIG.worldDim + tx] *= 0.25;
                  }
                }
              }
            }
            if (!CONFIG.bellAcousticsMode || !f.voice || f.voice.getTotalBellEnergy() < 0.001) {
              f.destroy();
              foodSources.splice(i, 1);
              continue;
            }
          }

          if (f.isDepleted) continue;

          // Inject attractant proportional to remaining mass
          const massRatio = f.mass / f.initialMass;
          const strength = 4.0 * massRatio;
          const r = Math.floor(f.radius || 16);
          const rSq = r * r;
          
          const x0 = Math.max(0, Math.floor(f.x - r));
          const x1 = Math.min(CONFIG.worldDim - 1, Math.floor(f.x + r));
          const y0 = Math.max(0, Math.floor(f.y - r));
          const y1 = Math.min(CONFIG.worldDim - 1, Math.floor(f.y + r));

          for (let py = y0; py <= y1; py++) {
            const dy = py - f.y;
            for (let px = x0; px <= x1; px++) {
              const dx = px - f.x;
              if (dx * dx + dy * dy <= rSq) {
                const idx = py * CONFIG.worldDim + px;
                trailMap[idx] = Math.min(255.0, trailMap[idx] + strength * 9.0);
              }
            }
          }
          const adj = calculateMooreBiomass(f.gridCol, f.gridRow);
          f.update(adj);
        }

        // 3. Diffusion and Decay
        const W = CONFIG.worldDim;
        for (let y = 0; y < W; y++) {
          const yTop = ((y === 0) ? W - 1 : y - 1) * W;
          const yMid = y * W;
          const yBtm = ((y === W - 1) ? 0 : y + 1) * W;

          // Interior columns
          for (let x = 1; x < W - 1; x++) {
            const sum = trailMap[yTop + x - 1] + trailMap[yTop + x] + trailMap[yTop + x + 1] +
                        trailMap[yMid + x - 1] +                      trailMap[yMid + x + 1] +
                        trailMap[yBtm + x - 1] + trailMap[yBtm + x] + trailMap[yBtm + x + 1];
            const result = (trailMap[yMid + x] * (1.0 - CONFIG.diffuseRate) + sum * 0.125 * CONFIG.diffuseRate) * CONFIG.decayFactor;
            nextTrailMap[yMid + x] = (result > 1.275) ? result : 0.0;
          }

          // Edge columns wrap
          for (let e = 0; e < 2; e++) {
            const x = (e === 0) ? 0 : W - 1;
            const xl = (x === 0) ? W - 1 : x - 1;
            const xr = (x === W - 1) ? 0 : x + 1;
            const sum = trailMap[yTop + xl] + trailMap[yTop + x] + trailMap[yTop + xr] +
                        trailMap[yMid + xl] +                      trailMap[yMid + xr] +
                        trailMap[yBtm + xl] + trailMap[yBtm + x] + trailMap[yBtm + xr];
            const result = (trailMap[yMid + x] * (1.0 - CONFIG.diffuseRate) + sum * 0.125 * CONFIG.diffuseRate) * CONFIG.decayFactor;
            nextTrailMap[yMid + x] = (result > 1.275) ? result : 0.0;
          }
        }
        trailMap.set(nextTrailMap);
      }

      // --- STREAMING_CHUNK:Refining shrinking food visuals, fading attractant, and UI rendering ---
      let speedAccumulator = 0.0;
      p.draw = () => {
        if (isRunning) {
          speedAccumulator += CONFIG.simSpeed * 0.4; // 0.1x is baseline
          if (speedAccumulator > 10.0) speedAccumulator = 10.0;
          while (speedAccumulator >= 1.0) {
            stepModel();
            speedAccumulator -= 1.0;
          }

        }

        // Texture Render
        const lerp = (a, b, t) => a + (b - a) * t;
        const lerpColor = (c1, c2, t) => {
          return [
            lerp(c1[0], c2[0], t),
            lerp(c1[1], c2[1], t),
            lerp(c1[2], c2[2], t),
            255
          ];
        };

        pixelBuffer.loadPixels();
        const d = pixelBuffer.pixels;
        
        let cBg;
        let pal;
        if (CONFIG.palette === 'yellow') {
          cBg = [6, 7, 10];
          pal = [
            [115, 65, 8],
            [140, 82, 8],
            [161, 98, 7],
            [188, 122, 8],
            [212, 150, 8],
            [234, 179, 8],
            [248, 212, 56],
            [254, 240, 138]
          ];
        } else if (CONFIG.palette === 'mono') {
          cBg = [6, 7, 10];
          pal = [
            [45, 45, 52],
            [70, 70, 78],
            [95, 95, 105],
            [122, 122, 132],
            [148, 148, 158],
            [175, 175, 185],
            [210, 210, 218],
            [245, 245, 250]
          ];
        } else {
          cBg = [6, 7, 10];
          pal = [
            [4, 52, 75],
            [5, 85, 118],
            [6, 120, 160],
            [14, 152, 186],
            [22, 182, 212],
            [34, 211, 238],
            [120, 232, 246],
            [207, 250, 254]
          ];
        }

        const fadeAlpha = p.map(CONFIG.visualBlur || 0, 0, 8.0, 255, 5);
        p.noStroke();
        p.fill(cBg[0], cBg[1], cBg[2], fadeAlpha);
        p.rect(0, 0, p.width, p.height);

        const cSharp = pal[7];
        const s = CONFIG.visualSharpness || 0;
        const moldCutoff = lerp(0.8, 0.4, s);
        let numColors = CONFIG.gradientColorCount || 3;
        if (numColors < 1) numColors = 1;
        if (numColors > 8) numColors = 8;

        const activeBands = new Array(numColors);
        for (let b = 0; b < numColors; b++) {
          const palIdx = (numColors === 1) ? 7 : Math.min(7, Math.max(0, Math.floor(b * 7 / (numColors - 1) + 0.5)));
          activeBands[b] = lerpColor(pal[palIdx], cSharp, s);
        }

        const logCutoff = Math.log(moldCutoff);
        const logTop = Math.log(36.0);
        const logRange = logTop - logCutoff;

        const bandLut = new Int32Array(256);
        for (let v = 0; v < 256; v++) {
          if (v < moldCutoff) {
            bandLut[v] = -1;
          } else if (numColors <= 1) {
            bandLut[v] = 0;
          } else {
            const u = Math.min(1.0, Math.max(0.0, (Math.log(Math.max(v, moldCutoff)) - logCutoff) / logRange));
            let b = Math.floor(u * numColors);
            if (b >= numColors) b = numColors - 1;
            bandLut[v] = b;
          }
        }

        for (let i = 0; i < trailMap.length; i++) {
          const val = trailMap[i];
          const px = i * 4;

          if (val < moldCutoff) {
            d[px] = cBg[0]; d[px+1] = cBg[1]; d[px+2] = cBg[2]; d[px+3] = 0; // transparent for blur
          } else {
            const vInt = Math.min(255, Math.max(0, val | 0));
            let b = bandLut[vInt];
            if (b < 0 || b >= numColors) b = 0;
            const c = activeBands[b] || cSharp;
            d[px] = c[0]; d[px+1] = c[1]; d[px+2] = c[2]; d[px+3] = 255;
          }
        }
        pixelBuffer.updatePixels();
        p.image(pixelBuffer, 0, 0, p.width, p.height);

        // Vector Render: Food Nodes
        for (const food of foodSources) {
          const sx = (food.x / CONFIG.worldDim) * p.width;
          const sy = (food.y / CONFIG.worldDim) * p.height;
          const radMax = (p.width / 800) * 16;

          if (food.isDepleted) {
            const bellEnergy = food.voice ? food.voice.getTotalBellEnergy() : 0;
            if (CONFIG.bellAcousticsMode && bellEnergy > 0.001) {
              p.push();
              p.noFill();
              p.stroke(255, 255, 255, Math.min(140, bellEnergy * 120));
              p.strokeWeight(1.0);
              p.circle(sx, sy, radMax * 2);
              p.pop();
            }
            continue;
          }

          const massRatio = Math.max(0.0, food.mass / food.initialMass);
          
          // Outer original bounds (dashed)
          p.noFill();
          p.stroke(255, 200, 50, 60);
          p.strokeWeight(1);
          p.drawingContext.setLineDash([4, 4]);
          p.circle(sx, sy, radMax * 2);
          p.drawingContext.setLineDash([]);

          // 3D Biomass Elevation Ring (lifts visually with mold mass height)
          if (food.elevationNorm > 0.02) {
            p.push();
            p.noFill();
            p.stroke(6, 182, 212, 70 + 120 * food.elevationNorm);
            p.strokeWeight(1.2);
            const elevOffset = food.elevationNorm * 10.0 * (p.height / CONFIG.worldDim);
            p.ellipse(sx, sy - elevOffset, (radMax + 4) * 2, (radMax + 2) * 2);
            p.pop();
          }

          // Inner solid shrinking core (oat body)
          const radCore = (p.width / 800) * (4 + (massRatio ** 0.65) * 12);
          p.fill(255, 230, 120);
          p.noStroke();
          p.circle(sx, sy, radCore * 2);

          // Red center of the food
          const radCenter = Math.max(2.5, radCore * 0.5);
          p.fill(239, 68, 68);
          p.noStroke();
          p.circle(sx, sy, radCenter * 2);

          // Resource Readout (% and u)
          if(CONFIG.showGridOverlay) {
             const pct = Math.round(massRatio * 100);
             p.fill(pct < 25 ? '#fb7185' : '#d1d5db'); // Rose-red if depleted
             p.textAlign(p.CENTER, p.BOTTOM);
             p.textSize(10);
             p.text(`${pct}%`, sx, sy - radMax - 6);
             p.fill(255, 255, 255, 100);
             p.text(`${Math.round(food.mass)}u`, sx, sy - radMax + 4);
          }
        }

        // HUD Overlay
        if (CONFIG.showGridOverlay) {
          p.stroke(255, 255, 255, 20);
          p.strokeWeight(1);
          const cellPx = p.width / CONFIG.gridDim;
          for (let i = 1; i < CONFIG.gridDim; i++) {
            p.line(i * cellPx, 0, i * cellPx, p.height);
            p.line(0, i * cellPx, p.width, i * cellPx);
          }
          p.noStroke();
          p.textSize(9);
          p.textAlign(p.CENTER, p.CENTER);
          for (let r = 0; r < CONFIG.gridDim; r++) {
            for (let c = 0; c < CONFIG.gridDim; c++) {
              const hz = Math.round(getCellFrequency(c, r));
              p.fill(255, 255, 255, 60);
              p.text(`${hz}Hz`, c * cellPx + cellPx / 2, r * cellPx + cellPx / 2);
            }
          }

          // 3D Binaural Virtual Listener (Center of grid)
          const lx = p.width * 0.5;
          const ly = p.height * 0.5;
          p.push();
          p.noFill();
          p.stroke(6, 182, 212, 180); // Cyan
          p.strokeWeight(1.5);
          p.circle(lx, ly, 16);
          // Nose pointing forward (up towards rows 0-3)
          p.fill(6, 182, 212, 200);
          p.noStroke();
          p.triangle(lx - 3, ly - 7, lx + 3, ly - 7, lx, ly - 12);
          // Left and Right Ears
          p.stroke(6, 182, 212, 220);
          p.strokeWeight(2);
          p.line(lx - 9, ly - 3, lx - 9, ly + 3);
          p.line(lx + 9, ly - 3, lx + 9, ly + 3);
          // Orientation label
          p.noStroke();
          p.textAlign(p.CENTER, p.TOP);
          p.textSize(8);
          p.fill(6, 182, 212, 160);
          p.text("LISTENER (3D)", lx, ly + 11);
          p.pop();
        }

        // Top UI Updates
        if (p.frameCount % 10 === 0) {
          document.getElementById('fps-display').innerText = `${Math.round(p.frameRate())} FPS`;
          document.getElementById('agent-display').innerText = `Agents: ${agents.length}`;
        }

        updateReverbBioTelemetry();
        flushMidiLeds();
      };

      p.mousePressed = () => {
        if (p.mouseX >= 0 && p.mouseX < p.width && p.mouseY >= 0 && p.mouseY < p.height) {
          // Automatically start audio engine on first canvas click
          if (!isAudioActive) {
            toggleAudioEngine();
          } else if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume();
          }
          const simX = (p.mouseX / p.width) * CONFIG.worldDim;
          const simY = (p.mouseY / p.height) * CONFIG.worldDim;
          const col = Math.floor((simX / CONFIG.worldDim) * CONFIG.gridDim);
          const row = Math.floor((simY / CONFIG.worldDim) * CONFIG.gridDim);
          foodSources.push(new FoodNodule(simX, simY));
          triggerPadRipple(col, row);
        }
      };
    });

    function spawnNoduleInGrid(col, row) {
      const cellW = CONFIG.worldDim / CONFIG.gridDim;
      const jX = (Math.random() * 0.7 + 0.15) * cellW;
      const jY = (Math.random() * 0.7 + 0.15) * cellW;
      const x = col * cellW + jX;
      const y = row * cellW + jY;
      foodSources.push(new FoodNodule(x, y));
      triggerPadRipple(col, row);
    }
