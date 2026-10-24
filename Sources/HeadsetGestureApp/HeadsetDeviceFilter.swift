import Foundation
import IOKit
import IOKit.hid

/// Decides which Consumer Control HID devices are headsets. Devices are seized
/// one by one, so keyboards and receivers with media keys are never taken over.
enum HeadsetDeviceFilter {
    /// Candidates handed to the HID manager; `shouldIntercept` narrows them down.
    static let matchingDictionaries: [[String: Any]] = [
        // The headphone-jack remote decoder. IOHIDManager compares product names
        // as case-insensitive substrings, so this also catches "… HEADSET" names.
        [
            kIOHIDProductKey as String: "Headset",
            kIOHIDPrimaryUsagePageKey as String: 0x0c
        ],
        [
            kIOHIDTransportKey as String: "USB",
            kIOHIDPrimaryUsagePageKey as String: 0x0c,
            kIOHIDPrimaryUsageKey as String: 0x01
        ]
    ]

    static func shouldIntercept(_ device: IOHIDDevice) -> Bool {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        return isHeadsetName(product) || hasUSBAudioInterface(device)
    }

    static func isHeadsetName(_ product: String) -> Bool {
        product.range(of: "headset", options: .caseInsensitive) != nil
    }

    /// Walks up from the HID interface to its USB device and checks whether a
    /// sibling interface is USB Audio Class (bInterfaceClass 1).
    private static func hasUSBAudioInterface(_ device: IOHIDDevice) -> Bool {
        var entry = IOHIDDeviceGetService(device)
        guard entry != IO_OBJECT_NULL else { return false }
        IOObjectRetain(entry)

        while entry != IO_OBJECT_NULL {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                defer { IOObjectRelease(entry) }
                return hasAudioInterfaceChild(entry)
            }
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : IO_OBJECT_NULL
        }
        return false
    }

    private static func hasAudioInterfaceChild(_ usbDevice: io_registry_entry_t) -> Bool {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryGetChildIterator(usbDevice, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        var found = false
        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            let interfaceClass = IORegistryEntryCreateCFProperty(
                child,
                "bInterfaceClass" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Int
            IOObjectRelease(child)
            if interfaceClass == 1 {
                found = true
                break
            }
        }
        return found
    }
}
