import Foundation
import CoreMIDI
import AVFoundation

// MIDI read procedure callback - required for MIDIDestinationCreate
private func midiReadProc(pktlist: UnsafePointer<MIDIPacketList>, 
                         readProcRefCon: UnsafeMutableRawPointer?, 
                         srcConnRefCon: UnsafeMutableRawPointer?) {
    // This callback handles incoming MIDI data to our virtual destination
    // For this app, we're only sending MIDI data out, so we can leave this empty
    // But the callback is required by the Core MIDI API
}

class MIDIController: ObservableObject {
    @Published var isConnected = false
    @Published var velocity: Double = 80
    @Published var channel: UInt8 = 2
    
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var destinationEndpoint: MIDIEndpointRef = 0
    private var sourceEndpoint: MIDIEndpointRef = 0
    
    func setupMIDI() {
        // Create MIDI client
        let clientName = "MIDI Controller" as CFString
        let status = MIDIClientCreate(clientName, nil, nil, &midiClient)
        
        if status == noErr {
            print("MIDI Client created successfully")
            
            // Create output port
            let portName = "Output Port" as CFString
            let portStatus = MIDIOutputPortCreate(midiClient, portName, &outputPort)
            
            if portStatus == noErr {
                print("MIDI Output Port created successfully")
                
                // Set connected status as soon as we have a working output port
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                
                // Create virtual source endpoint (for other apps to receive from us)
                let sourceName = "MIDI Controller Source" as CFString
                let sourceStatus = MIDISourceCreate(midiClient, sourceName, &sourceEndpoint)
                
                if sourceStatus == noErr {
                    print("MIDI Source created successfully")
                } else {
                    print("Failed to create MIDI source: \(sourceStatus)")
                }
                
                // Create virtual destination endpoint (for receiving MIDI data)
                let destinationName = "MIDI Controller Destination" as CFString
                let endpointStatus = MIDIDestinationCreate(midiClient, destinationName, midiReadProc, nil, &destinationEndpoint)
                
                if endpointStatus == noErr {
                    print("MIDI Destination created successfully")
                } else {
                    print("Failed to create MIDI destination: \(endpointStatus)")
                }
                
                // Refresh destinations after everything is set up
                DispatchQueue.main.async {
                    // No need to refresh destinations anymore - we'll broadcast to all
                }
            } else {
                print("Failed to create MIDI output port: \(portStatus)")
            }
        } else {
            print("Failed to create MIDI client: \(status)")
        }
        
        // Request MIDI access permission
        requestMIDIAccess()
    }
    
    private func requestMIDIAccess() {
        // For iOS, we need to handle MIDI permissions
        // The system will automatically prompt for permission when we try to use MIDI
        print("MIDI access requested")
    }
    
    func sendNoteOn(note: UInt8) {
        let velocityValue = UInt8(velocity)
        
        // Broadcast to external MIDI devices only
        DispatchQueue.global(qos: .userInitiated).async {
            let noteOnStatus: UInt8 = 0x90 | self.channel // Note On + channel
            self.sendMIDIMessage(status: noteOnStatus, data1: note, data2: velocityValue)
        }
        
        print("Note ON: \(note) with velocity \(velocityValue) - MIDI broadcast only")
    }
    
    func sendNoteOff(note: UInt8) {
        // Broadcast to external MIDI devices only
        DispatchQueue.global(qos: .userInitiated).async {
            let noteOffStatus: UInt8 = 0x80 | self.channel // Note Off + channel
            self.sendMIDIMessage(status: noteOffStatus, data1: note, data2: 0)
        }
        
        print("Note OFF: \(note) - MIDI broadcast only")
    }
    
    // MARK: - Chord Functions
    
    func playChord(notes: [UInt8]) {
        let velocityValue = UInt8(velocity)
        
        // Broadcast to external MIDI devices only
        DispatchQueue.global(qos: .userInitiated).async {
            for note in notes {
                let noteOnStatus: UInt8 = 0x90 | self.channel // Note On + channel
                self.sendMIDIMessage(status: noteOnStatus, data1: note, data2: velocityValue)
            }
        }
        
        print("Chord ON: \(notes) with velocity \(velocityValue) - MIDI broadcast only")
    }
    
    func stopChord(notes: [UInt8]) {
        // Broadcast to external MIDI devices only
        DispatchQueue.global(qos: .userInitiated).async {
            for note in notes {
                let noteOffStatus: UInt8 = 0x80 | self.channel // Note Off + channel
                self.sendMIDIMessage(status: noteOffStatus, data1: note, data2: 0)
            }
        }
        
        print("Chord OFF: \(notes) - MIDI broadcast only")
    }
    
    func sendControlChange(controller: UInt8, value: UInt8) {
        let ccStatus: UInt8 = 0xB0 | channel // Control Change + channel
        
        sendMIDIMessage(status: ccStatus, data1: controller, data2: value)
        print("Control Change: Controller \(controller) = \(value) on channel \(channel + 1)")
    }

    func sendAllNotesOff() {
        // Send All Notes Off (CC 123) to all external MIDI devices
        DispatchQueue.global(qos: .userInitiated).async {
            self.sendMIDIMessage(status: 0xB0 | self.channel, data1: 123, data2: 0) // CC 123 = All Notes Off
        }
    }

    func panic() {
        sendAllNotesOff()
        DispatchQueue.global(qos: .userInitiated).async {
            self.sendMIDIMessage(status: 0xB0 | self.channel, data1: 120, data2: 0) // CC 120 = All Sound Off
        }
        
        print("🚨 PANIC - All notes stopped (MIDI broadcast only)")
    }
    
    func listMIDIDestinations() {
        print("=== Available MIDI Destinations ===")
        let destinationCount = MIDIGetNumberOfDestinations()
        
        if destinationCount == 0 {
            print("No external MIDI destinations found")
        } else {
            for i in 0..<destinationCount {
                let destination = MIDIGetDestination(i)
                if destination != 0 {
                    var name: Unmanaged<CFString>?
                    let nameStatus = MIDIObjectGetStringProperty(destination, kMIDIPropertyDisplayName, &name)
                    let destinationName = nameStatus == noErr ? name?.takeRetainedValue() as String? ?? "Unknown" : "Unknown"
                    
                    var manufacturer: Unmanaged<CFString>?
                    let mfgStatus = MIDIObjectGetStringProperty(destination, kMIDIPropertyManufacturer, &manufacturer)
                    let mfgName = mfgStatus == noErr ? manufacturer?.takeRetainedValue() as String? ?? "Unknown" : "Unknown"
                    
                    print("Destination \(i): \(destinationName) (\(mfgName))")
                }
            }
        }
        
        if sourceEndpoint != 0 {
            print("Virtual Source: MIDI Controller Source (for internal apps)")
        }
        print("===================================")
    }
    
    func debugMIDIState() {
        print("=== MIDI Controller Debug State ===")
        print("isConnected: \(isConnected)")
        print("midiClient: \(midiClient)")
        print("outputPort: \(outputPort)")
        print("sourceEndpoint: \(sourceEndpoint)")
        print("destinationEndpoint: \(destinationEndpoint)")
        print("Channel: \(channel + 1)")
        print("Velocity: \(Int(velocity))")
        
        let destinationCount = MIDIGetNumberOfDestinations()
        print("External destinations available: \(destinationCount)")
        print("Virtual source available: \(sourceEndpoint != 0)")
        
        print("==================================")
    }
    
    private func sendMIDIMessage(status: UInt8, data1: UInt8, data2: UInt8) {
        guard isConnected else {
            print("MIDI not connected - cannot send message")
            return
        }
        
        print("Broadcasting MIDI message on channel \(channel + 1): Status=\(String(format: "0x%02X", status)), Data1=\(data1), Data2=\(data2)")
        
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = status
        packet.data.1 = data1
        packet.data.2 = data2
        
        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        
        // Send to virtual source (for other iPad apps)
        if sourceEndpoint != 0 {
            let result = MIDIReceived(sourceEndpoint, &packetList)
            if result == noErr {
                print("✓ MIDI sent to virtual source (internal apps)")
            } else {
                print("✗ Failed to send to virtual source: \(result)")
            }
        }
        
        // Send to all external MIDI destinations
        let destinationCount = MIDIGetNumberOfDestinations()
        var externalDestinationsSent = 0
        
        for i in 0..<destinationCount {
            let destination = MIDIGetDestination(i)
            if destination != 0 {
                let result = MIDISend(outputPort, destination, &packetList)
                if result == noErr {
                    externalDestinationsSent += 1
                } else {
                    print("✗ Failed to send to external destination \(i): \(result)")
                }
            }
        }
        
        if externalDestinationsSent > 0 {
            print("✓ MIDI sent to \(externalDestinationsSent) external destination(s)")
        } else if destinationCount > 0 {
            print("✗ No external destinations received MIDI")
        }
        
        if sourceEndpoint == 0 && destinationCount == 0 {
            print("⚠️ No MIDI destinations available (no virtual source or external devices)")
        }
    }
    
    deinit {
        if sourceEndpoint != 0 {
            MIDIEndpointDispose(sourceEndpoint)
        }
        if destinationEndpoint != 0 {
            MIDIEndpointDispose(destinationEndpoint)
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
}
