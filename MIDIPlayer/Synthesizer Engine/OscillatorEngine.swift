import Foundation
import AVFoundation

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

class OscillatorEngine {
    private var audioEngine: AVAudioEngine
    private var oscillators: [UInt8: [AVAudioPlayerNode]] = [:]  // Array of 3 oscillators per note
    private var audioBuffers: [UInt8: [AVAudioPCMBuffer]] = [:] // Array of 3 buffers per note
    private var noteMixers: [UInt8: AVAudioMixerNode] = [:]     // One mixer per note
    
    var osc1Settings = OscillatorSettings(waveform: .sawtooth, level: 1.0)
    var osc2Settings = OscillatorSettings(waveform: .sawtooth, detune: 20.0, level: 1.0)
    var osc3Settings = OscillatorSettings(waveform: .sawtooth, detune: -12.0, level: 1.0)
    
    init(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
    }
    
    func createOscillatorsForNote(_ note: UInt8, baseFrequency: Float, velocityAmplitude: Float, filter: AVAudioUnitEQ, finalMixer: AVAudioMixerNode) -> [AVAudioPlayerNode] {
        // Create arrays for the three oscillators
        var noteOscillators: [AVAudioPlayerNode] = []
        var noteBuffers: [AVAudioPCMBuffer] = []
        
        let oscillatorSettings = [osc1Settings, osc2Settings, osc3Settings]
        
        // Create a mixer for this note's oscillators
        let noteMixer = AVAudioMixerNode()
        audioEngine.attach(noteMixer)
        
        // Connect: Note Mixer -> Filter -> Final Mixer
        audioEngine.attach(filter)
        audioEngine.connect(noteMixer, to: filter, format: nil)
        audioEngine.connect(filter, to: finalMixer, format: nil)
        
        // Create three oscillators
        for (oscIndex, oscSettings) in oscillatorSettings.enumerated() {
            // Calculate frequency for this oscillator (base + pitch + detune)
            let pitchMultiplier = powf(2.0, oscSettings.pitch / 12.0) // Semitone adjustment
            let detuneMultiplier = powf(2.0, oscSettings.detune / 1200.0) // Cent adjustment
            let oscFrequency = baseFrequency * pitchMultiplier * detuneMultiplier
            
            // Calculate amplitude for this oscillator
            let oscAmplitude = velocityAmplitude * oscSettings.level
            
            // Create DCO buffer for this oscillator
            guard let buffer = createDCOBuffer(
                frequency: oscFrequency, 
                amplitude: oscAmplitude, 
                waveform: oscSettings.waveform,
                pulseWidth: oscSettings.pulseWidth
            ) else {
                print("✗ Failed to create DCO buffer for oscillator \(oscIndex + 1) of note \(note)")
                continue
            }
            
            // Create player node
            let playerNode = AVAudioPlayerNode()
            
            // Attach and connect: Player -> Note Mixer
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: noteMixer, format: buffer.format)
            
            // Store references
            noteOscillators.append(playerNode)
            noteBuffers.append(buffer)
            
            // Schedule buffer with looping
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            
            // Start playing immediately (volume will be controlled by envelope)
            playerNode.play()
        }
        
        // Store references
        oscillators[note] = noteOscillators
        audioBuffers[note] = noteBuffers
        noteMixers[note] = noteMixer
        
        return noteOscillators
    }
    
    func stopOscillatorsForNote(_ note: UInt8) {
        guard let playerNodes = oscillators[note] else { return }
        
        // Stop and detach all oscillators
        for playerNode in playerNodes {
            playerNode.stop()
            audioEngine.detach(playerNode)
        }
        
        // Remove and detach the note mixer
        if let noteMixer = noteMixers[note] {
            audioEngine.detach(noteMixer)
        }
        
        oscillators.removeValue(forKey: note)
        audioBuffers.removeValue(forKey: note)
        noteMixers.removeValue(forKey: note)
    }
    
    func updateVolumeForNote(_ note: UInt8, envelopeLevel: Float, masterVolume: Float) {
        guard let playerNodes = oscillators[note] else { return }
        
        let finalVolume = envelopeLevel * masterVolume
        for playerNode in playerNodes {
            playerNode.volume = finalVolume
        }
        
        // Debug logging (always log for now)
        print("🔊 Note \(note): envelope=\(String(format: "%.3f", envelopeLevel)), master=\(String(format: "%.3f", masterVolume)), final=\(String(format: "%.3f", finalVolume))")
    }
    
    func updateVolumeForAllNotes(masterVolume: Float, envelopeLevelProvider: (UInt8) -> Float) {
        for (note, playerNodes) in oscillators {
            let envelopeLevel = envelopeLevelProvider(note)
            for playerNode in playerNodes {
                playerNode.volume = envelopeLevel * masterVolume
            }
        }
    }
    
    func hasNote(_ note: UInt8) -> Bool {
        return oscillators[note] != nil
    }
    
    func regenerateAllOscillators() {
        // Regenerate buffers for all currently playing notes with new oscillator settings
        // This is a simplified approach - in practice we'd want to avoid audio glitches
        for (note, playerNodes) in oscillators {
            let baseFrequency = noteToFrequency(note: note)
            let velocityAmplitude = Float(1.0) // Use current amplitude
            
            let oscillatorSettings = [osc1Settings, osc2Settings, osc3Settings]
            
            for (oscIndex, oscSettings) in oscillatorSettings.enumerated() {
                guard oscIndex < playerNodes.count else { continue }
                
                // Calculate frequency for this oscillator
                let pitchMultiplier = powf(2.0, oscSettings.pitch / 12.0)
                let detuneMultiplier = powf(2.0, oscSettings.detune / 1200.0)
                let oscFrequency = baseFrequency * pitchMultiplier * detuneMultiplier
                
                // Calculate amplitude for this oscillator
                let oscAmplitude = velocityAmplitude * oscSettings.level
                
                guard let newBuffer = createDCOBuffer(
                    frequency: oscFrequency,
                    amplitude: oscAmplitude,
                    waveform: oscSettings.waveform,
                    pulseWidth: oscSettings.pulseWidth
                ) else {
                    continue
                }
                
                let playerNode = playerNodes[oscIndex]
                
                // Stop current playback
                playerNode.stop()
                
                // Update buffer
                audioBuffers[note]?[oscIndex] = newBuffer
                
                // Reschedule with new buffer
                playerNode.scheduleBuffer(newBuffer, at: nil, options: .loops, completionHandler: nil)
                playerNode.play()
            }
        }
        
        print("🔄 Regenerated oscillators for \(oscillators.count) active notes")
    }
    
    func stopAllOscillators() {
        // Stop and detach all oscillators
        for (_, playerNodes) in oscillators {
            for playerNode in playerNodes {
                playerNode.volume = 0.0
                playerNode.stop()
                audioEngine.detach(playerNode)
            }
        }
        
        // Stop and detach all note mixers
        for (_, noteMixer) in noteMixers {
            audioEngine.detach(noteMixer)
        }
        
        oscillators.removeAll()
        audioBuffers.removeAll()
        noteMixers.removeAll()
    }
    
    var activeNoteCount: Int {
        return oscillators.count
    }
    
    var totalOscillatorCount: Int {
        return oscillators.values.reduce(0) { $0 + $1.count }
    }
    
    private func noteToFrequency(note: UInt8) -> Float {
        // MIDI note to frequency conversion
        // A4 (note 69) = 440 Hz
        let noteNumber = Float(note)
        return 440.0 * powf(2.0, (noteNumber - 69.0) / 12.0)
    }
    
    private func createDCOBuffer(frequency: Float, amplitude: Float, waveform: Waveform, pulseWidth: Float = 0.5) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        
        // Calculate the exact number of samples for one complete cycle
        let cycleLength = sampleRate / Double(frequency)
        let frameCount = AVAudioFrameCount(round(cycleLength))
        
        // Ensure minimum buffer size for very high frequencies
        let minFrameCount: AVAudioFrameCount = 64
        let actualFrameCount = max(frameCount, minFrameCount)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: actualFrameCount) else {
            print("✗ Failed to create DCO format or buffer")
            return nil
        }
        
        buffer.frameLength = actualFrameCount
        
        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            print("✗ Failed to get DCO channel data")
            return nil
        }
        
        let frameLength = Int(actualFrameCount)
        
        // Generate waveform based on selected type
        for frame in 0..<frameLength {
            let phase = Float(frame) / Float(frameLength) // 0 to 1
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
            // Triangle wave: linear ramp up then down
            if phase < 0.5 {
                return amplitude * (4.0 * phase - 1.0)
            } else {
                return amplitude * (3.0 - 4.0 * phase)
            }
            
        case .sawtooth:
            // Sawtooth wave: linear ramp from -1 to 1
            return amplitude * (2.0 * phase - 1.0)
            
        case .square:
            // Square wave: +1 for first half, -1 for second half
            return amplitude * (phase < 0.5 ? 1.0 : -1.0)
            
        case .pulse:
            // Pulse wave: +1 for pulseWidth%, -1 for remainder
            return amplitude * (phase < pulseWidth ? 1.0 : -1.0)
            
        case .noise:
            // White noise: random values between -1 and 1
            return amplitude * (Float.random(in: -1.0...1.0))
        }
    }
}
