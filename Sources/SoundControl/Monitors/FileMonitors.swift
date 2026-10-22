import Foundation
import OSLog
import SoundControlCore

/// Watches one folder's directory entries and reports when they change.
@MainActor
final class FolderWatcher {
    /// Coalesces the burst of directory events a single save produces.
    private static let debounce: TimeInterval = 0.12
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var isStopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    /// Opens the folder off the main thread — the first access to Desktop/Downloads shows a
    /// privacy prompt and `open` blocks until the user answers, which would freeze the app.
    /// `completion` runs on main with the current entries, or nil if access failed.
    func start(completion: @escaping (Set<String>?) -> Void) {
        let path = url.path
        DispatchQueue.global(qos: .utility).async {
            let descriptor = open(path, O_EVTONLY)
            let contents = descriptor >= 0 ? (try? FileManager.default.contentsOfDirectory(atPath: path)).map(Set.init) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishStart(descriptor: descriptor, contents: contents, completion: completion)
                }
            }
        }
    }

    private func finishStart(descriptor: Int32, contents: Set<String>?, completion: (Set<String>?) -> Void) {
        guard descriptor >= 0 else {
            completion(nil)
            return
        }
        guard !isStopped, let contents else {
            close(descriptor)
            if !isStopped { completion(nil) }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        completion(contents)
    }

    func stop() {
        isStopped = true
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    func contents() -> Set<String>? {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)).map(Set.init)
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }
}

/// New finished files in ~/Downloads.
@MainActor
final class DownloadsMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.fileDownloaded]
    private let sink: MonitorSink
    private var watcher: FolderWatcher?
    private var known: Set<String> = []

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let watcher = FolderWatcher(url: folder) { [weak self] in self?.folderChanged() }
        self.watcher = watcher
        watcher.start { [weak self] contents in
            guard let self, self.watcher === watcher else { return }
            guard let contents else {
                self.watcher = nil
                self.sink.setUnavailable(self.triggers, "Allow access to the Downloads folder in Privacy settings")
                return
            }
            self.sink.setUnavailable(self.triggers, nil)
            self.known = contents
        }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func folderChanged() {
        guard let contents = watcher?.contents() else { return }
        let added = DownloadFilter.newDownloads(before: known, after: contents)
        known = contents
        if let first = added.first {
            sink.emit(.fileDownloaded, added.count == 1 ? first : "\(added.count) files")
        }
    }
}

/// Trash contents changing (files trashed or Trash emptied).
@MainActor
final class TrashMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.trashChanged]
    private let sink: MonitorSink
    private var watcher: FolderWatcher?
    private var count = 0

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        let watcher = FolderWatcher(url: trash) { [weak self] in self?.trashChanged() }
        self.watcher = watcher
        watcher.start { [weak self] contents in
            guard let self, self.watcher === watcher else { return }
            guard let contents else {
                self.watcher = nil
                self.sink.setUnavailable(self.triggers, "Needs Full Disk Access to watch the Trash")
                return
            }
            self.sink.setUnavailable(self.triggers, nil)
            self.count = contents.filter { !$0.hasPrefix(".") }.count
        }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func trashChanged() {
        guard let contents = watcher?.contents() else { return }
        let visible = contents.filter { !$0.hasPrefix(".") }.count
        defer { count = visible }
        guard visible != count else { return }
        sink.emit(.trashChanged, visible > count ? "Moved to Trash" : "Trash emptied")
    }
}

/// New screen captures. Watches the screenshot folder directly (instant once the file is
/// written) and checks the `kMDItemIsScreenCapture` attribute macOS stamps on captures;
/// a Spotlight query covers captures saved anywhere else.
@MainActor
final class ScreenshotMonitor: NSObject, TriggerMonitor {
    let triggers: Set<TriggerID> = [.screenshotTaken]
    private static let captureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    private static let recentLimit = 20

    private let sink: MonitorSink
    private var watcher: FolderWatcher?
    private var folder: URL?
    private var known: Set<String> = []
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    /// File names already announced, so the folder watcher and Spotlight never double up.
    private var announced: [String] = []

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        let folder = Self.screenshotFolder()
        let watcher = FolderWatcher(url: folder) { [weak self] in self?.folderChanged() }
        self.watcher = watcher
        self.folder = folder
        // If folder access is refused, the Spotlight query below still catches captures (just later).
        watcher.start { [weak self] contents in
            guard let self, self.watcher === watcher else { return }
            guard let contents else {
                self.watcher = nil
                return
            }
            self.known = contents
        }
        startSpotlight()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        query?.stop()
        observer.map(NotificationCenter.default.removeObserver)
        query = nil
        observer = nil
    }

    private func folderChanged() {
        guard let folder, let contents = watcher?.contents() else { return }
        let added = contents.subtracting(known)
        known = contents
        // screencapture writes a hidden temp file first, then renames it.
        for name in added.sorted() where !name.hasPrefix(".") && Self.isScreenCapture(folder.appendingPathComponent(name)) {
            announce(name)
        }
    }

    private func startSpotlight() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] notification in
            let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let names = added.compactMap { $0.value(forAttribute: NSMetadataItemFSNameKey) as? String }
            MainActor.assumeIsolated { names.forEach { self?.announce($0) } }
        }
        query.start()
        self.query = query
    }

    private func announce(_ name: String) {
        guard !announced.contains(name) else { return }
        announced = Array((announced + [name]).suffix(Self.recentLimit))
        sink.emit(.screenshotTaken, name)
    }

    private static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, captureAttribute, nil, 0, 0, XATTR_NOFOLLOW) > 0
    }

    /// The folder set in Screenshot.app options, or the Desktop.
    private static func screenshotFolder() -> URL {
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        if let path = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
