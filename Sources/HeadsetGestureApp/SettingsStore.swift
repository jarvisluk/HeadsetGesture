import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var enabled: Bool { didSet { saveScalar(enabled, key: Keys.enabled) } }
    @Published var showDockIcon: Bool { didSet { saveScalar(showDockIcon, key: Keys.showDockIcon) } }
    @Published var doubleTapInterval: Double { didSet { saveScalar(doubleTapInterval, key: Keys.doubleTapInterval) } }
    @Published var longPressDuration: Double { didSet { saveScalar(longPressDuration, key: Keys.longPressDuration) } }
    @Published var longPressRecognitionEnabled: Bool {
        didSet { saveScalar(longPressRecognitionEnabled, key: Keys.longPressRecognitionEnabled) }
    }
    @Published var longPressTriggerMode: LongPressTriggerMode {
        didSet { saveScalar(longPressTriggerMode.rawValue, key: Keys.longPressTriggerMode) }
    }
    @Published var showLongPressDuration: Bool {
        didSet { saveScalar(showLongPressDuration, key: Keys.showLongPressDuration) }
    }
    @Published var longPressDisplayPosition: LongPressDisplayPosition {
        didSet { saveScalar(longPressDisplayPosition.rawValue, key: Keys.longPressDisplayPosition) }
    }
    @Published var singleTapAction: KeyAction { didSet { saveEncoded(singleTapAction, key: Keys.singleTapAction) } }
    @Published var doubleTapAction: KeyAction { didSet { saveEncoded(doubleTapAction, key: Keys.doubleTapAction) } }
    @Published var tripleTapAction: KeyAction { didSet { saveEncoded(tripleTapAction, key: Keys.tripleTapAction) } }
    @Published var longPressAction: KeyAction { didSet { saveEncoded(longPressAction, key: Keys.longPressAction) } }
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var saveErrorText: String?

    var saveStatusText: String {
        if let saveErrorText {
            return saveErrorText
        }
        guard let lastSavedAt else {
            return "Changes save automatically"
        }
        return "Saved at \(lastSavedAt.formatted(date: .omitted, time: .standard))"
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "enabled"
        static let showDockIcon = "showDockIcon"
        static let doubleTapInterval = "doubleTapInterval"
        static let longPressDuration = "longPressDuration"
        static let longPressRecognitionEnabled = "longPressRecognitionEnabled"
        static let longPressTriggerMode = "longPressTriggerMode"
        static let showLongPressDuration = "showLongPressDuration"
        static let longPressDisplayPosition = "longPressDisplayPosition"
        static let singleTapAction = "singleTapAction"
        static let doubleTapAction = "doubleTapAction"
        static let tripleTapAction = "tripleTapAction"
        static let longPressAction = "longPressAction"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? true
        doubleTapInterval = defaults.object(forKey: Keys.doubleTapInterval) as? Double ?? 0.30
        longPressDuration = defaults.object(forKey: Keys.longPressDuration) as? Double ?? 0.60
        longPressRecognitionEnabled = defaults.object(forKey: Keys.longPressRecognitionEnabled) as? Bool ?? false
        longPressTriggerMode = defaults.string(forKey: Keys.longPressTriggerMode)
            .flatMap(LongPressTriggerMode.init(rawValue:)) ?? .onRelease
        showLongPressDuration = defaults.object(forKey: Keys.showLongPressDuration) as? Bool ?? true
        longPressDisplayPosition = defaults.string(forKey: Keys.longPressDisplayPosition)
            .flatMap(LongPressDisplayPosition.init(rawValue:)) ?? .bottom
        singleTapAction = Self.load(KeyAction.self, key: Keys.singleTapAction, defaults: defaults) ?? .defaultSingleTap
        doubleTapAction = Self.load(KeyAction.self, key: Keys.doubleTapAction, defaults: defaults) ?? .defaultDoubleTap
        tripleTapAction = Self.load(KeyAction.self, key: Keys.tripleTapAction, defaults: defaults) ?? .defaultTripleTap
        longPressAction = Self.load(KeyAction.self, key: Keys.longPressAction, defaults: defaults) ?? .defaultLongPress
    }

    private func saveScalar(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
        markSaved()
    }

    private func saveEncoded<T: Encodable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key)
            markSaved()
        } catch {
            saveErrorText = "Could not save changes"
        }
    }

    private func markSaved() {
        saveErrorText = nil
        lastSavedAt = Date()
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
