import AVFoundation

enum FilterType: String, CaseIterable {
    case lowPass = "Low Pass"
    case highPass = "High Pass"
    case bandPass = "Band Pass"
}

struct FilterSettings {
    var type: FilterType = .lowPass
    var frequency: Float = 1000.0  // Hz
    var resonance: Float = 1.0     // Q factor
    var envelopeAmount: Float = 0.0 // -1.0 to 1.0
}

class FilterEngine {
    private var filters: [UInt8: AVAudioUnitEQ] = [:]
    private var audioEngine: AVAudioEngine
    
    var filterSettings = FilterSettings()
    
    init(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
    }
    
    func createFilter(for note: UInt8) -> AVAudioUnitEQ {
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        
        // Set up the filter band based on current settings
        updateFilterBand(filter, settings: filterSettings)
        
        filters[note] = filter
        
        return filter
    }
    
    func removeFilter(for note: UInt8) {
        filters.removeValue(forKey: note)
    }
    
    func updateFilterSettings(_ newSettings: FilterSettings) {
        filterSettings = newSettings
        
        // Update all existing filters with new settings
        for (_, filter) in filters {
            updateFilterBand(filter, settings: newSettings)
        }
    }
    
    func updateFilterWithEnvelope(for note: UInt8, envelope: ADSREnvelope) {
        guard let filter = filters[note] else { return }
        
        let envelopeLevel = envelope.currentLevel()
        let modulatedFrequency = calculateModulatedFrequency(
            baseFrequency: filterSettings.frequency,
            envelopeLevel: envelopeLevel,
            envelopeAmount: filterSettings.envelopeAmount
        )
        
        // Create a temporary settings object with modulated frequency
        var modulatedSettings = filterSettings
        modulatedSettings.frequency = modulatedFrequency
        
        updateFilterBand(filter, settings: modulatedSettings)
    }
    
    private func updateFilterBand(_ filter: AVAudioUnitEQ, settings: FilterSettings) {
        let band = filter.bands[0]
        
        switch settings.type {
        case .lowPass:
            band.filterType = .lowPass
        case .highPass:
            band.filterType = .highPass
        case .bandPass:
            band.filterType = .bandPass
        }
        
        band.frequency = settings.frequency
        band.bandwidth = settings.resonance
        band.gain = 0 // We're using this as a filter, not EQ
        band.bypass = false
    }
    
    private func calculateModulatedFrequency(baseFrequency: Float, envelopeLevel: Float, envelopeAmount: Float) -> Float {
        // Envelope amount ranges from -1.0 to 1.0
        // When positive, envelope opens the filter (higher frequency)
        // When negative, envelope closes the filter (lower frequency)
        
        // Calculate frequency modulation in octaves
        let modulationOctaves = envelopeAmount * envelopeLevel * 4.0 // Up to 4 octaves of modulation
        
        // Convert octaves to frequency multiplier (2^octaves)
        let frequencyMultiplier = pow(2.0, modulationOctaves)
        
        // Apply modulation and clamp to reasonable range
        let modulatedFreq = baseFrequency * frequencyMultiplier
        return max(20.0, min(20000.0, modulatedFreq)) // Clamp to audible range
    }
    
    func getAllFilters() -> [AVAudioUnitEQ] {
        return Array(filters.values)
    }
    
    func stopAllFilters() {
        filters.removeAll()
    }
}
