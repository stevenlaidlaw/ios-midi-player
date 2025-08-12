import Foundation

struct ADSRSettings {
    var attack: Float = 0.1    // seconds
    var decay: Float = 0.4     // seconds
    var sustain: Float = 0.7   // level (0.0 - 1.0)
    var release: Float = 0.8   // seconds
}

class ADSREnvelope {
    private var settings: ADSRSettings
    private var startTime: Date?
    private var releaseTime: Date?
    private var isReleasing = false
    private var releaseStartLevel: Float = 0.0 // Capture the level when release starts
    
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
        // Capture the current level before starting release
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
            // Release phase: start from the captured level when release began
            let releaseElapsed = Float(Date().timeIntervalSince(releaseTime))
            let releaseProgress = min(releaseElapsed / settings.release, 1.0)
            return releaseStartLevel * (1.0 - releaseProgress)
        } else {
            // Attack, Decay, or Sustain phase
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
    
    private func getLevelAtSustain() -> Float {
        let totalAD = settings.attack + settings.decay
        return getLevelAtTime(totalAD)
    }
}

class EnvelopeEngine {
    private var envelopes: [UInt8: ADSREnvelope] = [:]
    private var filterEnvelopes: [UInt8: ADSREnvelope] = [:]
    private var envelopeTimers: [UInt8: Timer] = [:]
    private var filterEnvelopeTimers: [UInt8: Timer] = [:]
    
    var adsrSettings = ADSRSettings()
    var filterAdsrSettings = ADSRSettings(attack: 0.1, decay: 0.3, sustain: 0.7, release: 0.5)
    
    func createEnvelopesForNote(_ note: UInt8) {
        let envelope = ADSREnvelope(settings: adsrSettings)
        let filterEnvelope = ADSREnvelope(settings: filterAdsrSettings)
        envelopes[note] = envelope
        filterEnvelopes[note] = filterEnvelope
        envelope.noteOn()
        filterEnvelope.noteOn()
        print("🎛️ Created envelopes for note \(note): A=\(adsrSettings.attack), D=\(adsrSettings.decay), S=\(adsrSettings.sustain), R=\(adsrSettings.release)")
    }
    
    func startEnvelopeTimer(for note: UInt8, volumeUpdateCallback: @escaping (Float) -> Void) {
        print("⏱️ Starting envelope timer for note \(note)")
        
        // Ensure timer is scheduled on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update envelope volume at 100Hz for smooth transitions
            let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
                guard let self = self,
                      let envelope = self.envelopes[note] else {
                    print("⚠️ Envelope timer stopped for note \(note) - envelope not found")
                    timer.invalidate()
                    self?.envelopeTimers.removeValue(forKey: note)
                    return
                }
                
                let envelopeLevel = envelope.currentLevel()
                volumeUpdateCallback(envelopeLevel)
            }
            
            self.envelopeTimers[note] = timer
            print("✅ Envelope timer started for note \(note)")
        }
    }
    
    func startFilterEnvelopeTimer(for note: UInt8, filterUpdateCallback: @escaping (ADSREnvelope) -> Void) {
        // Ensure timer is scheduled on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update filter envelope at 100Hz for smooth transitions
            let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
                guard let self = self,
                      let envelope = self.filterEnvelopes[note] else {
                    timer.invalidate()
                    self?.filterEnvelopeTimers.removeValue(forKey: note)
                    return
                }
                
                filterUpdateCallback(envelope)
            }
            
            self.filterEnvelopeTimers[note] = timer
        }
    }
    
    func releaseNote(_ note: UInt8) {
        envelopes[note]?.noteOff()
        filterEnvelopes[note]?.noteOff()
        
        // Stop the envelope update timers
        envelopeTimers[note]?.invalidate()
        envelopeTimers.removeValue(forKey: note)
        filterEnvelopeTimers[note]?.invalidate()
        filterEnvelopeTimers.removeValue(forKey: note)
    }
    
    func removeEnvelopesForNote(_ note: UInt8) {
        envelopes.removeValue(forKey: note)
        filterEnvelopes.removeValue(forKey: note)
        envelopeTimers[note]?.invalidate()
        envelopeTimers.removeValue(forKey: note)
        filterEnvelopeTimers[note]?.invalidate()
        filterEnvelopeTimers.removeValue(forKey: note)
    }
    
    func getEnvelope(for note: UInt8) -> ADSREnvelope? {
        return envelopes[note]
    }
    
    func getFilterEnvelope(for note: UInt8) -> ADSREnvelope? {
        return filterEnvelopes[note]
    }
    
    func getCurrentEnvelopeLevel(for note: UInt8) -> Float {
        return envelopes[note]?.currentLevel() ?? 0.0
    }
    
    func updateADSRSettings(_ newSettings: ADSRSettings) {
        adsrSettings = newSettings
        
        // Update all existing envelopes with new settings
        for (_, envelope) in envelopes {
            envelope.updateSettings(newSettings)
        }
    }
    
    func updateFilterADSRSettings(_ newSettings: ADSRSettings) {
        filterAdsrSettings = newSettings
        
        // Update all existing filter envelopes with new settings
        for (_, envelope) in filterEnvelopes {
            envelope.updateSettings(newSettings)
        }
    }
    
    func stopAllEnvelopes() {
        // Stop all envelope timers
        for timer in envelopeTimers.values {
            timer.invalidate()
        }
        for timer in filterEnvelopeTimers.values {
            timer.invalidate()
        }
        envelopeTimers.removeAll()
        filterEnvelopeTimers.removeAll()
        
        envelopes.removeAll()
        filterEnvelopes.removeAll()
    }
}
