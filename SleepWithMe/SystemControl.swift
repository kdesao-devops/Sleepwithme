import AppKit
import AudioToolbox
import CoreAudio

/// Volume et état de la sortie audio par défaut, via CoreAudio.
enum AudioController {

    private static var defaultOutputDevice: AudioDeviceID? {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return (status == noErr && device != 0) ? device : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Volume de sortie entre 0 et 1. Vaut nil si la sortie n'a pas de réglage de volume
    /// (certains écrans HDMI par exemple) ; dans ce cas le fondu est simplement ignoré.
    static var volume: Float? {
        get {
            guard let device = defaultOutputDevice else { return nil }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = volumeAddress
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr ? value : nil
        }
        set {
            guard let device = defaultOutputDevice, let newValue else { return }
            var value = Float32(min(1, max(0, newValue)))
            let size = UInt32(MemoryLayout<Float32>.size)
            var address = volumeAddress
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }

    /// Vrai si une appli est en train d'envoyer du son vers la sortie par défaut.
    static var isOutputActive: Bool {
        guard let device = defaultOutputDevice else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }
}

/// Simule la touche Lecture/Pause du clavier (nécessite l'autorisation d'accessibilité).
enum MediaKey {
    static func playPause() {
        let playKey = 16 // NX_KEYTYPE_PLAY

        func post(down: Bool) {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (playKey << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }

        post(down: true)
        post(down: false)
    }
}

/// Mise en veille du Mac, équivalent de `pmset sleepnow`.
enum SystemSleep {
    static func sleepNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        try? process.run()
    }
}
