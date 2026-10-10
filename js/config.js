    // --- Global Application State & Configuration ---
    const CONFIG = {
      simSpeed: 1.0,
      gridDim: 8,
      worldDim: 256,
      sensorDist: 40.0,
      sensorAngle: 0.61,
      turnAngle: 0.384,
      stepSize: 1.0,
      decayFactor: 0.965,
      diffuseRate: 0.45,
      bmr: 0.010,
      locomotionCost: 0.018,
      mitosisThreshold: 75.0,
      maxAgents: 64000,
      initialAgents: 16000,
      targetAgentCount: 16000,
      octaveShift: 0,
      visualBlur: 0.0,
      baseReverbWet: 0.50,
      baseReverbDry: 0.80,
      baseReverbT60: 3.5,
      baseReverbHighDamping: 0.45,
      baseReverbPreDelay: 0.015,
      reverbWet: 0.50,
      reverbDry: 0.80,
      reverbT60: 3.5,
      reverbHighDamping: 0.45,
      reverbPreDelay: 0.015,
      reverbBioModDepth: 2.0, // Default 2.0x is 2x pronounced bio-modulation
      reverbEnabled: true,
      autoModulateReverb: true,
      reverbSeed: 1337,
      lastMitosisBiomassThreshold: 8000.0,
      visualSharpness: 0.0,
      gradientColorCount: 3,
      lpfSens: 3.0, // Default to maximum on startup
      lpfQ: 18.0,  // Default to maximum on startup
      vcaSens: 1.0,
      vcaGateThreshold: 120.0,
      rootNote: 9, // 'A'
      scaleType: 'major_pentatonic',
      waveform: 'triangle',
      bellAcousticsMode: true,
      bellQ: 1800.0,
      bellSustainLevel: 1.0,
      bellStrikeIntensity: 1.0,
      showGridOverlay: false,
      palette: 'yellow',
      ledMassThreshold: 120.0,
      lpRippleWidth: 3.0,
      lpShowSlime: true,
      lpShowFood: false,
      lpShowEating: false,
      lpUserMode: true,
      lpUseRgbSysex: false
    };

    let agents = [];
    let trailMap, nextTrailMap;
    let foodSources = [];
    let cellBiomass = new Float32Array(64);
    let isRunning = true;
    let audioCtx = null;
    let masterGain = null;
    let isAudioActive = false;
    let reverbConvolver = null;
    let reverbWetGain = null;
    let reverbDryGain = null;

    // --- Web MIDI State (Launchpad) ---
    let midiAccess = null;
    let midiIn = null;
    let midiOut = null;
    let midiEnabled = false;
    let padDirtyBuffer = new Uint8Array(64).fill(255);
    let padDirtyChannels = new Int8Array(64).fill(-1);
    let lastSentPadR = new Int8Array(64).fill(-1);
    let lastSentPadG = new Int8Array(64).fill(-1);
    let lastSentPadB = new Int8Array(64).fill(-1);
    let currentPadR = new Float32Array(64);
    let currentPadG = new Float32Array(64);
    let currentPadB = new Float32Array(64);
    let smoothBiomass = new Float32Array(64);
    let smoothFoodRatio = new Float32Array(64);
    let lastMidiFlushTime = 0;
    let padRipples = [];
    let lpTopSidePressed = false;
    let lpSecSidePressed = false;

    // Launchpad Drum Rack (4-Quadrant) 36..99 mapping
    // --- STREAMING_CHUNK:Implementing Music Theory matrices and frequencies ---
    const SCALE_INTERVALS = {
      major_pentatonic: [0, 2, 4, 7, 9],
      minor_pentatonic: [0, 3, 5, 7, 10],
      lydian: [0, 2, 4, 6, 7, 9, 11],
      dorian: [0, 2, 3, 5, 7, 9, 10],
      hirajoshi: [0, 2, 3, 7, 8],
      just_intonation: [1.0, 9/8, 5/4, 4/3, 3/2, 5/3, 15/8] // Microtonal ratios
    };

    function getCellFrequency(col, row) {
      const invertedRow = 7 - row;
      const gridOctaveShift = Math.floor(invertedRow / 2);
      const userOctaveShift = parseInt(CONFIG.octaveShift, 10);
      const baseOctave = 1; // User requested -1 octave shift overall
      const oct = baseOctave + gridOctaveShift + userOctaveShift;
      const subOffset = (invertedRow % 2 === 1) ? 1.5 : 1.0;

      if (CONFIG.scaleType !== 'just_intonation') {
        const degs = SCALE_INTERVALS[CONFIG.scaleType];
        const semitone = degs[col % degs.length];
        const totalSemitone = (oct * 12) + parseInt(CONFIG.rootNote, 10) + semitone;
        const freq = 440.0 * Math.pow(2.0, (totalSemitone - 57) / 12.0) * subOffset;
        return isNaN(freq) ? 110.0 : freq;
      } else {
        const baseF = 55.0 * Math.pow(2.0, oct - 1) * Math.pow(2.0, parseInt(CONFIG.rootNote, 10) / 12.0);
        const ratios = SCALE_INTERVALS.just_intonation;
        const freq = baseF * ratios[col % ratios.length] * subOffset;
        return isNaN(freq) ? 110.0 : freq;
      }
    }

    // --- Bell Acoustics Simpson Carillon Tuning Ratios & Modal Parameters ---
    const BELL_RATIOS = [0.50, 1.00, 1.1892, 1.4983, 2.00, 2.74];
    const BELL_STRIKE_AMPS = [0.45, 0.65, 0.75, 0.85, 1.00, 0.90];
    const BELL_SUSTAIN_WEIGHTS = [0.60, 0.80, 0.70, 0.50, 0.35, 0.05];
    const BELL_Q_MULTS = [1.0, 1.0, 1.0, 1.0, 0.9, 0.35];