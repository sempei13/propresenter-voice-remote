// ProPresenter Voice Remote: a small Mac window around voice_remote.py.
// Launching the app starts listening. The Listening switch (or Cmd-L) stops
// and restarts the listener; quitting the app (Cmd-Q, the Dock, or closing
// the window) stops it for good.
//
// MIDI: the app shows up to other apps (e.g. ProPresenter) as a MIDI device
// named "ProPresenter Voice Remote". Note On, any channel:
//   60 = toggle listening, 61 = listening on, 62 = listening off.

import AppKit
import CoreMIDI

let MIDI_TOGGLE: UInt8 = 60, MIDI_ON: UInt8 = 61, MIDI_OFF: UInt8 = 62
// Fixed ID so ProPresenter recognizes the same device after every relaunch.
let MIDI_UNIQUE_ID: Int32 = 0x5056_5231  // "PVR1"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var log: NSTextView!
    private var toggle: NSSwitch!
    private var listener: Process?
    private var stopping = false  // true while the user is switching listening off
    private var restartAfterStop = false  // "on" arrived while still switching off
    private var midiClient = MIDIClientRef()
    private var midiIn = MIDIEndpointRef()

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindow()
        setUpMIDI()
        start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ note: Notification) {
        // uv passes SIGTERM on to the Python listener, so this stops both.
        guard let p = listener, p.isRunning else { return }
        p.terminate()
        p.waitUntilExit()
    }

    // ---------------- listener ----------------

    private func start() {
        guard listener == nil else {
            if stopping { restartAfterStop = true; toggle.state = .on }
            return
        }
        toggle.state = .on
        guard let uv = findUV() else {
            fail("Can't find uv. Install it with: brew install uv")
            return
        }
        let script = Bundle.main.path(forResource: "voice_remote", ofType: "py")!
        let p = Process()
        p.executableURL = URL(fileURLWithPath: uv)
        p.arguments = ["run", "--quiet", script]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"  // show each line as soon as it's printed
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"  // lsof lives in /usr/sbin
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.append(text) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.listener === proc else { return }
                self.listener = nil
                if self.stopping {
                    self.stopping = false
                    self.toggle.state = .off
                    self.setStatus("Off. The microphone is released.")
                    self.append("--- listening off ---\n")
                    if self.restartAfterStop {
                        self.restartAfterStop = false
                        self.start()
                    }
                } else {
                    self.fail("Stopped (exit code \(proc.terminationStatus)). "
                              + "Fix the problem above, then turn Listening back on.")
                }
            }
        }
        do {
            try p.run()
            listener = p
            setStatus("Starting…")
        } catch {
            fail("Couldn't start the listener: \(error.localizedDescription)")
        }
    }

    private func stop() {
        restartAfterStop = false
        guard let p = listener, p.isRunning else { return }
        stopping = true
        setStatus("Turning off…")
        p.terminate()  // uv passes SIGTERM on to the Python listener
    }

    private func fail(_ message: String) {
        toggle.state = .off
        setStatus(message)
    }

    private func findUV() -> String? {
        let home = NSHomeDirectory()
        return ["/usr/local/bin/uv", "/opt/homebrew/bin/uv", "\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @objc private func toggleChanged() {
        toggle.state == .on ? start() : stop()
    }

    @objc private func toggleFromMenu() {
        toggle.state = toggle.state == .on ? .off : .on
        toggleChanged()
    }

    // ---------------- MIDI ----------------

    private func setUpMIDI() {
        var err = MIDIClientCreateWithBlock("ProPresenter Voice Remote" as CFString, &midiClient, nil)
        if err == noErr {
            err = MIDIDestinationCreateWithProtocol(
                midiClient, "ProPresenter Voice Remote" as CFString, ._1_0, &midiIn
            ) { [weak self] list, _ in
                for note in Self.noteOns(list) {
                    DispatchQueue.main.async { self?.midiNote(note) }
                }
            }
        }
        guard err == noErr else {
            append("MIDI input unavailable (CoreMIDI error \(err)).\n")
            return
        }
        MIDIObjectSetIntegerProperty(midiIn, kMIDIPropertyUniqueID, MIDI_UNIQUE_ID)
        append("MIDI input ready: \"ProPresenter Voice Remote\" "
               + "(note \(MIDI_TOGGLE) toggle, \(MIDI_ON) on, \(MIDI_OFF) off)\n")
    }

    /// Note numbers of every Note On (velocity > 0) in a MIDI 1.0 event list.
    private static func noteOns(_ list: UnsafePointer<MIDIEventList>) -> [UInt8] {
        var notes: [UInt8] = []
        for packet in list.unsafeSequence() {
            for word in packet.words() where word >> 28 == 0x2 {  // MIDI 1.0 channel voice
                let status = UInt8((word >> 16) & 0xF0)
                let note = UInt8((word >> 8) & 0x7F)
                let velocity = UInt8(word & 0x7F)
                if status == 0x90 && velocity > 0 { notes.append(note) }
            }
        }
        return notes
    }

    private func midiNote(_ note: UInt8) {
        switch note {
        case MIDI_TOGGLE:
            append("MIDI note \(note) -> toggle\n")
            toggleFromMenu()
        case MIDI_ON:
            append("MIDI note \(note) -> listening on\n")
            start()
        case MIDI_OFF:
            append("MIDI note \(note) -> listening off\n")
            toggle.state = .off
            stop()
        default:
            break  // other notes are left for other devices
        }
    }

    // ---------------- window ----------------

    private func append(_ text: String) {
        if text.contains("Listening.") { setStatus("Listening. Say a command.") }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        log.textStorage?.append(NSAttributedString(string: text, attributes: attrs))
        log.scrollToEndOfDocument(nil)
    }

    private func setStatus(_ s: String) { status.stringValue = s }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "ProPresenter Voice Remote"
        window.minSize = NSSize(width: 380, height: 220)
        window.center()
        window.setFrameAutosaveName("MainWindow")

        status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 14, weight: .semibold)
        status.lineBreakMode = .byTruncatingTail

        toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.state = .on
        let toggleLabel = NSTextField(labelWithString: "Listening")
        toggleLabel.font = .systemFont(ofSize: 13)

        let help = NSTextField(labelWithString:
            "\"next slide\" · \"go back\" · \"first slide\" · \"last slide\" · \"next presentation\"")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.lineBreakMode = .byTruncatingTail

        let scroll = NSTextView.scrollableTextView()
        log = (scroll.documentView as! NSTextView)
        log.isEditable = false
        log.textContainerInset = NSSize(width: 6, height: 6)

        let top = NSStackView(views: [toggle, toggleLabel, status])
        top.orientation = .horizontal
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [top, help, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        window.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ProPresenter Voice Remote",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let controlsItem = NSMenuItem()
        main.addItem(controlsItem)
        let controlsMenu = NSMenu(title: "Controls")
        let listenItem = NSMenuItem(title: "Listening On/Off", action: #selector(toggleFromMenu), keyEquivalent: "l")
        listenItem.target = self
        controlsMenu.addItem(listenItem)
        controlsItem.submenu = controlsMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
