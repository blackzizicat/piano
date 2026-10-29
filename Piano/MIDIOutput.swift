import CoreMIDI

/// Sends the keyboard's notes as MIDI 1.0 messages.
///
/// Notes go to:
/// - a virtual source named "Piano" (other apps on this device, e.g. GarageBand or AUM)
/// - every destination that belongs to a device: Network MIDI session, USB (Mac's
///   Audio MIDI Setup "iOS device"), connected Bluetooth or USB MIDI devices.
/// Other apps' virtual destinations are skipped so apps listening to the virtual
/// source do not receive every note twice.
final class MIDIOutput {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var source = MIDIEndpointRef()

    init() {
        MIDIClientCreateWithBlock("Piano" as CFString, &client) { _ in }
        MIDIOutputPortCreate(client, "Piano Output" as CFString, &port)
        MIDISourceCreateWithProtocol(client, "Piano" as CFString, ._1_0, &source)

        let network = MIDINetworkSession.default()
        network.isEnabled = true
        network.connectionPolicy = .anyone
    }

    func noteOn(_ note: Int, velocity: Float, channel: Int) {
        let vel = UInt8(min(max(Int(velocity * 127), 1), 127))
        send(status: 0x90 | UInt8(channel & 0x0F), UInt8(note & 0x7F), vel)
    }

    func noteOff(_ note: Int, channel: Int) {
        send(status: 0x80 | UInt8(channel & 0x0F), UInt8(note & 0x7F), 0)
    }

    private func send(status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        // Universal MIDI Packet, message type 2 (MIDI 1.0 channel voice), group 0.
        var word: UInt32 = 0x2000_0000 | UInt32(status) << 16 | UInt32(data1) << 8 | UInt32(data2)
        var list = MIDIEventList()
        withUnsafeMutablePointer(to: &list) { listPtr in
            let packet = MIDIEventListInit(listPtr, ._1_0)
            _ = MIDIEventListAdd(listPtr, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)

            if source != 0 {
                MIDIReceivedEventList(source, listPtr)
            }
            for i in 0..<MIDIGetNumberOfDestinations() {
                let dest = MIDIGetDestination(i)
                var entity = MIDIEntityRef()
                // Virtual destinations created by other apps have no entity.
                guard MIDIEndpointGetEntity(dest, &entity) == noErr, entity != 0 else { continue }
                MIDISendEventList(port, dest, listPtr)
            }
        }
    }
}
