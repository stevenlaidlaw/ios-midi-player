import SwiftUI

// MARK: - Music Theory Structures

enum Key: String, CaseIterable {
    case c = "C"
    case cSharp = "C#"
    case d = "D"
    case dSharp = "D#"
    case e = "E"
    case f = "F"
    case fSharp = "F#"
    case g = "G"
    case gSharp = "G#"
    case a = "A"
    case aSharp = "A#"
    case b = "B"
    
    var midiNote: UInt8 {
        switch self {
        case .c: return 48  // C3 (low octave)
        case .cSharp: return 49
        case .d: return 50
        case .dSharp: return 51
        case .e: return 52
        case .f: return 53
        case .fSharp: return 54
        case .g: return 55
        case .gSharp: return 56
        case .a: return 57
        case .aSharp: return 58
        case .b: return 59
        }
    }
    
    // Get MIDI note for specific octave (0 = low, 1 = middle, 2 = high)
    func midiNote(octave: Int) -> UInt8 {
        return midiNote + UInt8(octave * 12)
    }
}

enum Scale: String, CaseIterable {
    case major = "Major"
    case minor = "Minor"
    
    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11] // W-W-H-W-W-W-H
        case .minor: return [0, 2, 3, 5, 7, 8, 10] // W-H-W-W-H-W-W
        }
    }
    
    var chordQualities: [ChordQuality] {
        switch self {
        case .major: return [.major, .minor, .minor, .major, .major, .minor, .diminished]
        case .minor: return [.minor, .diminished, .major, .minor, .minor, .major, .major]
        }
    }
    
    var romanNumerals: [String] {
        switch self {
        case .major: return ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
        case .minor: return ["i", "ii°", "III", "iv", "v", "VI", "VII"]
        }
    }
}

enum ChordQuality {
    case major, minor, diminished
    
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        }
    }
}

struct ChordInfo {
    let romanNumeral: String
    let quality: ChordQuality
    let rootNote: UInt8
    let notes: [UInt8]
    let noteNames: [String]
}

struct ContentView: View {
    @StateObject private var midiController = MIDIController()
    @State private var selectedTab = 0 // 0 = MIDI Keyboard, 1 = Synth Controls
    @State private var selectedKey: Key = .c
    @State private var selectedScale: Scale = .major
    @State private var is7thPressed = false
    @State private var is9thPressed = false
    @State private var isFirstInversionPressed = false
    @State private var isSecondInversionPressed = false
    
    // Generate chords based on selected key and scale across three octaves
    var chords: [ChordInfo] {
        let scaleIntervals = selectedScale.intervals
        let chordQualities = selectedScale.chordQualities
        let romanNumerals = selectedScale.romanNumerals
        
        var allChords: [ChordInfo] = []
        
        // Generate chords for three octaves (low, middle, high)
        for octave in 0..<3 {
            let rootMidi = selectedKey.midiNote(octave: octave)
            
            let octaveChords = (0..<7).map { degree in
                let scaleNote = rootMidi + UInt8(scaleIntervals[degree])
                let quality = chordQualities[degree]
                var chordIntervals = quality.intervals
                
                // Add 7th if selected
                if is7thPressed {
                    let seventhInterval: Int
                    switch quality {
                    case .major:
                        // Major 7th for major chords (11 semitones)
                        seventhInterval = 11
                    case .minor:
                        // Minor 7th for minor chords (10 semitones)
                        seventhInterval = 10
                    case .diminished:
                        // Diminished 7th for diminished chords (9 semitones)
                        seventhInterval = 9
                    }
                    chordIntervals.append(seventhInterval)
                }
                
                // Add 9th if selected (always major 9th = 14 semitones = octave + major 2nd)
                if is9thPressed {
                    chordIntervals.append(14)
                }
                
                let chordNotes = chordIntervals.map { interval in
                    scaleNote + UInt8(interval)
                }
                
                // Apply inversions
                var finalChordNotes = chordNotes
                if isFirstInversionPressed && chordNotes.count >= 3 {
                    // First inversion: move root up an octave
                    finalChordNotes = Array(chordNotes.dropFirst()) + [chordNotes[0] + 12]
                } else if isSecondInversionPressed && chordNotes.count >= 3 {
                    // Second inversion: move root and third up an octave
                    if chordNotes.count >= 3 {
                        finalChordNotes = Array(chordNotes.dropFirst(2)) + [chordNotes[0] + 12, chordNotes[1] + 12]
                    }
                }
                
                let noteNames = finalChordNotes.map { note in
                    noteToName(note)
                }
                
                // Add octave indicator to roman numeral for higher octaves
                let octaveRomanNumeral = octave == 0 ? romanNumerals[degree] : 
                                        octave == 1 ? romanNumerals[degree] + "'" :
                                        romanNumerals[degree] + "''"
                
                return ChordInfo(
                    romanNumeral: octaveRomanNumeral,
                    quality: quality,
                    rootNote: scaleNote,
                    notes: finalChordNotes,
                    noteNames: noteNames
                )
            }
            
            allChords.append(contentsOf: octaveChords)
        }
        
        return allChords
    }
    
    func noteToName(_ midiNote: UInt8) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return noteNames[Int(midiNote) % 12]
    }
    
    var body: some View {
        VStack(spacing: 5) {
            // Status indicator
            HStack {
                Circle()
                    .fill(midiController.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(midiController.isConnected ? "MIDI Connected" : "MIDI Disconnected")
                    .font(.caption)
                
                Spacer()
                
                Circle()
                    .fill(midiController.synthEngine.isEngineRunning ? Color.blue : Color.gray)
                    .frame(width: 12, height: 12)
                Text(midiController.synthEngine.isEngineRunning ? "Synth Ready" : "Synth Offline")
                    .font(.caption)
            }
            .padding()
            
            // Segmented Control
            Picker("View", selection: $selectedTab) {
                Text("Chord Keyboard").tag(0)
                Text("Synth Controls").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Content based on selected tab
            if selectedTab == 0 {
                // Chord Keyboard View
                VStack(spacing: 15) {
                    // Key and Scale Selection
                    VStack(spacing: 10) {
                        HStack(spacing: 20) {
                            // Key picker
                            VStack {
                                Text("Key")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                
                                Picker("Key", selection: $selectedKey) {
                                    ForEach(Key.allCases, id: \.self) { key in
                                        Text(key.rawValue).tag(key)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 100)
                            }
                            
                            // Scale picker
                            VStack {
                                Text("Scale")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                
                                Picker("Scale", selection: $selectedScale) {
                                    ForEach(Scale.allCases, id: \.self) { scale in
                                        Text(scale.rawValue).tag(scale)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 100)
                            }
                        }
                    }
                    
                    // Chord buttons in three rows (three octaves)
                    VStack(spacing: 8) {
                        // High octave label and buttons (row 3)
                        VStack(spacing: 5) {
                            HStack(spacing: 5) {
                                ForEach(Array(chords[14..<21].enumerated()), id: \.offset) { index, chord in
                                    ChordButton(
                                        chord: chord,
                                        midiController: midiController,
                                        add7th: is7thPressed,
                                        add9th: is9thPressed,
                                        isFirstInversion: isFirstInversionPressed,
                                        isSecondInversion: isSecondInversionPressed
                                    )
                                    .frame(width: 90, height: 90)
                                }
                            }
                            HStack(spacing: 5) {
                                ForEach(Array(chords[7..<14].enumerated()), id: \.offset) { index, chord in
                                    ChordButton(
                                        chord: chord,
                                        midiController: midiController,
                                        add7th: is7thPressed,
                                        add9th: is9thPressed,
                                        isFirstInversion: isFirstInversionPressed,
                                        isSecondInversion: isSecondInversionPressed
                                    )
                                    .frame(width: 90, height: 90)
                                }
                            }
                            HStack(spacing: 5) {
                                ForEach(Array(chords[0..<7].enumerated()), id: \.offset) { index, chord in
                                    ChordButton(
                                        chord: chord,
                                        midiController: midiController,
                                        add7th: is7thPressed,
                                        add9th: is9thPressed,
                                        isFirstInversion: isFirstInversionPressed,
                                        isSecondInversion: isSecondInversionPressed
                                    )
                                    .frame(width: 90, height: 90)
                                }
                            }


                            HStack(spacing: 5) {
                                // 7th button
                                ExtensionButton(
                                    title: "7th",
                                    isPressed: $is7thPressed
                                )
                                .frame(width: 90, height: 90)
                                
                                // 9th button  
                                ExtensionButton(
                                    title: "9th",
                                    isPressed: $is9thPressed
                                )
                                .frame(width: 90, height: 90)
                                
                                // First inversion button
                                ExtensionButton(
                                    title: "1st",
                                    isPressed: $isFirstInversionPressed,
                                    onPress: {
                                        // If activating first inversion, deactivate second inversion
                                        if !isFirstInversionPressed {
                                            isSecondInversionPressed = false
                                        }
                                    },
                                    color: .purple
                                )
                                .frame(width: 90, height: 90)
                                
                                // Second inversion button
                                ExtensionButton(
                                    title: "2nd",
                                    isPressed: $isSecondInversionPressed,
                                    onPress: {
                                        // If activating second inversion, deactivate first inversion
                                        if !isSecondInversionPressed {
                                            isFirstInversionPressed = false
                                        }
                                    },
                                    color: .purple
                                )
                                .frame(width: 90, height: 90)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Basic MIDI Controls
                    VStack(spacing: 10) {
                        Text("MIDI CONTROLS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            // Velocity knob
                            IntegerCircularSlider(
                                value: Binding(
                                    get: { Double(midiController.velocity) },
                                    set: { midiController.velocity = ($0) }
                                ),
                                range: 1...127,
                                label: "VELOCITY",
                                unit: ""
                            )
                            
                            // Volume knob
                            CircularSlider(
                                value: Binding(
                                    get: { Double(midiController.synthEngine.volume * 100) },
                                    set: { midiController.synthEngine.setVolume(Float($0 / 100.0)) }
                                ),
                                range: 0...100,
                                label: "VOLUME",
                                unit: "%",
                                step: 1,
                                formatString: "%.0f"
                            )
                            
                            // Voice count display
                            VStack {
                                Text("VOICES")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("\(midiController.synthEngine.activeNoteCount)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(20)
                                
                                Text("/ 6")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // PANIC button
                        Button("PANIC - Stop All Sound") {
                            midiController.panic()
                            
                            // Haptic feedback for panic button
                            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                            impactFeedback.impactOccurred()
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(.white)
                        .background(Color.red)
                        .font(.headline)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            } else {
                // Synth Controls View
                ScrollView {
                    synthControlsView
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
            }
        }
        .onAppear {
            midiController.setupMIDI()
        }
    }
    
    // MARK: - Synth Controls View
    
    private var synthControlsView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Internal Synthesizer")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if midiController.synthEngine.activeNoteCount > 0 {
                    Text("\(midiController.synthEngine.activeNoteCount) notes (\(midiController.synthEngine.totalOscillatorCount) oscillators)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Three DCO Oscillator Controls
            VStack {
                // OSC 1
                OscillatorControlView(
                    title: "OSC 1",
                    settings: Binding(
                        get: { midiController.synthEngine.osc1Settings },
                        set: { midiController.synthEngine.osc1Settings = $0 }
                    ),
                    synthEngine: midiController.synthEngine,
                    oscIndex: 0
                )
                
                // OSC 2
                OscillatorControlView(
                    title: "OSC 2",
                    settings: Binding(
                        get: { midiController.synthEngine.osc2Settings },
                        set: { midiController.synthEngine.osc2Settings = $0 }
                    ),
                    synthEngine: midiController.synthEngine,
                    oscIndex: 1
                )
                
                // OSC 3
                OscillatorControlView(
                    title: "OSC 3",
                    settings: Binding(
                        get: { midiController.synthEngine.osc3Settings },
                        set: { midiController.synthEngine.osc3Settings = $0 }
                    ),
                    synthEngine: midiController.synthEngine,
                    oscIndex: 2
                )
            }
            
            Divider()
            
            // ADSR Controls - Hardware Synth Style Layout
            VStack(spacing: 5) {
                Text("AMP ENVELOPE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // ADSR knobs in a row like hardware synths
                HStack(spacing: 15) {
                    TimeCircularSlider(
                        value: Binding(
                            get: { Double(midiController.synthEngine.adsrSettings.attack) },
                            set: { newValue in
                                var settings = midiController.synthEngine.adsrSettings
                                settings.attack = Float(newValue)
                                midiController.synthEngine.updateADSRSettings(settings)
                            }
                        ),
                        label: "ATTACK",
                        maxTime: 2.0
                    )
                    
                    TimeCircularSlider(
                        value: Binding(
                            get: { Double(midiController.synthEngine.adsrSettings.decay) },
                            set: { newValue in
                                var settings = midiController.synthEngine.adsrSettings
                                settings.decay = Float(newValue)
                                midiController.synthEngine.updateADSRSettings(settings)
                            }
                        ),
                        label: "DECAY",
                        maxTime: 2.0
                    )
                    
                    CircularSlider(
                        value: Binding(
                            get: { Double(midiController.synthEngine.adsrSettings.sustain) * 100 },
                            set: { newValue in
                                var settings = midiController.synthEngine.adsrSettings
                                settings.sustain = Float(newValue / 100.0)
                                midiController.synthEngine.updateADSRSettings(settings)
                            }
                        ),
                        range: 0...100,
                        label: "SUSTAIN",
                        unit: "%",
                        step: 1,
                        formatString: "%.0f"
                    )
                    
                    TimeCircularSlider(
                        value: Binding(
                            get: { Double(midiController.synthEngine.adsrSettings.release) },
                            set: { newValue in
                                var settings = midiController.synthEngine.adsrSettings
                                settings.release = Float(newValue)
                                midiController.synthEngine.updateADSRSettings(settings)
                            }
                        ),
                        label: "RELEASE",
                        maxTime: 3.0
                    )
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 10) {
                // Filter Section
                VStack(spacing: 5) {
                    Text("FILTER")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    // Filter type dropdown
                    HStack {
                        Text("TYPE:")
                            .font(.caption2)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Picker("Filter Type", selection: Binding(
                            get: { midiController.synthEngine.filterSettings.type },
                            set: { newType in
                                var newSettings = midiController.synthEngine.filterSettings
                                newSettings.type = newType
                                midiController.synthEngine.updateFilterSettings(newSettings)
                            }
                        )) {
                            ForEach(FilterType.allCases, id: \.self) { filterType in
                                Text(filterType.rawValue).tag(filterType)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    // Filter controls
                    HStack(spacing: 5) {
                        CircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterSettings.cutoff) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterSettings
                                    settings.cutoff = Float(newValue)
                                    midiController.synthEngine.updateFilterSettings(settings)
                                }
                            ),
                            range: 20...20000,
                            label: "CUTOFF",
                            unit: "Hz",
                            step: 10,
                            formatString: "%.0f"
                        )
                        
                        CircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterSettings.resonance) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterSettings
                                    settings.resonance = Float(newValue)
                                    midiController.synthEngine.updateFilterSettings(settings)
                                }
                            ),
                            range: 0.1...10.0,
                            label: "RES",
                            unit: "",
                            step: 0.1,
                            formatString: "%.1f"
                        )
                        
                        CircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterSettings.envelopeAmount * 100) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterSettings
                                    settings.envelopeAmount = Float(newValue / 100.0)
                                    midiController.synthEngine.updateFilterSettings(settings)
                                }
                            ),
                            range: -100...100,
                            label: "ENV\nAMT",
                            unit: "%",
                            step: 1,
                            formatString: "%.0f"
                        )
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Filter ADSR Controls
                VStack(spacing: 5) {
                    Text("FILTER ENVELOPE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    // Filter ADSR knobs in a row
                    HStack(spacing: 5) {
                        TimeCircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterAdsrSettings.attack) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterAdsrSettings
                                    settings.attack = Float(newValue)
                                    midiController.synthEngine.updateFilterADSRSettings(settings)
                                }
                            ),
                            label: "ATTACK",
                            maxTime: 2.0
                        )
                        
                        TimeCircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterAdsrSettings.decay) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterAdsrSettings
                                    settings.decay = Float(newValue)
                                    midiController.synthEngine.updateFilterADSRSettings(settings)
                                }
                            ),
                            label: "DECAY",
                            maxTime: 2.0
                        )
                        
                        CircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterAdsrSettings.sustain) * 100 },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterAdsrSettings
                                    settings.sustain = Float(newValue / 100.0)
                                    midiController.synthEngine.updateFilterADSRSettings(settings)
                                }
                            ),
                            range: 0...100,
                            label: "SUSTAIN",
                            unit: "%",
                            step: 1,
                            formatString: "%.0f"
                        )
                        
                        TimeCircularSlider(
                            value: Binding(
                                get: { Double(midiController.synthEngine.filterAdsrSettings.release) },
                                set: { newValue in
                                    var settings = midiController.synthEngine.filterAdsrSettings
                                    settings.release = Float(newValue)
                                    midiController.synthEngine.updateFilterADSRSettings(settings)
                                }
                            ),
                            label: "RELEASE",
                            maxTime: 3.0
                        )
                    }
                    .padding(.horizontal)
                }
            }
            
            // PANIC button and engine status
            VStack(spacing: 10) {
                Button("PANIC - Stop All Sound") {
                    midiController.panic()
                    
                    // Haptic feedback for panic button
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.white)
                .background(Color.red)
                .font(.headline)
                
                // Restart synth engine button (for debugging)
                if !midiController.synthEngine.isEngineRunning {
                    Button("Restart Synth Engine") {
                        midiController.restartSynthEngine()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                    .font(.caption)
                }
                
                Text("Playing internal synthesizer only (MIDI broadcasting disabled for low latency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Debug buttons
                HStack {
                    Button("List MIDI Destinations") {
                        midiController.listMIDIDestinations()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                    .font(.caption)
                    
                    Button("Debug State") {
                        midiController.debugMIDIState()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                    .font(.caption)
                }
            }
        }
    }
}

struct MIDIButton: View {
    let title: String
    let note: Int
    let midiController: MIDIController
    let isSharp: Bool
    
    var body: some View {
        MIDIButtonUIKit(
            title: title,
            note: note,
            midiController: midiController,
            isSharp: isSharp
        )
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }
}

// Pure UIKit button to completely avoid SwiftUI gesture system
struct MIDIButtonUIKit: UIViewRepresentable {
    let title: String
    let note: Int
    let midiController: MIDIController
    let isSharp: Bool
    
    func makeUIView(context: Context) -> MIDIUIButton {
        let button = MIDIUIButton()
        button.setup(title: title, note: note, midiController: midiController, isSharp: isSharp)
        return button
    }
    
    func updateUIView(_ uiView: MIDIUIButton, context: Context) {
        // Update if needed
    }
}

class MIDIUIButton: UIView {
    private var titleLabel: UILabel!
    private var note: Int = 0
    private var midiController: MIDIController?
    private var isSharp: Bool = false
    private var isPressed: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        // Create label
        titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        // Setup corner radius and initial appearance
        layer.cornerRadius = 12
        clipsToBounds = true
        
        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 6
        layer.masksToBounds = false
        
        updateAppearance()
    }
    
    func setup(title: String, note: Int, midiController: MIDIController, isSharp: Bool) {
        self.note = note
        self.midiController = midiController
        self.isSharp = isSharp
        titleLabel.text = title
        updateAppearance()
    }
    
    private func updateAppearance() {
        if isPressed {
            backgroundColor = isSharp ? UIColor.gray : UIColor.systemBlue.withAlphaComponent(0.8)
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: 2)
        } else {
            backgroundColor = isSharp ? UIColor.black : UIColor.white
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        
        titleLabel.textColor = isSharp ? UIColor.white : UIColor.black
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        if !isPressed {
            isPressed = true
            midiController?.sendNoteOn(note: UInt8(note))
            
            // Haptic feedback in background
            DispatchQueue.global(qos: .userInitiated).async {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        if isPressed {
            isPressed = false
            midiController?.sendNoteOff(note: UInt8(note))
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        if isPressed {
            isPressed = false
            midiController?.sendNoteOff(note: UInt8(note))
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Oscillator Control Component

struct OscillatorControlView: View {
    let title: String
    @Binding var settings: OscillatorSettings
    let synthEngine: SynthEngine
    let oscIndex: Int
    
    var body: some View {
        HStack {
            // Oscillator title
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Waveform and basic controls row
            HStack {
                Picker("Waveform", selection: $settings.waveform) {
                    ForEach(Waveform.allCases, id: \.self) { waveform in
                        Text(waveform.rawValue).tag(waveform)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: settings.waveform) { _ in
                    synthEngine.updateOscillatorSettings(oscIndex, settings)
                }
                
                Spacer()
                
                // Level
                CircularSlider(
                    value: Binding(
                        get: { Double(settings.level * 100) },
                        set: { 
                            settings.level = Float($0 / 100.0)
                            synthEngine.updateOscillatorSettings(oscIndex, settings)
                        }
                    ),
                    range: 0...100,
                    label: "LEVEL",
                    unit: "%",
                    step: 1,
                    formatString: "%.0f"
                )
                
                // Pitch
                CircularSlider(
                    value: Binding(
                        get: { Double(settings.pitch) },
                        set: { 
                            settings.pitch = Float($0)
                            synthEngine.updateOscillatorSettings(oscIndex, settings)
                        }
                    ),
                    range: -24...24,
                    label: "PITCH",
                    unit: "st",
                    step: 1,
                    formatString: "%.0f"
                )
                
                // Detuning
                CircularSlider(
                    value: Binding(
                        get: { Double(settings.detune) },
                        set: { 
                            settings.detune = Float($0)
                            synthEngine.updateOscillatorSettings(oscIndex, settings)
                        }
                    ),
                    range: -100...100,
                    label: "DETUNE",
                    unit: "¢",
                    step: 1,
                    formatString: "%.0f"
                )
                
                // Pulse Width (only for pulse wave)
                if settings.waveform == .pulse {
                    CircularSlider(
                        value: Binding(
                            get: { Double(settings.pulseWidth * 100) },
                            set: { 
                                settings.pulseWidth = Float($0 / 100.0)
                                synthEngine.updateOscillatorSettings(oscIndex, settings)
                            }
                        ),
                        range: 10...90,
                        label: "PULSE",
                        unit: "%",
                        step: 1,
                        formatString: "%.0f"
                    )
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.2), value: settings.waveform)
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Circular Slider Components

struct CircularSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let unit: String
    let step: Double
    let formatString: String
    
    @State private var isDragging = false
    @State private var startValue: Double = 0
    @State private var displayValue: Double = 0
    
    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        label: String,
        unit: String = "",
        step: Double = 0.01,
        formatString: String = "%.2f"
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.unit = unit
        self.step = step
        self.formatString = formatString
    }
    
    private var angle: Double {
        let currentValue = isDragging ? displayValue : value
        let normalizedValue = (currentValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        // Map to 270 degrees of rotation (-135° to +135°)
        return -135 + (normalizedValue * 270)
    }
    
    private var trackValue: Double {
        return isDragging ? displayValue : value
    }
    
    var body: some View {
        VStack(spacing: 1) {
            // Label
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .frame(height: 20)
            
            // Circular knob
            ZStack {
                // Background track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                    .rotationEffect(.degrees(-225))
                
                // Active track
                Circle()
                    .trim(from: 0, to: CGFloat((trackValue - range.lowerBound) / (range.upperBound - range.lowerBound)) * 0.75)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-225))
                
                // Knob body
                Circle()
                    .frame(width: 33, height: 33)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                
                // Indicator line
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 10)
                    .offset(y: -11)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 40, height: 40)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        if !isDragging {
                            isDragging = true
                            startValue = value
                            displayValue = value
                            // Haptic feedback on start
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                        
                        // Calculate vertical drag distance for up/down control (negative for up = increase)
                        let dragDistance = -gestureValue.translation.height
                        let sensitivity: Double = 100.0 // Pixels needed for full range
                        
                        // Calculate new value based on horizontal drag from start position
                        let dragRatio = dragDistance / sensitivity
                        let valueRange = range.upperBound - range.lowerBound
                        let deltaValue = dragRatio * valueRange
                        
                        let newValue = startValue + deltaValue
                        let steppedValue = round(newValue / step) * step
                        let clampedValue = max(range.lowerBound, min(range.upperBound, steppedValue))
                        
                        // Update display value immediately for real-time visual feedback
                        displayValue = clampedValue
                        // Update the actual binding value for real-time parameter changes
                        value = clampedValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Haptic feedback on end
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
            )
            
            // Value display
            Text(String(format: formatString, isDragging ? displayValue : value) + unit)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(height: 15)
        }
        .frame(width: 47)
    }
}

// Specialized circular sliders for different parameter types
struct PercentageCircularSlider: View {
    @Binding var value: Double
    let label: String
    
    var body: some View {
        CircularSlider(
            value: $value,
            range: 0...1,
            label: label,
            unit: "%",
            step: 0.01,
            formatString: "%.0f"
        )
    }
}

struct TimeCircularSlider: View {
    @Binding var value: Double
    let label: String
    let maxTime: Double
    
    var body: some View {
        CircularSlider(
            value: $value,
            range: 0.01...maxTime,
            label: label,
            unit: "s",
            step: 0.01,
            formatString: "%.2f"
        )
    }
}

struct IntegerCircularSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let unit: String
    
    var body: some View {
        CircularSlider(
            value: $value,
            range: range,
            label: label,
            unit: unit,
            step: 1,
            formatString: "%.0f"
        )
    }
}

// MARK: - Chord Button Component

struct ChordButton: View {
    let chord: ChordInfo
    let midiController: MIDIController
    let add7th: Bool
    let add9th: Bool
    let isFirstInversion: Bool
    let isSecondInversion: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                // Roman numeral
                Text(chord.romanNumeral)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isPressed ? .white : .primary)
                
                // Note names
                VStack(spacing: 2) {
                    Text(chord.noteNames.joined(separator: " - "))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isPressed ? .white : .secondary)
                        .multilineTextAlignment(.center)
                    
                    // Chord quality indicator
                    Text(chordQualityText(chord.quality))
                        .font(.caption2)
                        .foregroundColor(isPressed ? .white : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80) // Use minHeight instead of fixed height
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isPressed ? Color.blue : Color(.systemGray5))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        midiController.playChord(notes: chord.notes)
                        
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    midiController.stopChord(notes: chord.notes)
                }
        )
    }
    
    private func chordQualityText(_ quality: ChordQuality) -> String {
        var baseText: String
        switch quality {
        case .major: baseText = "Major"
        case .minor: baseText = "minor"
        case .diminished: baseText = "diminished"
        }
        
        // Add extension and inversion indicators
        var modifiers: [String] = []
        if add7th { modifiers.append("7") }
        if add9th { modifiers.append("9") }
        if isFirstInversion { modifiers.append("1st inv") }
        if isSecondInversion { modifiers.append("2nd inv") }
        
        if !modifiers.isEmpty {
            baseText += " (" + modifiers.joined(separator: ", ") + ")"
        }
        
        return baseText
    }
}

// MARK: - Extension Button Component

struct ExtensionButton: View {
    let title: String
    @Binding var isPressed: Bool
    let onPress: (() -> Void)?
    let color: Color
    
    init(title: String, isPressed: Binding<Bool>, onPress: (() -> Void)? = nil, color: Color = .orange) {
        self.title = title
        self._isPressed = isPressed
        self.onPress = onPress
        self.color = color
    }
    
    var body: some View {
        Button(action: {}) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 80) // Match chord button height
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isPressed ? color : Color(.systemGray5))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        // Call the onPress callback before setting isPressed
                        onPress?()
                        isPressed = true
                        
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
