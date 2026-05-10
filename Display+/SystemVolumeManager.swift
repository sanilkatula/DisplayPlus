import Foundation
import CoreAudio

final class SystemVolumeManager {
    static let shared = SystemVolumeManager()

    private init() {}

    func readVolume() -> Float? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }

        if let main = readVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return main
        }

        let left = readVolume(deviceID: deviceID, element: 1)
        let right = readVolume(deviceID: deviceID, element: 2)

        switch (left, right) {
        case let (.some(l), .some(r)):
            return (l + r) / 2
        case let (.some(l), nil):
            return l
        case let (nil, .some(r)):
            return r
        default:
            return nil
        }
    }

    func setVolume(_ value: Float) {
        guard let deviceID = defaultOutputDeviceID() else {
            print("No default output device found.")
            return
        }

        let clamped = max(0, min(1, value))

        if setVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: clamped) {
            return
        }

        let leftOK = setVolume(deviceID: deviceID, element: 1, value: clamped)
        let rightOK = setVolume(deviceID: deviceID, element: 2, value: clamped)

        if !leftOK && !rightOK {
            print("Default output device does not expose writable volume.")
        }
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private func readVolume(
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )

        return status == noErr ? volume : nil
    }

    private func setVolume(
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement,
        value: Float
    ) -> Bool {
        var volume = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &volume
        )

        return status == noErr
    }
}
