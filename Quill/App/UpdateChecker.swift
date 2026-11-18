import AppKit
import Observation

/// A published release on GitHub.
struct AppRelease: Equatable {
    let version: String
    let name: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL?
    let publishedAt: Date?
}

/// Checks GitHub Releases for a newer version: on launch, then daily, or on demand.
/// Notifies only; the person downloads and installs the new DMG themselves.
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    /// Shown in the menu bar and library until downloaded, skipped or dismissed.
    var availableUpdate: AppRelease? {
        if case .available(let release) = status, release.version != skippedVersion, !isDismissed { return release }
        return nil
    }

    var isShowingDetails = false
    private(set) var isDismissed = false

    var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: Keys.automatic)
            if checksAutomatically { scheduleChecks() } else { scheduler?.cancel() }
        }
    }

    private var skippedVersion: String? {
        didSet { defaults.set(skippedVersion, forKey: Keys.skipped) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    private let interval: TimeInterval = 24 * 60 * 60

    private enum Keys {
        static let automatic = "checksForUpdates"
        static let skipped = "skippedUpdateVersion"
        static let lastChecked = "lastUpdateCheck"
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "owner/repo", from Info.plist, so a fork checks its own releases.
    static var repository: String? {
        Bundle.main.object(forInfoDictionaryKey: "QuillUpdateRepository") as? String
    }

    init() {
        checksAutomatically = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        skippedVersion = defaults.string(forKey: Keys.skipped)
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        #if DEBUG
        if CommandLine.arguments.contains("-QuillFakeUpdate") {
            status = .available(AppRelease(
                version: "9.9", name: "Quill 9.9",
                notes: "## New\n- **Example feature**: a demo release note.\n- Faster suggestions.\n\n## Fixed\n- An example fix.",
                pageURL: URL(string: "https://github.com")!, downloadURL: nil, publishedAt: Date()))
            return
        }
        if ["-QuillDemo", "-QuillSelfTest", "-QuillUpdateCheck"].contains(where: CommandLine.arguments.contains) { return }
        #endif
        if checksAutomatically { scheduleChecks() }
    }

    // MARK: Checking

    /// First check shortly after launch (if a day has passed), then once a day.
    private func scheduleChecks() {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                guard let self else { return }
                let due = self.lastChecked.map { Date().timeIntervalSince($0) >= self.interval } ?? true
                if due { await self.check(manual: false) }
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func check(manual: Bool) async {
        guard status != .checking else { return }
        guard let repository = Self.repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            status = .failed("No update source is configured.")
            return
        }
        status = .checking
        if manual { isDismissed = false }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Quill/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                status = .failed(http.statusCode == 404 ? "No releases found." : "GitHub returned error \(http.statusCode).")
                return
            }
            let release = try Self.parse(data)
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Keys.lastChecked)
            if Self.isVersion(release.version, newerThan: Self.currentVersion) {
                status = .available(release)
                // A manual check always shows the update, even one skipped before.
                if manual { skippedVersion = nil; isShowingDetails = true }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(manual ? "Couldn't reach GitHub. Check your connection and try again." : "Couldn't check for updates.")
            quillLog.notice("Updates: check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Actions

    func download(_ release: AppRelease) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        isShowingDetails = false
        isDismissed = true
    }

    func skip(_ release: AppRelease) {
        skippedVersion = release.version
        isShowingDetails = false
    }

    func remindLater() {
        isDismissed = true
        isShowingDetails = false
    }

    // MARK: Parsing and comparing

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let published_at: Date?
        let assets: [Asset]
    }

    static func parse(_ data: Data) throws -> AppRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return AppRelease(version: version, name: release.name ?? "Quill \(version)", notes: release.body ?? "",
                          pageURL: release.html_url, downloadURL: dmg, publishedAt: release.published_at)
    }

    /// Compares dotted versions numerically, so 1.10 is newer than 1.9 and 1.1 equals 1.1.0.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
