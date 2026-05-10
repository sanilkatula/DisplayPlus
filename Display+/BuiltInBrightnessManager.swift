import Foundation
import IOKit
import IOKit.graphics

final class BuiltInBrightnessManager {
    static let shared = BuiltInBrightnessManager()

    private init() {}

    func readBrightness() -> Float? {
        var result: Float?

        forDisplayService { service in
            var value: Float = 0

            let error = IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &value
            )

            if error == kIOReturnSuccess, result == nil {
                result = value
            }
        }

        return result
    }

    func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))

        forDisplayService { service in
            var current: Float = 0

            let canRead = IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &current
            )

            guard canRead == kIOReturnSuccess else {
                return
            }

            IODisplaySetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                clamped
            )
        }
    }

    private func forDisplayService(_ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0

        guard let matching = IOServiceMatching("IODisplayConnect") else {
            return
        }

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        )

        guard result == kIOReturnSuccess else {
            return
        }

        defer {
            IOObjectRelease(iterator)
        }

        var service = IOIteratorNext(iterator)

        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
