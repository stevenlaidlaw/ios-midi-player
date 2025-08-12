# iOS MIDI Player - Modular Synthesizer Architecture

## Overview
The SynthEngine has been successfully modularized into separate, focused classes to improve code organization, maintainability, and readability. The monolithic SynthEngine class has been split into four distinct components, all organized in the `SynthesizerEngine/` folder for better project structure.

## Project Structure
```
MIDIPlayer/
├── MIDIPlayerApp.swift          # App entry point
├── ContentView.swift            # Main UI with piano keyboard and controls
├── MIDIController.swift         # MIDI handling (legacy, now disabled)
└── SynthesizerEngine/           # Modular synthesizer components
    ├── SynthEngine.swift        # Main coordinator
    ├── OscillatorEngine.swift   # Audio generation
    ├── EnvelopeEngine.swift     # Time-based modulation
    └── FilterEngine.swift       # Audio processing
```

## Architecture Components

### 1. SynthEngine.swift (Main Coordinator)
**Purpose**: Main synthesizer coordinator and public interface
**Responsibilities**:
- Audio engine initialization and configuration
- Note playback coordination between all modules
- Volume management and master controls
- Legacy API compatibility
- Audio session configuration for ultra-low latency (2ms buffer)

**Key Public Methods**:
- `playNote(note:velocity:)` - Starts note playback using all modules
- `stopNote(note:)` - Handles note release with envelope decay
- `panic()` - Emergency stop all notes
- `updateOscillatorSettings(_:_:)` - Update individual oscillator parameters
- `updateADSRSettings(_:)` - Update envelope settings
- `updateFilterSettings(_:)` - Update filter parameters

### 2. OscillatorEngine.swift (Audio Generation)
**Location**: `SynthesizerEngine/OscillatorEngine.swift`
**Purpose**: Manages three-oscillator DCO generation and audio buffers
**Responsibilities**:
- DCO waveform generation (Sine, Triangle, Sawtooth, Square, Pulse, Noise)
- Three-oscillator polyphony per note
- Individual oscillator pitch (-24 to +24 semitones), detune (-100 to +100 cents), and level control
- Real-time buffer regeneration when settings change
- Audio node lifecycle management

**Key Features**:
- Per-note three-oscillator mixing
- Precise frequency calculation with pitch and detune
- Efficient waveform sample generation
- Real-time parameter updates without audio dropouts

### 3. EnvelopeEngine.swift (Time-based Modulation)
**Location**: `SynthesizerEngine/EnvelopeEngine.swift`
**Purpose**: Manages ADSR envelopes for amplitude and filter modulation
**Responsibilities**:
- Dual ADSR envelope system (amplitude + filter)
- Per-note envelope lifecycle management
- Timer-based envelope updates at 100Hz for smooth transitions
- Proper release behavior with level capture
- Envelope setting propagation to active notes

**Key Features**:
- Accurate ADSR envelope calculation
- Independent amplitude and filter envelopes
- Smooth envelope transitions
- Proper release phase handling

### 4. FilterEngine.swift (Audio Processing)
**Location**: `SynthesizerEngine/FilterEngine.swift`
**Purpose**: Manages real-time filtering with envelope modulation
**Responsibilities**:
- AVAudioUnitEQ-based filtering (Low Pass, High Pass, Band Pass)
- Filter envelope modulation with configurable amount
- Per-note filter management
- Real-time frequency and resonance updates
- Filter parameter validation and clamping

**Key Features**:
- Real-time filter cutoff modulation
- Envelope-controlled filter sweeps
- Multiple filter types with resonance control
- Frequency range validation (20Hz - 20kHz)

## Benefits of Modular Architecture

### Code Organization
- **Single Responsibility**: Each class has a focused, well-defined purpose
- **Separation of Concerns**: Audio generation, time-based modulation, and filtering are isolated
- **Maintainability**: Easier to modify individual components without affecting others
- **Testability**: Each module can be tested independently

### Performance
- **Efficient Resource Management**: Each engine manages its own resources
- **Optimized Updates**: Only affected modules regenerate when settings change
- **Memory Management**: Clear ownership and lifecycle for audio resources

### Extensibility
- **Easy Feature Addition**: New synthesis features can be added as separate engines
- **Plugin Architecture**: Modules can be easily swapped or extended
- **Parameter Isolation**: Settings changes don't create cross-dependencies

## API Compatibility
The refactoring maintains full backward compatibility with the existing ContentView interface. All public methods and properties remain unchanged, ensuring the UI continues to work without modifications.

## Technical Implementation Details

### Inter-Module Communication
- **Callback-based Updates**: Envelope engine uses callbacks to notify volume and filter changes
- **Settings Propagation**: Main SynthEngine coordinates settings updates across modules
- **Resource Sharing**: Audio engine reference shared safely between modules

### Memory Management
- **Weak References**: Timer callbacks use weak self to prevent retain cycles
- **Resource Cleanup**: Each module properly cleans up its resources on deinit
- **Automatic Cleanup**: Failed note creation properly cleans up partial state

### Thread Safety
- **Main Queue Updates**: UI-related property changes dispatched to main queue
- **Timer Management**: Envelope timers properly invalidated to prevent leaks
- **Audio Thread Safety**: Audio buffer operations designed for real-time thread

## Migration Summary
- ✅ **OscillatorEngine**: Extracted DCO generation and three-oscillator management (`SynthesizerEngine/OscillatorEngine.swift`)
- ✅ **EnvelopeEngine**: Separated ADSR envelope system with dual envelope support (`SynthesizerEngine/EnvelopeEngine.swift`)
- ✅ **FilterEngine**: Isolated filter processing and envelope modulation (`SynthesizerEngine/FilterEngine.swift`)
- ✅ **SynthEngine**: Refactored as coordinator with maintained public API (`SynthesizerEngine/SynthEngine.swift`)
- ✅ **Organized Structure**: All synthesizer components moved to dedicated `SynthesizerEngine/` folder
- ✅ **Zero Breaking Changes**: Full backward compatibility maintained
- ✅ **Performance Maintained**: Same ultra-low latency audio performance
- ✅ **Feature Parity**: All existing functionality preserved

The modular architecture provides a solid foundation for future synthesizer enhancements while maintaining the professional-grade performance and ultra-low latency characteristics of the original implementation.
