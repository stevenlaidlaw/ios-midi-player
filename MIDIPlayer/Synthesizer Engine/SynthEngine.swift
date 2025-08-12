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
        guard isEngineRunning else { return }
        
        // Calculate frequency and amplitude from MIDI note and velocity
        let frequency = noteToFrequency(note: note)
        let amplitude = Float(velocity) / 127.0
        
        // Create oscillators for this note
        let oscillators = oscillatorEngine.createOscillatorsForNote(note, baseFrequency: frequency, velocityAmplitude: amplitude, noteMixer: mixer)
        
        // Store the note info (simplified - no envelope for now)
        activeNotes[note] = (oscillators: oscillators, envelope: ADSREnvelope(settings: ADSRSettings()))
        
        // Connect and start oscillators
        for oscillator in oscillators {
            oscillator.play()
        }
        
        print("🎵 Playing note \(note) with \(oscillators.count) oscillators")
    }
    
    func stopNote(_ note: UInt8) {
        oscillatorEngine.stopOscillatorsForNote(note)
        activeNotes.removeValue(forKey: note)
        print("🔇 Stopped note \(note)")
    }
    
    func stopAllNotes() {
        oscillatorEngine.stopAllOscillators()
        activeNotes.removeAll()
        print("� Stopped all notes")
    }
    
    private func noteToFrequency(note: UInt8) -> Float {
        let noteNumber = Float(note)
        return 440.0 * powf(2.0, (noteNumber - 69.0) / 12.0)
    }
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
        mixer.outputVolume = newVolume
        
        // Update oscillator engine volume
        oscillatorEngine.updateVolumeForAllNotes(masterVolume: volume) { note in
            // For now, return a fixed envelope level since we simplified the envelope system
            return 1.0
        }
    }
    
    func updateWaveform(_ newWaveform: Waveform) {
        currentWaveform = newWaveform
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
