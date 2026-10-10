class FoodNodule {
      constructor(x, y) {
        this.x = x;
        this.y = y;
        this.initialRadius = 8.0 + Math.random() * 16.0;
        this.radius = this.initialRadius;
        this.initialMass = this.radius * this.radius * 2.0;
        this.mass = this.initialMass;
        this.gridCol = Math.floor((this.x / CONFIG.worldDim) * CONFIG.gridDim);
        this.gridRow = Math.floor((this.y / CONFIG.worldDim) * CONFIG.gridDim);
        this.isFeeding = false;
        this.wasFeeding = false;
        this.isDepleted = false;
        this.elevationNorm = 0.0;
        this.vcaGain = 0.0;
        this.consumptionActivity = 0.0;
        this.grazingBuffer = 0.0;
        this.voice = new FoodAudioVoice(this);
      }

      update(adjacentMass) {
        this.voice.update(adjacentMass, this.isFeeding);
        if (!this.isFeeding) this.wasFeeding = false;
        this.isFeeding = false; // Reset for next frame
      }

      destroy() {
        this.voice.destroy();
      }
    }

    // Sums biomass in the 8 surrounding cells
    function calculateMooreBiomass(col, row) {
      let sum = 0;
      for (let dc = -1; dc <= 1; dc++) {
        for (let dr = -1; dr <= 1; dr++) {
          if (dc === 0 && dr === 0) continue;
          const c = col + dc;
          const r = row + dr;
          if (c >= 0 && c < CONFIG.gridDim && r >= 0 && r < CONFIG.gridDim) {
            sum += cellBiomass[r * CONFIG.gridDim + c];
          }
        }
      }
      return sum;
    }

    // --- STREAMING_CHUNK:Coding Agent sensing, locomotion, and trail deposition ---
    class Agent {
      constructor(x, y, angle) {
        this.x = x;
        this.y = y;
        this.angle = angle;
        this.energy = 50.0 * (0.8 + Math.random() * 0.4);
      }
    }
