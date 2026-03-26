import AppKit
import AVFoundation
import EventKit
import UserNotifications

private struct MeetingInfo: Equatable {
    let date: Date
    let title: String
    let calendarTitle: String?
    var meetingURL: URL? = nil
}

final class MenuHeaderView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        translatesAutoresizingMaskIntoConstraints = false

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = NSFont.menuFont(ofSize: 13)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1

        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            subtitleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            subtitleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: 46)
    }

    func update(title: String, subtitle: String?) {
        titleField.stringValue = title
        titleField.toolTip = title.count > 40 ? title : nil
        subtitleField.stringValue = subtitle ?? ""
        subtitleField.isHidden = subtitle == nil || subtitle?.isEmpty == true
        let accessLabel = subtitle != nil && !subtitle!.isEmpty ? "\(title), \(subtitle!)" : title
        setAccessibilityLabel(accessLabel)
    }
}

private enum AppHolder {
    static let delegate = MeetingCountdownApp()
}

@main
enum OnAirMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = AppHolder.delegate
        app.run()
    }
}

final class MeetingCountdownApp: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    private let countdownVisible = 120
    private let flashAt = 10
    private let broadcast = "((\u{2022}))"
    private let upcomingWindow: TimeInterval = 2 * 60 * 60

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = EKEventStore()
    private let menu = NSMenu()
    private let headerItem = NSMenuItem()
    private let headerView = MenuHeaderView(frame: .zero)
    private let infoSeparator = NSMenuItem.separator()
    private let accessItem = NSMenuItem(
        title: "Enable Calendar Access",
        action: #selector(requestCalendarAccessMenuAction(_:)),
        keyEquivalent: ""
    )
    private let joinMeetingItem = NSMenuItem(
        title: "Join Meeting",
        action: #selector(joinMeetingAction(_:)),
        keyEquivalent: ""
    )
    private let stopAudioItem = NSMenuItem(
        title: "Stop Audio",
        action: #selector(stopAudioMenuAction(_:)),
        keyEquivalent: ""
    )
    private let notificationsItem = NSMenuItem(
        title: "Notifications",
        action: #selector(toggleNotificationsAction(_:)),
        keyEquivalent: ""
    )
    private let testItem = NSMenuItem(
        title: "Test Countdown",
        action: #selector(testCountdownMenuAction(_:)),
        keyEquivalent: ""
    )
    private let quitItem = NSMenuItem(
        title: "Quit",
        action: #selector(quitMenuAction(_:)),
        keyEquivalent: "q"
    )
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var nextEvent: MeetingInfo?
    private var played = false
    private var tickCount = 0
    private var accessRequested = false
    private var accessPrompted = false
    private var audioTrigger = 60
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private let liveSeconds = 60
    private var liveEvent: MeetingInfo?
    private var liveUntil: Date?
    private var testEvent: MeetingInfo?
    private var forceRefetch = false
    private var audioMissing = false

    private var projectDirectory: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }

    private var audioURL: URL? {
        if let bundled = Bundle.main.url(forResource: "countdown", withExtension: "mp3") {
            return bundled
        }

        let fallback = projectDirectory.appendingPathComponent("countdown.mp3")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        audioTrigger = detectedAudioTrigger()
        configureMenu()
        requestCalendarAccessIfNeeded()
        tick()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAudio()
        timer?.invalidate()
    }

    @objc private func handleWake(_ notification: Notification) {
        let now = Date()
        if let liveUntil, now >= liveUntil {
            liveEvent = nil
            self.liveUntil = nil
            testEvent = nil
        }
        if liveEvent == nil, let next = nextEvent, next.date <= now,
           now.timeIntervalSince(next.date) <= Double(liveSeconds) {
            liveEvent = next
            liveUntil = now.addingTimeInterval(Double(liveSeconds))
            nextEvent = nil
        }
        forceRefetch = true
    }

    @objc private func stopAudioMenuAction(_ sender: Any?) {
        stopAudio()
    }

    @objc private func joinMeetingAction(_ sender: Any?) {
        guard let url = (liveEvent ?? nextEvent)?.meetingURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func requestCalendarAccessMenuAction(_ sender: Any?) {
        requestCalendarAccessIfNeeded(force: true)
    }

    @objc private func quitMenuAction(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func toggleNotificationsAction(_ sender: Any?) {
        if notificationsItem.state == .on {
            UserDefaults.standard.set(false, forKey: "notificationsEnabled")
            notificationsItem.state = .off
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                    self.notificationsItem.state = .on
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Notifications Disabled"
                    alert.informativeText = "Enable notifications in System Settings → Notifications → On Air"
                    alert.runModal()
                }
            }
        }
    }

    @objc private func testCountdownMenuAction(_ sender: Any?) {
        liveEvent = nil
        liveUntil = nil
        played = false
        stopAudio()
        let fakeDate = Date().addingTimeInterval(Double(audioTrigger + 10))
        testEvent = MeetingInfo(date: fakeDate, title: "Test Meeting", calendarTitle: nil)
        nextEvent = testEvent
        tick()
    }

    private func configureMenu() {
        menu.autoenablesItems = false

        headerItem.view = headerView
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(infoSeparator)

        accessItem.target = self
        menu.addItem(accessItem)
        joinMeetingItem.target = self
        joinMeetingItem.isHidden = true
        menu.addItem(joinMeetingItem)
        stopAudioItem.target = self
        menu.addItem(stopAudioItem)
        notificationsItem.target = self
        menu.addItem(notificationsItem)

        menu.addItem(.separator())

        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuForNoMeeting()
        updateStopAudioVisibility()
        restoreNotificationsToggle()
    }

    private func restoreNotificationsToggle() {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                if settings.authorizationStatus == .authorized {
                    self.notificationsItem.state = .on
                } else {
                    UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                    self.notificationsItem.state = .off
                }
            }
        }
    }

    private func sendMeetingNotification(for meeting: MeetingInfo?, secondsLeft: Int) {
        guard let meeting else { return }
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        if secondsLeft < 60 {
            content.body = "Starts in less than a minute"
        } else if secondsLeft < 120 {
            content.body = "Starts in 1 minute"
        } else {
            content.body = "Starts in \(Int(ceil(Double(secondsLeft) / 60.0))) minutes"
        }
        let id = meeting.date.formatted(.iso8601)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    private func hasCalendarAccess() -> Bool {
        let status = authorizationStatus()
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    private func requestCalendarAccessIfNeeded(force: Bool = false) {
        let status = authorizationStatus()

        if status == .notDetermined {
            if accessRequested || (accessPrompted && !force) {
                return
            }

            accessRequested = true
            accessPrompted = true

            let completion: (Bool, Error?) -> Void = { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.accessRequested = false
                    if granted {
                        self.nextEvent = nil
                    }
                    self.tick()
                }
            }

            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents(completion: completion)
            } else {
                store.requestAccess(to: .event, completion: completion)
            }
            return
        }

        if force {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            setStatus(broadcast)
            updateMenuForAccess(status: status)
        }
    }

    private func fetchNextEvent(from now: Date) -> MeetingInfo? {
        let end = now.addingTimeInterval(upcomingWindow)
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.startDate > now else { return false }
                if event.availability == .free { return false }
                if let attendees = event.attendees,
                   let me = attendees.first(where: { $0.isCurrentUser }),
                   me.participantStatus == .declined {
                    return false
                }
                return true
            }
            .sorted { $0.startDate < $1.startDate }

        guard let event = events.first else {
            return nil
        }

        let title = event.title?.isEmpty == false ? event.title! : "Meeting"
        let calendarTitle = event.calendar.title.isEmpty ? nil : event.calendar.title
        return MeetingInfo(date: event.startDate, title: title, calendarTitle: calendarTitle,
                           meetingURL: extractMeetingURL(from: event))
    }

    private func isMeetingService(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        if (host == "teams.microsoft.com" || host == "teams.live.com") &&
           (path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")) { return true }
        if (host == "zoom.us" || host.hasSuffix(".zoom.us")) && path.hasPrefix("/j/") { return true }
        if host == "meet.google.com" { return true }
        if host == "webex.com" || host.hasSuffix(".webex.com") { return true }
        return false
    }

    private func extractMeetingURL(from event: EKEvent) -> URL? {
        if let url = event.url, url.scheme?.lowercased() == "https", isMeetingService(url) {
            return url
        }

        let fields = [event.notes, event.location].compactMap { $0 }
        let pattern = try! NSRegularExpression(pattern: "https://[^\\s<>\"')\\],;]+", options: [])
        var firstGeneric: URL?

        for field in fields {
            let range = NSRange(field.startIndex..., in: field)
            let matches = pattern.matches(in: field, range: range)
            for match in matches {
                guard let matchRange = Range(match.range, in: field) else { continue }
                let raw = String(field[matchRange])
                guard let url = URL(string: raw) else { continue }
                if isMeetingService(url) { return url }
                if firstGeneric == nil { firstGeneric = url }
            }
        }

        if let url = event.url, url.scheme?.lowercased() == "https" { return url }
        return firstGeneric
    }

    private func tick() {
        tickCount += 1
        let now = Date()

        if !hasCalendarAccess() && testEvent == nil {
            stopAudio()
            nextEvent = nil
            liveEvent = nil
            liveUntil = nil
            requestCalendarAccessIfNeeded()
            let status = authorizationStatus()
            setStatus(broadcast)
            updateMenuForAccess(status: status)
            updateStopAudioVisibility()
            return
        }

        if let liveUntil, now >= liveUntil {
            self.liveEvent = nil
            self.liveUntil = nil
            self.testEvent = nil
        }

        if testEvent != nil {
            if nextEvent == nil && liveEvent == nil {
                nextEvent = testEvent
                played = false
            }
        } else if nextEvent == nil || tickCount % 30 == 0 || forceRefetch {
            let fresh = fetchNextEvent(from: now)
            if fresh != nextEvent {
                if fresh?.date != nextEvent?.date {
                    stopAudio()
                    played = false
                }
                nextEvent = fresh
            }
            forceRefetch = false
        }

        guard let nextEvent else {
            if let liveEvent {
                setStatus("\(broadcast) LIVE", pill: true)
                updateMenuForLiveMeeting(liveEvent)
            } else {
                stopAudio()
                setStatus(broadcast)
                updateMenuForNoMeeting()
            }
            updateStopAudioVisibility()
            return
        }

        let secondsLeft = Int(nextEvent.date.timeIntervalSince(now))

        if secondsLeft <= 0 {
            stopAudio()
            if nextEvent != testEvent { testEvent = nil }
            liveEvent = nextEvent
            liveUntil = now.addingTimeInterval(Double(liveSeconds))
            self.nextEvent = nil
            self.played = false
            setStatus("\(broadcast) LIVE", pill: true)
            updateMenuForLiveMeeting(liveEvent!)
            updateStopAudioVisibility()
            return
        }

        if let liveEvent, secondsLeft > audioTrigger {
            setStatus("\(broadcast) LIVE", pill: true)
            updateMenuForLiveMeeting(liveEvent)
            updateStopAudioVisibility()
            return
        }

        if liveEvent != nil {
            self.liveEvent = nil
            self.liveUntil = nil
        }

        let label = compactLabel(for: secondsLeft)
        updateMenuForMeeting(nextEvent, secondsLeft: secondsLeft)

        // Flash alternates between red pill (shape + color) and plain text (no shape),
        // providing both a color and a shape cue for accessibility.
        if secondsLeft <= flashAt {
            setImage(label, red: tickCount.isMultiple(of: 2))
        } else if secondsLeft <= audioTrigger {
            setStatus(label, pill: true)
        } else {
            setStatus(label)
        }

        if secondsLeft <= audioTrigger && !played {
            let audioStarted = playAudio()
            played = true
            if audioStarted && testEvent == nil && UserDefaults.standard.bool(forKey: "notificationsEnabled") {
                sendMeetingNotification(for: nextEvent, secondsLeft: secondsLeft)
            }
        }

        updateStopAudioVisibility()
    }

    private func detectedAudioTrigger() -> Int {
        guard let audioURL else {
            return 60
        }

        guard let player = try? AVAudioPlayer(contentsOf: audioURL) else {
            return 60
        }

        return max(1, Int(ceil(player.duration)))
    }

    @discardableResult
    private func playAudio() -> Bool {
        stopAudio()

        guard let audioURL else {
            audioMissing = true
            return false
        }

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            audioMissing = false
        } catch {
            audioPlayer = nil
        }

        updateStopAudioVisibility()
        return audioPlayer != nil
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        updateStopAudioVisibility()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        updateStopAudioVisibility()
    }

    private func setStatus(_ text: String, pill: Bool = false) {
        guard let button = statusItem.button else {
            return
        }

        if pill {
            button.image = renderPill(
                text: text,
                background: .systemRed,
                foreground: .white
            )
            button.title = ""
        } else {
            button.image = nil
            button.title = text
        }

        button.toolTip = currentTooltip()
    }

    private func setImage(_ text: String, red: Bool) {
        guard let button = statusItem.button else {
            return
        }

        button.image = renderPill(
            text: text,
            background: red ? .systemRed : nil,
            foreground: red ? .white : .labelColor
        )
        button.title = ""
        button.toolTip = currentTooltip()
    }

    private func compactLabel(for secondsLeft: Int) -> String {
        if secondsLeft <= countdownVisible {
            let minutes = secondsLeft / 60
            let seconds = secondsLeft % 60
            return "\(broadcast) \(minutes):" + String(format: "%02d", seconds)
        }

        let roundedMinutes = max(1, Int(ceil(Double(secondsLeft) / 60.0)))
        return "\(broadcast) \(roundedMinutes)m"
    }

    private func detailCountdown(for secondsLeft: Int) -> String {
        if secondsLeft <= countdownVisible {
            let minutes = secondsLeft / 60
            let seconds = secondsLeft % 60
            return "\(minutes):" + String(format: "%02d", seconds)
        }

        let roundedMinutes = max(1, Int(ceil(Double(secondsLeft) / 60.0)))
        return "\(roundedMinutes)m"
    }

    private func updateMenuForMeeting(_ meeting: MeetingInfo, secondsLeft: Int) {
        var metadata = "\(timeFormatter.string(from: meeting.date)) (\(detailCountdown(for: secondsLeft)))"
        if audioMissing && secondsLeft <= audioTrigger {
            metadata += " · No audio"
        }
        if let calendarTitle = meeting.calendarTitle {
            metadata += " · \(calendarTitle)"
        }

        headerView.update(title: meeting.title, subtitle: metadata)
        headerItem.isHidden = false
        infoSeparator.isHidden = false
        accessItem.isHidden = true
        updateJoinMeetingVisibility()
    }

    private func updateMenuForLiveMeeting(_ meeting: MeetingInfo) {
        var metadata = "\(timeFormatter.string(from: meeting.date)) (LIVE)"
        if let calendarTitle = meeting.calendarTitle {
            metadata += " · \(calendarTitle)"
        }
        headerView.update(title: meeting.title, subtitle: metadata)
        headerItem.isHidden = false
        infoSeparator.isHidden = false
        accessItem.isHidden = true
        updateJoinMeetingVisibility()
    }

    private func updateMenuForNoMeeting() {
        headerView.update(
            title: "No meetings in next 2 hours",
            subtitle: "On Air is watching your calendar."
        )
        headerItem.isHidden = false
        infoSeparator.isHidden = false
        accessItem.isHidden = true
        updateJoinMeetingVisibility()
    }

    private func updateMenuForAccess(status: EKAuthorizationStatus) {
        if status == .notDetermined || accessRequested {
            headerView.update(
                title: "Requesting Calendar access…",
                subtitle: "Allow On Air to read your calendar."
            )
        } else {
            headerView.update(
                title: "Calendar access needed",
                subtitle: "Grant access in System Settings or reinstall."
            )
        }

        headerItem.isHidden = false
        infoSeparator.isHidden = false
        accessItem.isHidden = false
        joinMeetingItem.isHidden = true
    }

    private func updateStopAudioVisibility() {
        stopAudioItem.isHidden = false
        stopAudioItem.isEnabled = audioPlayer?.isPlaying ?? false
    }

    private func updateJoinMeetingVisibility() {
        let meeting = liveEvent ?? nextEvent
        let isTest = testEvent != nil && meeting == testEvent
        let hasURL = meeting?.meetingURL != nil && !isTest
        joinMeetingItem.isHidden = !hasURL
    }

    private func currentTooltip() -> String {
        guard hasCalendarAccess() || testEvent != nil else {
            return "On Air — Calendar access needed"
        }

        let event = liveEvent ?? nextEvent
        guard let event else {
            return "On Air"
        }

        let startTime = timeFormatter.string(from: event.date)
        let verb = liveEvent != nil ? "Started at" : "Starts at"
        if let calendarTitle = event.calendarTitle {
            return "\(event.title)\n\(verb) \(startTime)\n\(calendarTitle)"
        }

        return "\(event.title)\n\(verb) \(startTime)"
    }

    private func renderPill(text: String, background: NSColor?, foreground: NSColor) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
        ]

        let textSize = (text as NSString).size(withAttributes: attributes)
        let height: CGFloat = 22
        let paddingX: CGFloat = 8
        let width = ceil(textSize.width + (paddingX * 2))
        let paddingY = (height - textSize.height) / 2

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if let background {
                background.setFill()
                let pillRect = NSRect(x: 0, y: 1, width: width, height: height - 2)
                NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5).fill()
            }

            (text as NSString).draw(
                at: NSPoint(x: paddingX, y: paddingY),
                withAttributes: attributes
            )

            return true
        }
        image.isTemplate = false
        return image
    }
}
