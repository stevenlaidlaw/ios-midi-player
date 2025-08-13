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
    @State private var holdMode = false
    
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
    
    // Helper functions for hold mode
    func playChordWithHold(notes: [UInt8]) {
        if holdMode {
            // Stop all currently playing notes before playing the new chord
            midiController.sendAllNotesOff()
        }
        // Play the new chord
        midiController.playChord(notes: notes)
    }
    
    func stopChordWithHold(notes: [UInt8]) {
        if !holdMode {
            // Only stop if not in hold mode
            midiController.stopChord(notes: notes)
        }
        // In hold mode, we don't stop - the chord continues until next chord is played
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
                
                Text("MIDI Controller Only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            // Chord Keyboard View
            VStack(spacing: 15) {
                    // Key, Scale, and MIDI Controls Row
                    VStack(spacing: 10) {
                        HStack(spacing: 15) {
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
                            }

                            Spacer()
                
                            // Hold toggle
                            Toggle("Hold", isOn: $holdMode)
                                .font(.caption)
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                                .scaleEffect(0.8)

                            // Velocity control
                            IntegerCircularSlider(
                                value: Binding(
                                    get: { Double(midiController.velocity) },
                                    set: { midiController.velocity = ($0) }
                                ),
                                range: 1...127,
                                label: "VELOCITY",
                                unit: ""
                            )
                            
                            // MIDI Channel picker
                            VStack {
                                Text("CHANNEL")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                
                                Picker("MIDI Channel", selection: Binding(
                                    get: { Int(midiController.channel) },
                                    set: { midiController.channel = UInt8($0) }
                                )) {
                                    ForEach(0..<16) { channel in
                                        Text("\(channel + 1)").tag(channel)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            
                            // PANIC button
                            Button("PANIC") {
                                midiController.panic()
                            }
                            .buttonStyle(.borderedProminent)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .font(.caption)
                        }
                    }
                    
                    // Chord buttons in three rows (three octaves)
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
                                    isSecondInversion: isSecondInversionPressed,
                                    playChordAction: playChordWithHold,
                                    stopChordAction: stopChordWithHold
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
                                    isSecondInversion: isSecondInversionPressed,
                                    playChordAction: playChordWithHold,
                                    stopChordAction: stopChordWithHold
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
                                    isSecondInversion: isSecondInversionPressed,
                                    playChordAction: playChordWithHold,
                                    stopChordAction: stopChordWithHold
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
                                title: "1st Inv",
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
                                title: "2nd Inv",
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
        }
        .onAppear {
            midiController.setupMIDI()
        }
        .onChange(of: holdMode) { newValue in
            // When hold mode is turned off, stop all currently playing notes
            if !newValue {
                midiController.sendAllNotesOff()
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

// MARK: - Simple Controls

struct IntegerCircularSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 1) {
            // Label
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .frame(height: 20)
            
            // Simple circular display
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                
                // Value circle
                Circle()
                    .trim(from: 0, to: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 0.75)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-225))
                
                // Center display
                VStack(spacing: 1) {
                    Text("\(Int(value))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 40, height: 40)
            .onTapGesture {
                // Simple tap to cycle through values
                let newValue = value + 10
                value = newValue > range.upperBound ? range.lowerBound : newValue
            }
        }
        .frame(width: 47)
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
    let playChordAction: ([UInt8]) -> Void
    let stopChordAction: ([UInt8]) -> Void
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
                        playChordAction(chord.notes)
                        
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    stopChordAction(chord.notes)
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
