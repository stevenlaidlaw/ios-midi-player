# iOS MIDI Player

A simple iOS app that sends MIDI data to control external instruments. The app features an on-screen keyboard with buttons that send MIDI Note On messages when pressed and MIDI Note Off messages when released.

## Features

- **Touch-responsive MIDI keyboard**: 12 buttons representing a chromatic octave (C to B)
- **Real-time MIDI output**: Sends MIDI Note On/Off messages to connected MIDI devices
- **Customizable controls**:
  - Adjustable velocity (1-127)
  - Selectable MIDI channel (1-16)
- **Visual feedback**: 
  - Button press animations
  - Connection status indicator
  - Haptic feedback on button press
- **Piano-style layout**: White and black keys with appropriate styling

## Technical Details

- Built with SwiftUI and Core MIDI
- Uses `MIDIClientCreate` and `MIDIOutputPortCreate` for MIDI output
- Creates a virtual MIDI destination for testing
- Sends standard MIDI messages (Note On: 0x90, Note Off: 0x80)
- Supports all 16 MIDI channels
- Velocity-sensitive output

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+

## Setup

1. Open `MIDIPlayer.xcodeproj` in Xcode
2. Build and run on a physical iOS device (MIDI functionality requires a real device)
3. Connect external MIDI devices or use MIDI-enabled apps to receive the output

## Usage

1. **Press and hold** any button to send a MIDI Note On message
2. **Release** the button to send a MIDI Note Off message
3. Adjust the **velocity slider** to control note velocity (1-127)
4. Select the **MIDI channel** from the dropdown (1-16)
5. The **status indicator** shows green when MIDI is connected

## MIDI Output

The app sends MIDI data to:
- All available MIDI destinations on the device
- A virtual destination endpoint for testing
- External MIDI devices connected via USB or wireless

## Notes

- The app creates its own virtual MIDI destination for testing purposes
- MIDI messages are logged to the console for debugging
- The keyboard layout includes both natural notes (white keys) and sharp/flat notes (black keys)
- Haptic feedback provides tactile response when pressing buttons

## Customization

You can easily modify:
- Note mappings in the `notes` array in `ContentView.swift`
- MIDI controller assignments in `MIDIController.swift`
- UI appearance and layout in `ContentView.swift`
- Add additional MIDI message types (CC, Program Change, etc.)
