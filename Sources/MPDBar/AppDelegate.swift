import AppKit
import MPDCore

private enum DefaultsKey {
    static let host = "mpdHost"
    static let port = "mpdPort"
    static let password = "mpdPassword"
}

private enum PollResult: Sendable {
    case success(MPDSnapshot)
    case failure(String)
}

private enum CommandResult: Sendable {
    case success
    case failure(String)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusItemContentView.width)
    private let statusContent = StatusItemContentView(frame: .zero)
    private let menu = NSMenu()
    private let nowPlayingItem = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
    private let detailsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var previousItem = makeMenuItem(
        title: "Previous",
        symbol: "backward.fill",
        action: #selector(previousTrack)
    )
    private lazy var toggleItem = makeMenuItem(
        title: "Play",
        symbol: "play.fill",
        action: #selector(togglePlayback)
    )
    private lazy var nextItem = makeMenuItem(
        title: "Next",
        symbol: "forward.fill",
        action: #selector(nextTrack)
    )

    private var timer: Timer?
    private var currentSnapshot: MPDSnapshot?
    private var refreshInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        statusContent.frame = button.bounds
        statusContent.setIcon(symbol("music.note"))
        statusContent.setTitle("MPD")
        button.addSubview(statusContent)
        button.toolTip = "MPD Bar"
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        nowPlayingItem.isEnabled = false
        detailsItem.isEnabled = false
        menu.addItem(nowPlayingItem)
        menu.addItem(detailsItem)
        menu.addItem(.separator())
        menu.addItem(previousItem)
        menu.addItem(toggleItem)
        menu.addItem(nextItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Refresh", symbol: "arrow.clockwise", action: #selector(refreshNow)))
        menu.addItem(makeMenuItem(title: "Settings…", symbol: "gearshape", action: #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MPD Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeMenuItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = self.symbol(symbol)
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private var configuration: MPDConfiguration {
        let defaults = UserDefaults.standard
        let environment = ProcessInfo.processInfo.environment
        let host = defaults.string(forKey: DefaultsKey.host)
            ?? environment["MPD_HOST"]
            ?? "127.0.0.1"

        let savedPort = defaults.object(forKey: DefaultsKey.port) as? Int
        let environmentPort = environment["MPD_PORT"].flatMap(UInt16.init)
        let port = savedPort.flatMap(UInt16.init) ?? environmentPort ?? 6600

        let password = defaults.string(forKey: DefaultsKey.password)
            ?? environment["MPD_PASSWORD"]

        return MPDConfiguration(host: host, port: port, password: password)
    }

    private func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let configuration = configuration

        Task {
            let result = await Task.detached {
                do {
                    return PollResult.success(try MPDClient.fetchStatus(configuration: configuration))
                } catch {
                    return PollResult.failure(error.localizedDescription)
                }
            }.value

            refreshInFlight = false
            apply(result)
        }
    }

    private func apply(_ result: PollResult) {
        switch result {
        case .success(let snapshot):
            currentSnapshot = snapshot
            updateConnectedUI(snapshot)
        case .failure(let message):
            currentSnapshot = nil
            updateDisconnectedUI(message)
        }
    }

    private func updateConnectedUI(_ snapshot: MPDSnapshot) {
        let songTitle = snapshot.song?.displayTitle ?? "No current song"
        nowPlayingItem.title = songTitle

        var details: [String] = [stateLabel(snapshot.state)]
        if let elapsed = snapshot.elapsed, let duration = snapshot.duration {
            details.append("\(format(elapsed)) / \(format(duration))")
        }
        if let volume = snapshot.volume, volume >= 0 {
            details.append("Volume \(volume)%")
        }
        detailsItem.title = details.joined(separator: "  •  ")

        let hasSong = snapshot.song != nil
        previousItem.isEnabled = hasSong
        nextItem.isEnabled = hasSong
        toggleItem.isEnabled = true

        let isPlaying = snapshot.state == .playing
        toggleItem.title = isPlaying ? "Pause" : "Play"
        toggleItem.image = symbol(isPlaying ? "pause.fill" : "play.fill")

        guard let button = statusItem.button else { return }
        statusContent.setIcon(symbol(statusSymbol(snapshot.state)))
        switch snapshot.state {
        case .playing, .paused:
            statusContent.setTitle(snapshot.song?.displayTitle ?? "MPD")
        case .stopped, .unknown:
            statusContent.setTitle("MPD")
        }
        button.toolTip = "\(songTitle)\n\(detailsItem.title)"
    }

    private func updateDisconnectedUI(_ message: String) {
        nowPlayingItem.title = "MPD unavailable"
        detailsItem.title = message
        previousItem.isEnabled = false
        toggleItem.isEnabled = false
        nextItem.isEnabled = false

        guard let button = statusItem.button else { return }
        statusContent.setIcon(symbol("exclamationmark.triangle"))
        statusContent.setTitle("MPD Offline")
        button.toolTip = message
    }

    private func stateLabel(_ state: PlaybackState) -> String {
        switch state {
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unknown: "Unknown state"
        }
    }

    private func statusSymbol(_ state: PlaybackState) -> String {
        switch state {
        case .playing: "music.note"
        case .paused: "pause.circle"
        case .stopped: "stop.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func perform(_ command: MPDCommand) {
        let configuration = configuration
        setControlsEnabled(false)

        Task {
            let result = await Task.detached {
                do {
                    try MPDClient.send(command, configuration: configuration)
                    return CommandResult.success
                } catch {
                    return CommandResult.failure(error.localizedDescription)
                }
            }.value

            switch result {
            case .success:
                refresh()
            case .failure(let message):
                updateDisconnectedUI(message)
            }
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        previousItem.isEnabled = enabled
        toggleItem.isEnabled = enabled
        nextItem.isEnabled = enabled
    }

    @objc private func previousTrack() {
        perform(.previous)
    }

    @objc private func togglePlayback() {
        perform(currentSnapshot?.state == .playing ? .pause : .play)
    }

    @objc private func nextTrack() {
        perform(.next)
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func showSettings() {
        let current = configuration
        let alert = NSAlert()
        alert.messageText = "MPD Connection"
        alert.informativeText = "Enter the address of your Music Player Daemon server."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 92))
        let hostField = NSTextField(string: current.host)
        let portField = NSTextField(string: String(current.port))
        let passwordField = NSSecureTextField(string: current.password ?? "")
        addSettingRow(label: "Host", field: hostField, y: 64, to: accessory)
        addSettingRow(label: "Port", field: portField, y: 34, to: accessory)
        addSettingRow(label: "Password", field: passwordField, y: 4, to: accessory)
        alert.accessoryView = accessory

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedHost = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let port = UInt16(portField.stringValue),
              port > 0 else {
            showInvalidSettingsAlert()
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(trimmedHost, forKey: DefaultsKey.host)
        defaults.set(Int(port), forKey: DefaultsKey.port)
        defaults.set(passwordField.stringValue, forKey: DefaultsKey.password)
        refresh()
    }

    private func addSettingRow(label: String, field: NSTextField, y: CGFloat, to view: NSView) {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.frame = NSRect(x: 0, y: y + 2, width: 72, height: 22)
        field.frame = NSRect(x: 80, y: y, width: 240, height: 24)
        view.addSubview(labelField)
        view.addSubview(field)
    }

    private func showInvalidSettingsAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid MPD settings"
        alert.informativeText = "Enter a host and a port between 1 and 65535."
        alert.runModal()
    }
}
