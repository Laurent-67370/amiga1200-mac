import CoreMIDI
import Foundation

/// MIDI du port série de l'Amiga par CoreMIDI : ce que joue l'Amiga part vers un synthétiseur (USB, Bluetooth, réseau,
/// application de synthé), un clavier MIDI peut jouer sur l'Amiga (Bars & Pipes, Music-X, OctaMED…)
final class MidiLink {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef(), inPort = MIDIPortRef()
    private var dest: MIDIEndpointRef = 0
    private var timer: Timer?

    static func name(_ e: MIDIEndpointRef) -> String {
        var s: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s)
        return (s?.takeRetainedValue() as String?) ?? "?"
    }
    /// Appareils qui reçoivent (sorties de l'Amiga) ou qui envoient (claviers)
    static func names(output: Bool) -> [String] {
        let n = output ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources()
        return (0..<n).map { name(output ? MIDIGetDestination($0) : MIDIGetSource($0)) }
    }

    /// Démarre ; renvoie le compte rendu (appareils reliés)
    func start(_ s: Settings) -> String {
        guard MIDIClientCreate("Amiga 1200" as CFString, nil, nil, &client) == noErr else { return "MIDI indisponible" }
        var msg: [String] = []
        let dests = (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }
        dest = dests.first { MidiLink.name($0) == s.midiOut } ?? dests.first ?? 0
        if dest != 0 {
            MIDIOutputPortCreate(client, "Sortie Amiga" as CFString, &outPort)
            msg.append("MIDI → \(MidiLink.name(dest))")
        } else { msg.append("Aucun appareil MIDI pour la sortie") }
        if !s.midiIn.isEmpty, let src = (0..<MIDIGetNumberOfSources()).map({ MIDIGetSource($0) }).first(where: { MidiLink.name($0) == s.midiIn }) {
            MIDIInputPortCreateWithBlock(client, "Entrée Amiga" as CFString, &inPort) { list, _ in
                for p in list.unsafeSequence() {
                    // Les octets suivent l'en-tête du paquet (ils peuvent dépasser les 256 du tuple data)
                    let data = UnsafeRawPointer(p).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!)
                    amb_midi_write(data.assumingMemoryBound(to: UInt8.self), UInt32(p.pointee.length))
                }
            }
            MIDIPortConnectSource(inPort, src, nil)
            msg.append("\(MidiLink.name(src)) → Amiga")
        }
        amb_midi_enable(dest != 0 ? 1 : 0, inPort != 0 ? 1 : 0)
        // Octets joués par l'Amiga : envoyés toutes les 2 ms
        timer = Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { [weak self] _ in self?.pump() }
        return msg.joined(separator: " · ")
    }

    private func pump() {
        guard dest != 0 else { return }
        var b = [UInt8](repeating: 0, count: 1024)
        let n = Int(amb_midi_read(&b, UInt32(b.count)))
        if n == 0 { return }
        var buf = [UInt8](repeating: 0, count: n + 64)
        buf.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let pkt = MIDIPacketListInit(list)
            _ = MIDIPacketListAdd(list, raw.count, pkt, 0, n, b)
            MIDISend(outPort, dest, list)
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        amb_midi_enable(0, 0)
        if client != 0 { MIDIClientDispose(client) }
    }
}
