import AppKit
import Foundation
import ServiceManagement

struct WorldClock: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var timeZoneID: String
    var showInMenuBar = true

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    static let defaults = [
        WorldClock(label: "LDN", timeZoneID: "Europe/London"),
        WorldClock(label: "NYC", timeZoneID: "America/New_York"),
    ]
}

@MainActor
final class ClockStore: ObservableObject {
    @Published var clocks: [WorldClock] { didSet { save() } }
    @Published var use24Hour: Bool { didSet { defaults.set(use24Hour, forKey: Keys.use24Hour) } }
    @Published var menuBarDate: MenuBarDate {
        didSet { defaults.set(menuBarDate.rawValue, forKey: Keys.menuBarDate) }
    }
    @Published private(set) var now = Date()

    enum MenuBarDate: String, CaseIterable {
        case always, whenDifferent, never

        var title: String {
            switch self {
            case .always: "Always"
            case .whenDifferent: "If different"
            case .never: "Never"
            }
        }
    }

    private let defaults = UserDefaults.standard
    private var ticker: Task<Void, Never>?

    private enum Keys {
        static let clocks = "clocks"
        static let use24Hour = "use24Hour"
        static let menuBarDate = "menuBarDate"
    }

    init() {
        if let data = defaults.data(forKey: Keys.clocks),
           let saved = try? JSONDecoder().decode([WorldClock].self, from: data) {
            clocks = saved
        } else {
            clocks = WorldClock.defaults
        }
        use24Hour = defaults.object(forKey: Keys.use24Hour) as? Bool ?? true
        menuBarDate = defaults.string(forKey: Keys.menuBarDate).flatMap(MenuBarDate.init) ?? .always
        startTicking()

        // Refresh immediately after waking from sleep or a manual clock/timezone change.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        now = Date()
    }

    /// Wakes just after each minute boundary so the menu bar flips exactly on the minute.
    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let t = Date().timeIntervalSince1970
                let wait = (60 - t.truncatingRemainder(dividingBy: 60)) + 0.05
                try? await Task.sleep(for: .seconds(wait))
                self?.refresh()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clocks) {
            defaults.set(data, forKey: Keys.clocks)
        }
    }

    // MARK: - Editing

    func add(timeZoneID: String) {
        clocks.append(WorldClock(label: Self.cityName(for: timeZoneID), timeZoneID: timeZoneID))
    }

    func remove(_ clock: WorldClock) {
        clocks.removeAll { $0.id == clock.id }
    }

    func move(_ clock: WorldClock, by offset: Int) {
        guard let i = clocks.firstIndex(of: clock) else { return }
        let j = i + offset
        guard clocks.indices.contains(j) else { return }
        clocks.swapAt(i, j)
    }

    static func cityName(for timeZoneID: String) -> String {
        (timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID)
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Formatting

    /// e.g. "LDN · Wed 23 · 08:43   │   NYC · Wed 23 · 03:43"
    var menuBarTitle: String {
        clocks.filter(\.showInMenuBar)
            .map { clock in
                let showDate = switch menuBarDate {
                case .always: true
                case .whenDifferent: dayOffset(for: clock) != 0
                case .never: false
                }
                let parts = [clock.label]
                    + (showDate ? [formatter(clock.timeZone, format: "EEE d").string(from: now)] : [])
                    + [time(for: clock)]
                return parts.joined(separator: " · ")
            }
            .joined(separator: "   │   ")
    }

    func time(for clock: WorldClock) -> String {
        formatter(clock.timeZone, format: use24Hour ? "HH:mm" : "h:mm a").string(from: now)
    }

    func date(for clock: WorldClock) -> String {
        formatter(clock.timeZone, format: "EEE d MMM").string(from: now)
    }

    /// e.g. "+5h", "−4h 30m", or "Same as you".
    func offsetFromLocal(for clock: WorldClock) -> String {
        let diff = clock.timeZone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        if diff == 0 { return "Same as you" }
        let sign = diff > 0 ? "+" : "−"
        let hours = abs(diff) / 3600
        let minutes = (abs(diff) % 3600) / 60
        return minutes == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours)h \(minutes)m"
    }

    /// "Today", "Tomorrow" or "Yesterday" relative to the local calendar day.
    func relativeDay(for clock: WorldClock) -> String {
        switch dayOffset(for: clock) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: ""
        }
    }

    /// Calendar days the clock is ahead of (+) or behind (−) the local date.
    func dayOffset(for clock: WorldClock) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        var remote = local
        remote.timeZone = clock.timeZone
        let a = local.dateComponents([.year, .month, .day], from: now)
        let b = remote.dateComponents([.year, .month, .day], from: now)
        guard let da = local.date(from: a), let db = local.date(from: b) else { return 0 }
        return local.dateComponents([.day], from: da, to: db).day ?? 0
    }

    enum WorkState { case working, edge, offHours }

    /// Rough "can I ping them?" indicator: 9–17 working, 7–9 / 17–21 edge, otherwise off.
    func workState(for clock: WorldClock) -> WorkState {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = clock.timeZone
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 { return .offHours }
        switch hour {
        case 9..<17: return .working
        case 7..<9, 17..<21: return .edge
        default: return .offHours
        }
    }

    private var formatterCache: [String: DateFormatter] = [:]

    private func formatter(_ tz: TimeZone, format: String) -> DateFormatter {
        let key = "\(tz.identifier)|\(format)"
        if let f = formatterCache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = format
        formatterCache[key] = f
        return f
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Meridian: launch-at-login change failed: \(error)")
            }
        }
    }
}
