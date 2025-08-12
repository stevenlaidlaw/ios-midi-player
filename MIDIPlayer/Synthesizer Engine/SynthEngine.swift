import Foundation
import AVFoundation

// MARK: - Enums and Structs

enum Waveform: String, CaseIterable {
    case sine = "Sine"
    case triangle = "Triangle"
    case sawtooth = "Sawtooth"
    case square = "Square"
    case pulse = "Pulse"
    case noise = "Noise"
}

struct OscillatorSettings {
    var waveform: Waveform = .sine
    var pitch: Float = 0.0        // -24 to +24 semitones
    var detune: Float = 0.0       // -100 to +100 cents (fractions of semitone)
    var level: Float = 1.0        // 0.0 to 1.0
    var pulseWidth: Float = 0.5   // For pulse wave (0.1 - 0.9)
}

struct ADSRSettings {
    var attack: Float = 0.1    // seconds
    var decay: Float = 0.4     // seconds
    var sustain: Float = 0.7   // level (0.0 - 1.0)
    var release: Float = 0.8   // seconds
}

enum FilterType: String, CaseIterable {
    case lowpass = "Low Pass"
    case highpass = "High Pass"
    case bandpass = "Band Pass"
}

struct FilterSettings {
    var type: FilterType = .lowpass
    var cutoff: Float = 1000.0      // Hz
    var resonance: Float = 1.0      // Q factor
    var envelopeAmount: Float = 0.0 // -1.0 to 1.0
}

// MARK: - Envelope Class

class ADSREnvelope {
    private var settings: ADSRSettings
    private var startTime: Date?
    private var releaseTime: Date?
    private var isReleasing = false
    private var releaseStartLevel: Float = 0.0
    
    init(settings: ADSRSettings) {
        self.settings = settings
    }
    
    func updateSettings(_ newSettings: ADSRSettings) {
        settings = newSettings
    }
    
    func noteOn() {
        startTime = Date()
        releaseTime = nil
        isReleasing = false
        releaseStartLevel = 0.0
    }
    
    func noteOff() {
        if let startTime = startTime {
            let elapsed = Float(Date().timeIntervalSince(startTime))
            releaseStartLevel = getLevelAtTime(elapsed)
        }
        releaseTime = Date()
        isReleasing = true
    }
    
    func currentLevel() -> Float {
        guard let startTime = startTime else { return 0.0 }
        
        let elapsed = Float(Date().timeIntervalSince(startTime))
        
        if isReleasing, let releaseTime = releaseTime {
            let releaseElapsed = Float(Date().timeIntervalSince(releaseTime))
            let releaseProgress = min(releaseElapsed / settings.release, 1.0)
            return releaseStartLevel * (1.0 - releaseProgress)
        } else {
            return getLevelAtTime(elapsed)
        }
    }
    
    private func getLevelAtTime(_ elapsed: Float) -> Float {
        if elapsed <= settings.attack {
            // Attack phase: 0 to 1
            return elapsed / settings.attack
        } else if elapsed <= settings.attack + settings.decay {
            // Decay phase: 1 to sustain level
            let decayElapsed = elapsed - settings.attack
            let decayProgress = decayElapsed / settings.decay
            return 1.0 - (1.0 - settings.sustain) * decayProgress
        } else {
            // Sustain phase: hold at sustain level
            return settings.sustain
        }
    }
}

// MARK: - Main SynthEngine Class

class SynthEngine: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var mixer: AVAudioMixerNode
    
    // Note management
    private var activeNotes: [UInt8: NoteInfo] = [:]
    private var envelopeTimers: [UInt8: Timer] = [:]
    private let maxVoices = 6 // Voice limiting
    
    struct NoteInfo {
        let oscillators: [AVAudioPlayerNode]
        let noteMixer: AVAudioMixerNode
        let filter: AVAudioUnitEQ
        let envelope: ADSREnvelope
        let filterEnvelope: ADSREnvelope
    }
    
    @Published var isEngineRunning = false
    @Published var volume: Float = 0.5
    
    // Oscillator settings
    var osc1Settings = OscillatorSettings(waveform: .sine, level: 1.0)
    var osc2Settings = OscillatorSettings(waveform: .sawtooth, pitch: 12.0, level: 0.0)
    var osc3Settings = OscillatorSettings(waveform: .sawtooth, pitch: -12.0, level: 0.0)
    
    // ADSR settings
    var adsrSettings = ADSRSettings()
    var filterAdsrSettings = ADSRSettings(attack: 0.1, decay: 0.3, sustain: 0.7, release: 0.5)
    
    // Filter settings
    var filterSettings = FilterSettings()
    
    // Computed properties for easy access
    var activeNoteCount: Int { return activeNotes.count }
    var totalOscillatorCount: Int { return activeNotes.count * 3 }
    
    init() {
        audioEngine = AVAudioEngine()
        mixer = audioEngine.mainMixerNode
        setupAudioEngine()
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, 
                                       mode: .default, 
                                       options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            
            try audioSession.setPreferredIOBufferDuration(0.002)
            try audioSession.setPreferredSampleRate(44100)
            try audioSession.setActive(true)
            
            mixer.outputVolume = 1.0
            audioEngine.prepare()
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isEngineRunning = true
            }
            
            print("✓ Audio engine started successfully")
            
        } catch {
            print("❌ Failed to setup audio engine: \(error)")
            DispatchQueue.main.async {
                self.isEngineRunning = false
            }
        }
    }
    
    // MARK: - Note Management
    
    func playNote(_ note: UInt8, velocity: UInt8) {
        guard isEngineRunning else { return }
        
        // Voice limiting: if we're at max voices, remove the oldest note
        if activeNotes.count >= maxVoices && activeNotes[note] == nil {
            // Find the oldest note to remove (simple FIFO)
            if let oldestNote = activeNotes.keys.first {
                print("🔄 Voice limit reached (\(maxVoices)), removing note \(oldestNote)")
                removeNote(oldestNote)
            }
        }
        
        // Stop existing note first
        if activeNotes[note] != nil {
            stopNote(note)
        }
        
        let frequency = noteToFrequency(note: note)
        let amplitude = Float(velocity) / 127.0
        
        // Create note mixer
        let noteMixer = AVAudioMixerNode()
        audioEngine.attach(noteMixer)
        
        // Create filter
        let filter = createFilter()
        audioEngine.attach(filter)
        
        // Connect: Note Mixer -> Filter -> Main Mixer
        audioEngine.connect(noteMixer, to: filter, format: nil)
        audioEngine.connect(filter, to: mixer, format: nil)
        
        // Create oscillators
        var oscillators: [AVAudioPlayerNode] = []
        let oscSettings = [osc1Settings, osc2Settings, osc3Settings]
        
        for (index, settings) in oscSettings.enumerated() {
            guard settings.level > 0 else { continue } // Skip silent oscillators
            
            let oscillator = AVAudioPlayerNode()
            audioEngine.attach(oscillator)
            
            // Calculate frequency for this oscillator
            let pitchMultiplier = powf(2.0, settings.pitch / 12.0)
            let detuneMultiplier = powf(2.0, settings.detune / 1200.0)
            let oscFrequency = frequency * pitchMultiplier * detuneMultiplier
            
            // Create audio buffer
            if let buffer = createOscillatorBuffer(
                frequency: oscFrequency,
                amplitude: amplitude * settings.level,
                waveform: settings.waveform,
                pulseWidth: settings.pulseWidth
            ) {
                audioEngine.connect(oscillator, to: noteMixer, format: buffer.format)
                oscillator.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                oscillator.play()
                oscillators.append(oscillator)
            }
        }
        
        // Create envelopes
        let envelope = ADSREnvelope(settings: adsrSettings)
        let filterEnvelope = ADSREnvelope(settings: filterAdsrSettings)
        envelope.noteOn()
        filterEnvelope.noteOn()
        
        // Store note info
        let noteInfo = NoteInfo(
            oscillators: oscillators,
            noteMixer: noteMixer,
            filter: filter,
            envelope: envelope,
            filterEnvelope: filterEnvelope
        )
        activeNotes[note] = noteInfo
        
        // Start envelope timer
        startEnvelopeTimer(for: note)
        
        print("🎵 Playing note \(note) with \(oscillators.count) oscillators")
    }
    
    func stopNote(_ note: UInt8) {
        guard let noteInfo = activeNotes[note] else { return }
        
        // Start release phase
        noteInfo.envelope.noteOff()
        noteInfo.filterEnvelope.noteOff()
        
        print("🔇 Released note \(note)")
    }
    
    private func removeNote(_ note: UInt8) {
        guard let noteInfo = activeNotes[note] else { return }
        
        // Stop timer
        envelopeTimers[note]?.invalidate()
        envelopeTimers.removeValue(forKey: note)
        
        // Stop and detach oscillators
        for oscillator in noteInfo.oscillators {
            oscillator.stop()
            audioEngine.detach(oscillator)
        }
        
        // Detach mixer and filter
        audioEngine.detach(noteInfo.noteMixer)
        audioEngine.detach(noteInfo.filter)
        
        // Remove from active notes
        activeNotes.removeValue(forKey: note)
        
        print("🗑️ Completely removed note \(note)")
    }
    
    func stopAllNotes() {
        for note in Array(activeNotes.keys) {
            removeNote(note)
        }
        print("🛑 Stopped all notes")
    }
    
    // MARK: - Envelope Management
    
    private func startEnvelopeTimer(for note: UInt8) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
                guard let self = self,
                      let noteInfo = self.activeNotes[note] else {
                    timer.invalidate()
                    self?.envelopeTimers.removeValue(forKey: note)
                    return
                }
                
                let envelopeLevel = noteInfo.envelope.currentLevel()
                let filterLevel = noteInfo.filterEnvelope.currentLevel()
                
                // Update volume
                self.updateNoteVolume(note: note, envelopeLevel: envelopeLevel)
                
                // Update filter
                self.updateNoteFilter(note: note, envelopeLevel: filterLevel)
                
                // Remove note if envelope is finished
                if noteInfo.envelope.currentLevel() <= 0.001 && 
                   noteInfo.filterEnvelope.currentLevel() <= 0.001 {
                    timer.invalidate()
                    self.envelopeTimers.removeValue(forKey: note)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.removeNote(note)
                    }
                }
            }
            
            self.envelopeTimers[note] = timer
        }
    }
    
    private func updateNoteVolume(note: UInt8, envelopeLevel: Float) {
        guard let noteInfo = activeNotes[note] else { return }
        
        let finalVolume = envelopeLevel * volume
        for oscillator in noteInfo.oscillators {
            oscillator.volume = finalVolume
        }
        
        print("🔊 Note \(note): envelope=\(String(format: "%.3f", envelopeLevel)), final=\(String(format: "%.3f", finalVolume))")
    }
    
    private func updateNoteFilter(note: UInt8, envelopeLevel: Float) {
        guard let noteInfo = activeNotes[note] else { return }
        
        // Apply filter envelope to cutoff frequency
        let baseFreq = filterSettings.cutoff
        let envAmount = filterSettings.envelopeAmount
        let modulation = envAmount * envelopeLevel * 5000.0 // Scale envelope to frequency range
        let modulatedFreq = max(20.0, min(20000.0, baseFreq + modulation))
        
        noteInfo.filter.bands[0].frequency = modulatedFreq
    }
    
    
    // MARK: - Audio Buffer Creation
    
    private func createOscillatorBuffer(frequency: Float, amplitude: Float, waveform: Waveform, pulseWidth: Float) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let cycleLength = sampleRate / Double(frequency)
        let frameCount = AVAudioFrameCount(round(cycleLength))
        let actualFrameCount = max(frameCount, 64)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: actualFrameCount) else {
            return nil
        }
        
        buffer.frameLength = actualFrameCount
        
        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            return nil
        }
        
        let frameLength = Int(actualFrameCount)
        
        for frame in 0..<frameLength {
            let phase = Float(frame) / Float(frameLength)
            let sample = generateWaveformSample(phase: phase, waveform: waveform, amplitude: amplitude, pulseWidth: pulseWidth)
            leftChannel[frame] = sample
            rightChannel[frame] = sample
        }
        
        return buffer
    }
    
    private func generateWaveformSample(phase: Float, waveform: Waveform, amplitude: Float, pulseWidth: Float) -> Float {
        switch waveform {
        case .sine:
            return amplitude * sinf(2.0 * Float.pi * phase)
        case .triangle:
            if phase < 0.5 {
                return amplitude * (4.0 * phase - 1.0)
            } else {
                return amplitude * (3.0 - 4.0 * phase)
            }
        case .sawtooth:
            return amplitude * (2.0 * phase - 1.0)
        case .square:
            return amplitude * (phase < 0.5 ? 1.0 : -1.0)
        case .pulse:
            return amplitude * (phase < pulseWidth ? 1.0 : -1.0)
        case .noise:
            return amplitude * (Float.random(in: -1.0...1.0))
        }
    }
    
    private func createFilter() -> AVAudioUnitEQ {
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        let band = filter.bands[0]
        
        switch filterSettings.type {
        case .lowpass:
            band.filterType = .lowPass
        case .highpass:
            band.filterType = .highPass
        case .bandpass:
            band.filterType = .bandPass
        }
        
        band.frequency = filterSettings.cutoff
        band.bandwidth = filterSettings.resonance
        band.gain = 0
        band.bypass = false
        
        return filter
    }
    
    private func noteToFrequency(note: UInt8) -> Float {
        let noteNumber = Float(note)
        return 440.0 * powf(2.0, (noteNumber - 69.0) / 12.0)
    }
    
    // MARK: - Settings Update Methods
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
        mixer.outputVolume = newVolume
        
        // Update all active notes immediately
        for (note, noteInfo) in activeNotes {
            let envelopeLevel = noteInfo.envelope.currentLevel()
            updateNoteVolume(note: note, envelopeLevel: envelopeLevel)
        }
    }
    
    func updateADSRSettings(_ settings: ADSRSettings) {
        adsrSettings = settings
        print("🎛️ Updated ADSR: A=\(settings.attack)s D=\(settings.decay)s S=\(settings.sustain) R=\(settings.release)s")
        
        // Update all active envelopes
        for (_, noteInfo) in activeNotes {
            noteInfo.envelope.updateSettings(settings)
        }
    }
    
    func updateFilterADSRSettings(_ settings: ADSRSettings) {
        filterAdsrSettings = settings
        print("🎛️ Updated Filter ADSR: A=\(settings.attack)s D=\(settings.decay)s S=\(settings.sustain) R=\(settings.release)s")
        
        // Update all active filter envelopes
        for (_, noteInfo) in activeNotes {
            noteInfo.filterEnvelope.updateSettings(settings)
        }
    }
    
    func updateFilterSettings(_ settings: FilterSettings) {
        filterSettings = settings
        print("🔧 Updated Filter: \(settings.type.rawValue) \(settings.cutoff)Hz Q=\(settings.resonance) Env=\(settings.envelopeAmount)")
        
        // Update all active filters
        for (note, noteInfo) in activeNotes {
            let band = noteInfo.filter.bands[0]
            
            switch settings.type {
            case .lowpass:
                band.filterType = .lowPass
            case .highpass:
                band.filterType = .highPass
            case .bandpass:
                band.filterType = .bandPass
            }
            
            band.frequency = settings.cutoff
            band.bandwidth = settings.resonance
            
            // Apply current filter envelope
            let filterLevel = noteInfo.filterEnvelope.currentLevel()
            updateNoteFilter(note: note, envelopeLevel: filterLevel)
        }
    }
    
    func updateOscillatorSettings(_ oscIndex: Int, _ settings: OscillatorSettings) {
        switch oscIndex {
        case 0: osc1Settings = settings
        case 1: osc2Settings = settings
        case 2: osc3Settings = settings
        default: break
        }
        
        print("🎚️ Updated OSC\(oscIndex + 1): \(settings.waveform.rawValue) Level=\(settings.level)")
        
        // For now, just print - full regeneration would be complex
        // In a real implementation, you'd regenerate oscillator buffers here
    }
    
    func restartEngine() {
        print("🔄 Restarting audio engine...")
        stopAllNotes()
        audioEngine.stop()
        
        DispatchQueue.main.async {
            self.isEngineRunning = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupAudioEngine()
        }
    }
}
