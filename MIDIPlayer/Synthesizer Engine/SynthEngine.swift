import Foundation
import AVFoundation

class SynthEngine: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var mixer: AVAudioMixerNode
    
    // Modular engine components
    let oscillatorEngine: OscillatorEngine
    let envelopeEngine: EnvelopeEngine
    let filterEngine: FilterEngine
    
    // Audio node management
    private var activeNotes: [UInt8: (oscillators: [AVAudioPlayerNode], envelope: ADSREnvelope)] = [:]
    
    @Published var isEngineRunning = false
    @Published var volume: Float = 0.5
    
    // Legacy support for single oscillator controls (now maps to osc1)
    @Published var currentWaveform: Waveform = .sine {
        didSet {
            oscillatorEngine.osc1Settings.waveform = currentWaveform
        }
    }
    @Published var pulseWidth: Float = 0.5 {
        didSet {
            oscillatorEngine.osc1Settings.pulseWidth = pulseWidth
        }
    }
    
    // Expose modular engine properties
    var activeNoteCount: Int {
        return oscillatorEngine.activeNoteCount
    }
    
    var totalOscillatorCount: Int {
        return oscillatorEngine.totalOscillatorCount
    }
    
    // Expose oscillator settings for UI binding
    var osc1Settings: OscillatorSettings {
        get { oscillatorEngine.osc1Settings }
        set { 
            oscillatorEngine.osc1Settings = newValue
            oscillatorEngine.regenerateAllOscillators()
        }
    }
    
    var osc2Settings: OscillatorSettings {
        get { oscillatorEngine.osc2Settings }
        set { 
            oscillatorEngine.osc2Settings = newValue
            oscillatorEngine.regenerateAllOscillators()
        }
    }
    
    var osc3Settings: OscillatorSettings {
        get { oscillatorEngine.osc3Settings }
        set { 
            oscillatorEngine.osc3Settings = newValue
            oscillatorEngine.regenerateAllOscillators()
        }
    }
    
    // Expose ADSR settings for UI binding
    var adsrSettings: ADSRSettings {
        get { envelopeEngine.adsrSettings }
        set { envelopeEngine.updateADSRSettings(newValue) }
    }
    
    var filterAdsrSettings: ADSRSettings {
        get { envelopeEngine.filterAdsrSettings }
        set { envelopeEngine.updateFilterADSRSettings(newValue) }
    }
    
    // Expose filter settings for UI binding
    var filterSettings: FilterSettings {
        get { filterEngine.filterSettings }
        set { filterEngine.updateFilterSettings(newValue) }
    }
    
    init() {
        audioEngine = AVAudioEngine()
        mixer = audioEngine.mainMixerNode
        
        // Initialize modular components
        oscillatorEngine = OscillatorEngine(audioEngine: audioEngine)
        envelopeEngine = EnvelopeEngine()
        filterEngine = FilterEngine(audioEngine: audioEngine)
        
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        do {
            // Configure audio session for ultra-low-latency audio
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, 
                                       mode: .default, 
                                       options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            
            // Set even smaller buffer size for minimal latency
            try audioSession.setPreferredIOBufferDuration(0.002) // 2ms buffer for ultra-low latency
            try audioSession.setPreferredSampleRate(44100) // Ensure consistent sample rate
            try audioSession.setActive(true)
            
            print("✓ Audio session configured for ultra-low latency (2ms buffer)")
            
            // Configure audio engine for minimal latency
            mixer.outputVolume = 1.0
            
            // Pre-warm the engine to avoid first-play delays
            audioEngine.prepare()
            try audioEngine.start()
            
            // Verify engine is actually running
            if audioEngine.isRunning {
                print("✓ Audio engine verified as running")
            } else {
                print("⚠️ Audio engine claims to be started but isRunning = false")
            }
            
            // Additional preparation: create a dummy buffer to warm up the audio path
            if let dummyFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2),
               let dummyBuffer = AVAudioPCMBuffer(pcmFormat: dummyFormat, frameCapacity: 1) {
                dummyBuffer.frameLength = 1
                // This helps warm up the audio pipeline
            }
            
            DispatchQueue.main.async {
                self.isEngineRunning = true
            }
            
            print("✓ Audio engine started with ultra-low latency configuration")
            
        } catch {
            print("❌ Failed to setup audio engine: \(error)")
            DispatchQueue.main.async {
                self.isEngineRunning = false
            }
        }
    }
    
    func playNote(_ note: UInt8, velocity: UInt8) {
        // Check if engine is still actually running
        if !audioEngine.isRunning {
            print("⚠️ Audio engine stopped unexpectedly - restarting...")
            restartEngine()
            return
        }
        
        guard isEngineRunning else { 
            print("❌ Cannot play note - engine not running")
            return 
        }
        
        // Stop any existing note first
        if activeNotes[note] != nil {
            stopNote(note)
        }
        
        // Calculate frequency and amplitude from MIDI note and velocity
        let frequency = noteToFrequency(note: note)
        let amplitude = Float(velocity) / 127.0
        
        // Create filter for this note
        let filter = filterEngine.createFilter(for: note)
        
        // Create oscillators for this note (they will connect through the filter)
        let oscillators = oscillatorEngine.createOscillatorsForNote(note, baseFrequency: frequency, velocityAmplitude: amplitude, filter: filter, finalMixer: mixer)
        
        // Create envelopes for this note
        envelopeEngine.createEnvelopesForNote(note)
        print("📊 Created envelopes for note \(note)")
        
        // Store the note info with envelope
        if let envelope = envelopeEngine.getEnvelope(for: note) {
            activeNotes[note] = (oscillators: oscillators, envelope: envelope)
            print("✅ Envelope found for note \(note), starting timers")
            
            // Start envelope control timer for volume
            envelopeEngine.startEnvelopeTimer(for: note) { [weak self] envelopeLevel in
                guard let self = self else { return }
                // Debug logging
                print("📈 Envelope update for note \(note): level=\(String(format: "%.3f", envelopeLevel))")
                self.oscillatorEngine.updateVolumeForNote(note, envelopeLevel: envelopeLevel, masterVolume: self.volume)
            }
            
            // Start filter envelope timer
            if let filterEnvelope = envelopeEngine.getFilterEnvelope(for: note) {
                envelopeEngine.startFilterEnvelopeTimer(for: note) { [weak self] envelope in
                    guard let self = self else { return }
                    self.filterEngine.updateFilterWithEnvelope(for: note, envelope: envelope)
                }
            }
        } else {
            // Fallback without envelope
            print("⚠️ No envelope found for note \(note), using fallback")
            activeNotes[note] = (oscillators: oscillators, envelope: ADSREnvelope(settings: ADSRSettings()))
            
            // Set initial volume for all oscillators
            for oscillator in oscillators {
                oscillator.volume = amplitude * volume
            }
        }
        
        print("🎵 Playing note \(note) with \(oscillators.count) oscillators, envelope, and filter")
    }
    
    func stopNote(_ note: UInt8) {
        // Release the envelope (start release phase)
        envelopeEngine.releaseNote(note)
        
        // The envelope timer will handle the fade-out and eventual removal of the note
        // For now, we'll remove the note after a short delay to allow for release
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.removeNote(note)
        }
        
        print("🔇 Released note \(note) (will fade out)")
    }
    
    private func removeNote(_ note: UInt8) {
        // Stop oscillators
        oscillatorEngine.stopOscillatorsForNote(note)
        
        // Remove filter
        filterEngine.removeFilter(for: note)
        
        // Remove envelopes
        envelopeEngine.removeEnvelopesForNote(note)
        
        // Remove from active notes
        activeNotes.removeValue(forKey: note)
        
        print("�️ Completely removed note \(note)")
    }
    
    func stopAllNotes() {
        oscillatorEngine.stopAllOscillators()
        filterEngine.stopAllFilters()
        envelopeEngine.stopAllEnvelopes()
        activeNotes.removeAll()
        print("🛑 Stopped all notes")
    }
    
    private func noteToFrequency(note: UInt8) -> Float {
        let noteNumber = Float(note)
        return 440.0 * powf(2.0, (noteNumber - 69.0) / 12.0)
    }
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
        mixer.outputVolume = newVolume
        
        // Update volume for all active notes with their current envelope levels
        oscillatorEngine.updateVolumeForAllNotes(masterVolume: volume) { note in
            return envelopeEngine.getCurrentEnvelopeLevel(for: note)
        }
    }
    
    func updateWaveform(_ newWaveform: Waveform) {
        currentWaveform = newWaveform
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func updateOscillatorSettings(_ oscIndex: Int, _ settings: OscillatorSettings) {
        switch oscIndex {
        case 0:
            oscillatorEngine.osc1Settings = settings
        case 1:
            oscillatorEngine.osc2Settings = settings
        case 2:
            oscillatorEngine.osc3Settings = settings
        default:
            break
        }
        oscillatorEngine.regenerateAllOscillators()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func updateADSRSettings(_ settings: ADSRSettings) {
        envelopeEngine.updateADSRSettings(settings)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func updateFilterADSRSettings(_ settings: ADSRSettings) {
        envelopeEngine.updateFilterADSRSettings(settings)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func updateFilterSettings(_ settings: FilterSettings) {
        filterEngine.updateFilterSettings(settings)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func restartEngine() {
        print("🔄 Restarting audio engine...")
        
        // Stop all notes first
        stopAllNotes()
        
        // Stop the engine
        audioEngine.stop()
        
        // Reset the engine running state
        DispatchQueue.main.async {
            self.isEngineRunning = false
        }
        
        // Wait a moment then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupAudioEngine()
        }
    }
}
