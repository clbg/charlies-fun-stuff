import Foundation
import Observation

/// Daily sunset reminder: toast at T-10min, bubble + 10s of Bach at T-5min.
/// Sunset time is computed locally (NOAA almanac algorithm) from a configurable lat/lon.
@MainActor
@Observable
final class SunsetReminder {

    private static let enabledKey = "CharlieWidget.sunsetEnabled"
    private static let latitudeKey = "CharlieWidget.sunsetLatitude"
    private static let longitudeKey = "CharlieWidget.sunsetLongitude"
    private static let firedKey = "CharlieWidget.sunsetFired"

    // Tokyo
    private static let defaultLatitude = 35.6762
    private static let defaultLongitude = 139.6503

    static let musicDir = "/Users/pencheng/Library/CloudStorage/GoogleDrive-charlie.pengcheng@gmail.com/My Drive/Autosync/CharlieObsidianVault/Assets/audios/agent-operator"
    private static let musicSeconds = 10
    static let bubbleId = "sunset"

    private static let warnLead: TimeInterval = 10 * 60
    private static let bubbleLead: TimeInterval = 5 * 60
    /// Events missed by more than this (e.g. Mac asleep) are skipped instead of fired late.
    private static let grace: TimeInterval = 2 * 60
    private static let pollInterval: Duration = .seconds(20)

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var latitude: Double {
        didSet { UserDefaults.standard.set(latitude, forKey: Self.latitudeKey) }
    }

    var longitude: Double {
        didSet { UserDefaults.standard.set(longitude, forKey: Self.longitudeKey) }
    }

    /// Called with (title, body) for the T-10 toast.
    var onWarn: (@MainActor (String, String) -> Void)?
    /// Called with the sunset time for the T-5 bubble.
    var onBubble: (@MainActor (Date) -> Void)?

    /// Keys like "2026-10-08:warn" — persisted so an app restart doesn't re-fire.
    private var fired: Set<String> {
        didSet { UserDefaults.standard.set(Array(fired), forKey: Self.firedKey) }
    }

    private var loopTask: Task<Void, Never>?
    private var musicProcess: Process?

    init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.latitude = defaults.object(forKey: Self.latitudeKey) as? Double ?? Self.defaultLatitude
        self.longitude = defaults.object(forKey: Self.longitudeKey) as? Double ?? Self.defaultLongitude
        self.fired = Set(defaults.stringArray(forKey: Self.firedKey) ?? [])
    }

    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.check(now: Date())
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    // MARK: - Scheduling

    private func check(now: Date) {
        guard isEnabled, let sunset = todaySunset(now: now) else { return }
        let day = Self.dayKey(now)
        let todayFired = fired.filter { $0.hasPrefix(day) }
        if todayFired != fired { fired = todayFired }

        let warnAt = sunset.addingTimeInterval(-Self.warnLead)
        let bubbleAt = sunset.addingTimeInterval(-Self.bubbleLead)

        if fire("\(day):warn", at: warnAt, now: now, until: bubbleAt) {
            warn(sunset: sunset)
        }
        if fire("\(day):bubble", at: bubbleAt, now: now, until: sunset) {
            bubble(sunset: sunset)
        }
    }

    /// True once per key when `now` falls in [at, min(at + grace, until)).
    private func fire(_ key: String, at: Date, now: Date, until: Date) -> Bool {
        guard !fired.contains(key), now >= at,
              now < min(at.addingTimeInterval(Self.grace), until) else { return false }
        fired.insert(key)
        return true
    }

    // MARK: - Actions

    func warn(sunset: Date) {
        onWarn?("🌇 快日落了", "还有 10 分钟日落（\(Self.timeString(sunset))），起来看看窗外吧")
    }

    func bubble(sunset: Date) {
        onBubble?(sunset)
        playBach()
    }

    func runTest() {
        let sunset = Date().addingTimeInterval(Self.bubbleLead)
        warn(sunset: sunset)
        bubble(sunset: sunset)
    }

    private func playBach() {
        guard let file = Self.pickBachFile() else {
            print("[SunsetReminder] No Bach file in \(Self.musicDir)")
            return
        }
        if let old = musicProcess, old.isRunning { old.terminate() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-t", "\(Self.musicSeconds)", file]
        do {
            try process.run()
            musicProcess = process
        } catch {
            print("[SunsetReminder] Failed to run afplay: \(error)")
        }
    }

    /// Prefers calm Bach pieces; falls back to any Bach file.
    private static func pickBachFile() -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: musicDir)) ?? []
        let bach = names.filter { $0.contains("bach") && $0.hasSuffix(".wav") }
        let calm = bach.filter { $0.hasPrefix("calm_") }
        guard let name = (calm.isEmpty ? bach : calm).randomElement() else { return nil }
        return (musicDir as NSString).appendingPathComponent(name)
    }

    // MARK: - Status

    func statusJSON(now: Date = Date()) -> String {
        let sunset = todaySunset(now: now)
        let sunsetStr = sunset.map { "\"\(Self.timeString($0))\"" } ?? "null"
        let musicCount = ((try? FileManager.default.contentsOfDirectory(atPath: Self.musicDir)) ?? [])
            .filter { $0.contains("bach") && $0.hasSuffix(".wav") }.count
        let firedList = fired.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"enabled\":\(isEnabled),\"latitude\":\(latitude),\"longitude\":\(longitude),\"today_sunset\":\(sunsetStr),\"bach_files\":\(musicCount),\"fired_today\":[\(firedList)]}"
    }

    // MARK: - Sunset math

    func todaySunset(now: Date) -> Date? {
        Self.sunset(on: now, latitude: latitude, longitude: longitude)
    }

    /// NOAA almanac sunset (official zenith 90.833°) for the local calendar day containing `date`.
    static func sunset(on date: Date, latitude: Double, longitude: Double) -> Date? {
        let rad = Double.pi / 180
        let calendar = Calendar.current
        guard let n = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let lngHour = longitude / 15
        let t = Double(n) + (18 - lngHour) / 24
        let m = 0.9856 * t - 3.289
        var l = m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634
        l = l.truncatingRemainder(dividingBy: 360); if l < 0 { l += 360 }

        var ra = atan(0.91764 * tan(l * rad)) / rad
        ra = ra.truncatingRemainder(dividingBy: 360); if ra < 0 { ra += 360 }
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15

        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(90.833 * rad) - sinDec * sin(latitude * rad)) / (cosDec * cos(latitude * rad))
        guard cosH >= -1, cosH <= 1 else { return nil }  // polar day/night

        let h = acos(cosH) / rad / 15
        let localMeanTime = h + ra - 0.06571 * t - 6.622
        var ut = (localMeanTime - lngHour).truncatingRemainder(dividingBy: 24)
        if ut < 0 { ut += 24 }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let utcMidnight = utc.date(from: comps) else { return nil }
        var result = utcMidnight.addingTimeInterval(ut * 3600)

        // UT wraps across days for far-east/west zones; snap to the local day containing `date`.
        let localNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let delta = result.timeIntervalSince(localNoon)
        if delta > 12 * 3600 { result.addTimeInterval(-86400) }
        if delta < -12 * 3600 { result.addTimeInterval(86400) }
        return result
    }

    private static func dayKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
