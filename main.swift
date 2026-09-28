import Cocoa
import ServiceManagement

// ───────────────────────────────────────────────── DOI extraction

/// Accept a bare DOI, a doi.org URL, or a publisher URL (IOP, APS, Nature…)
/// and return just the DOI body.
func extractDOI(_ raw: String) -> String {
    if let id = arxivID(raw) { return "10.48550/arXiv.\(id)" }
    let decoded = raw.removingPercentEncoding ?? raw
    let s = decoded.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let re = try? NSRegularExpression(pattern: #"10\.\d{4,9}/[^\s"<>]+"#),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let r = Range(m.range, in: s) else { return s }

    var doi = String(s[r])
    doi = doi.components(separatedBy: "?")[0].components(separatedBy: "#")[0]

    // Strip publisher path suffixes that follow the DOI in a URL.
    if let re2 = try? NSRegularExpression(
        pattern: #"/(meta|pdf|fulltext|abstract|full|references|citations)/?$"#,
        options: .caseInsensitive) {
        doi = re2.stringByReplacingMatches(
            in: doi, range: NSRange(doi.startIndex..., in: doi), withTemplate: "")
    }
    return doi.trimmingCharacters(in: CharacterSet(charactersIn: "/.,;"))
}

/// Normalize modern and legacy arXiv identifiers, dropping optional versions.
func arxivID(_ raw: String) -> String? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: value), let host = url.host,
       ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(host.lowercased()) {
        value = url.path
        for prefix in ["/abs/", "/pdf/", "/html/"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)); break
        }
    }
    value = value.replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
    let pattern = #"^(\d{4}\.\d{4,5}|[a-zA-Z-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?(?:\.pdf)?/?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value) else { return nil }
    return String(value[range])
}

func looksLikeDOI(_ s: String) -> Bool {
    arxivID(s) != nil || s.range(of: #"10\.\d{4,9}/"#, options: .regularExpression) != nil
}

/// Pull the citation key out of "@article{Key2018,…}" for the status line.
func bibKey(_ s: String) -> String {
    guard let open = s.range(of: "{"),
          let comma = s.range(of: ",", range: open.upperBound..<s.endIndex) else { return "entry" }
    return String(s[open.upperBound..<comma.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// ───────────────────────────────────────────────── ADS token

/// Stored in the app's own preferences, not the Keychain — the Keychain is what
/// makes macOS ask for a password on every rebuild. Set it once via the
/// right-click menu ("Set ADS Token…") and it persists untouched thereafter.
/// Saved settings take priority over the optional environment variable.
let adsTokenKey = "ADSAPIToken"
let appPreferences = UserDefaults(suiteName: "org.bibgrab.settings")!

func adsToken() -> String? {
    if let t = appPreferences.string(forKey: adsTokenKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
    if let t = ProcessInfo.processInfo.environment["ADS_API_TOKEN"], !t.isEmpty { return t }
    return nil
}

func setADSToken(_ raw: String) {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty {
        appPreferences.removeObject(forKey: adsTokenKey)
    } else {
        appPreferences.set(t, forKey: adsTokenKey)
    }
    appPreferences.synchronize()
}

// ───────────────────────────────────────────────── Sources

typealias BibResult = (String?, String?) -> Void   // (bibtex, error)

func fetchADS(doi: String, token: String, done: @escaping BibResult) {
    var c = URLComponents(string: "https://api.adsabs.harvard.edu/v1/search/query")!
    c.queryItems = [
        URLQueryItem(name: "q", value: doi.lowercased().hasPrefix("10.48550/arxiv.")
            ? "identifier:\"arXiv:\(doi.dropFirst(16))\"" : "doi:\"\(doi)\""),
        URLQueryItem(name: "fl", value: "bibcode"),
        URLQueryItem(name: "rows", value: "1"),
    ]
    var req = URLRequest(url: c.url!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.timeoutInterval = 20

    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { done(nil, err.localizedDescription); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            done(nil, code == 401 ? "bad ADS token" : "ADS HTTP \(code)"); return
        }
        guard let data = data,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = j["response"] as? [String: Any],
              let docs = r["docs"] as? [[String: Any]] else {
            done(nil, "unreadable ADS reply"); return
        }
        guard let bibcode = docs.first?["bibcode"] as? String else {
            done(nil, "not in ADS"); return
        }

        var er = URLRequest(url: URL(string: "https://api.adsabs.harvard.edu/v1/export/bibtex")!)
        er.httpMethod = "POST"
        er.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        er.setValue("application/json", forHTTPHeaderField: "Content-Type")
        er.httpBody = try? JSONSerialization.data(withJSONObject: ["bibcode": [bibcode]])
        er.timeoutInterval = 20

        URLSession.shared.dataTask(with: er) { d2, response, e2 in
            if let e2 = e2 { done(nil, e2.localizedDescription); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { done(nil, "ADS export HTTP \(code)"); return }
            guard let d2 = d2,
                  let j2 = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
                  let ex = j2["export"] as? String, !ex.isEmpty else {
                done(nil, "ADS export failed"); return
            }
            done(ex.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }.resume()
    }.resume()
}

/// DOI content negotiation routes to Crossref, DataCite, or another registry.
func fetchCrossref(doi: String, done: @escaping BibResult) {
    let path = doi.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%"))) ?? doi
    guard let url = URL(string: "https://doi.org/\(path)") else {
        done(nil, "bad DOI"); return
    }
    var req = URLRequest(url: url)
    req.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")
    req.timeoutInterval = 30

    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { done(nil, err.localizedDescription); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let data = data,
              let s = String(data: data, encoding: .utf8),
              s.contains("@") else {
            done(nil, code == 404 ? "DOI not found" : "DOI service HTTP \(code)"); return
        }
        done(s.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }.resume()
}

// ───────────────────────────────────────────────── Editing support

/// An accessory (LSUIElement) app has no main menu, so NSTextField never
/// receives ⌘V/⌘C/⌘X/⌘A. Handle them on the field itself as a belt-and-braces
/// companion to the Edit menu installed below.
final class EditableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let sel: Selector?
        switch key {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSResponder.selectAll(_:))
        case "z": sel = Selector(("undo:"))
        default:  sel = nil
        }
        if let sel = sel, NSApp.sendAction(sel, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Even accessory apps route key equivalents through NSApp.mainMenu, so this
/// restores standard editing shortcuts app-wide (including in the output view).
func installMainMenu() {
    let main = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit BibGrab",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All",
                 action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)

    NSApp.mainMenu = main
}

// ───────────────────────────────────────────────── Window

final class BibWindow: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let panel: NSPanel
    let field = EditableTextField()
    let status = NSTextField(labelWithString: "")
    let output = NSTextView()
    var onSubmit: ((String) -> Void)?

    /// Popover-style dismissal: vanish as soon as focus goes elsewhere, so it
    /// never has to be closed by hand. Suspended while a modal sheet is up.
    var autoHide = true
    /// When the click that opened the menu bar item also dismissed the panel,
    /// so the toggle doesn't immediately reopen it.
    var lastAutoHide = Date.distantPast

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        super.init()

        panel.title = "BibGrab"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 200)
        panel.delegate = self
        // Remembers the size you drag it to; position is set on each open.
        panel.setFrameAutosaveName("BibGrabPanel")

        buildUI()
    }

    func windowDidResignKey(_ note: Notification) {
        guard autoHide else { return }
        panel.orderOut(nil)
        lastAutoHide = Date()
    }

    private func buildUI() {
        let c = NSView()
        panel.contentView = c

        let title = NSTextField(labelWithString: "DOI · arXiv · publisher URL")
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor

        field.placeholderString = "10.1103/PhysRevB.98.045103"
        field.font = .systemFont(ofSize: 13)
        field.delegate = self
        field.target = self
        field.action = #selector(submit)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true

        output.isEditable = false
        output.isSelectable = true
        output.drawsBackground = false
        output.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        output.textContainerInset = NSSize(width: 6, height: 6)
        output.minSize = NSSize(width: 0, height: 0)
        output.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        output.isVerticallyResizable = true
        output.isHorizontallyResizable = false
        output.autoresizingMask = [.width]
        output.textContainer?.widthTracksTextView = true
        output.string = "BibTeX appears here and is copied to the clipboard."
        scroll.documentView = output

        for v in [title, field, status, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(v)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: c.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),

            field.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            field.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),

            status.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -14),
        ])
    }

    @objc func submit() {
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        onSubmit?(raw)
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            panel.orderOut(nil)
            return true
        }
        return false
    }

    func setStatus(_ s: String, ok: Bool?) {
        status.stringValue = s
        switch ok {
        case .some(true):  status.textColor = .systemGreen
        case .some(false): status.textColor = .systemRed
        default:           status.textColor = .secondaryLabelColor
        }
    }

    func setOutput(_ s: String) { output.string = s }

    /// Prefill from the clipboard when it already holds a DOI — the common case
    /// is copying a DOI in the browser, then clicking this.
    func show(under button: NSStatusBarButton?) {
        // Drop it under the menu bar icon each time, popover-style, while
        // keeping whatever size you dragged it to.
        if let b = button, let bw = b.window {
            let onScreen = bw.convertToScreen(b.convert(b.bounds, to: nil))
            var f = panel.frame
            f.origin.x = onScreen.midX - f.width / 2
            f.origin.y = onScreen.minY - f.height - 6
            if let vis = (bw.screen ?? NSScreen.main)?.visibleFrame {
                f.origin.x = min(max(f.origin.x, vis.minX + 8), vis.maxX - f.width - 8)
                f.origin.y = max(f.origin.y, vis.minY + 8)
            }
            panel.setFrameOrigin(f.origin)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if field.stringValue.isEmpty,
           let clip = NSPasteboard.general.string(forType: .string),
           looksLikeDOI(clip) {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    var isVisible: Bool { panel.isVisible }
    func hide() { panel.orderOut(nil) }
}

// ───────────────────────────────────────────────── Controller

final class Controller: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let win = BibWindow()

    override init() {
        super.init()
        item.autosaveName = "BibGrab"
        if let img = NSImage(systemSymbolName: "text.book.closed",
                             accessibilityDescription: "BibGrab") {
            item.button?.image = img
        } else {
            item.button?.title = "BIB"
        }
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        win.onSubmit = { [weak self] raw in self?.handle(raw) }
    }

    @objc func clicked() {
        if let e = NSApp.currentEvent, e.type == .rightMouseUp { showMenu(); return }
        if win.isVisible {
            win.hide()
        } else if Date().timeIntervalSince(win.lastAutoHide) < 0.3 {
            // This same click already dismissed it — leave it closed.
        } else {
            win.show(under: item.button)
        }
    }

    private func showMenu() {
        let m = NSMenu()
        let have = adsToken()
        let label: String
        if let h = have, h.count > 8 {
            label = "ADS token: saved (default)"
        } else if have != nil {
            label = "ADS token: set"
        } else {
            label = "ADS token: not set (DOI services only)"
        }
        let t = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        t.isEnabled = false
        m.addItem(t)

        let edit = NSMenuItem(title: "Set ADS Token…",
                              action: #selector(editToken), keyEquivalent: "")
        edit.target = self
        m.addItem(edit)
        m.addItem(.separator())

        let l = NSMenuItem(title: "Launch at Login",
                           action: #selector(toggleLogin), keyEquivalent: "")
        l.target = self
        l.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(l)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q"))

        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil          // restore click-to-open
    }

    @objc func editToken() {
        let a = NSAlert()
        a.messageText = "ADS API Token"
        a.informativeText = """
            Saved in this app's preferences and reused from then on — no password \
            prompt. Clear the field to fall back to DOI services only.

            Get one at ui.adsabs.harvard.edu/user/settings/token
            """
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")

        // EditableTextField so ⌘V works inside the dialog too.
        let tf = EditableTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        tf.stringValue = adsToken() ?? ""
        tf.placeholderString = "paste your ADS token"
        tf.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        a.accessoryView = tf

        // The alert takes key focus; without this the panel would auto-hide.
        win.autoHide = false
        defer { win.autoHide = true }

        NSApp.activate(ignoringOtherApps: true)
        a.window.initialFirstResponder = tf

        if a.runModal() == .alertFirstButtonReturn {
            setADSToken(tf.stringValue)
            win.setStatus(adsToken() != nil ? "ADS token saved" : "ADS token cleared",
                          ok: adsToken() != nil)
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { NSLog("launch-at-login failed: \(error)") }
    }

    private func handle(_ raw: String) {
        let doi = extractDOI(raw)
        guard looksLikeDOI(doi) else { win.setStatus("Enter a DOI or arXiv link", ok: false); return }
        win.setStatus("Looking up \(doi) …", ok: nil)

        let finish: BibResult = { [weak self] bib, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let bib = bib else {
                    self.win.setStatus("✗ \(err ?? "failed")", ok: false); return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(bib, forType: .string)
                self.win.setStatus("✓ Copied  \(bibKey(bib))", ok: true)
                self.win.setOutput(bib)
                self.win.field.stringValue = ""
            }
        }

        guard let token = adsToken() else {
            win.setStatus("No ADS token — trying DOI services …", ok: nil)
            fetchCrossref(doi: doi, done: finish)
            return
        }

        fetchADS(doi: doi, token: token) { [weak self] bib, err in
            if bib != nil { finish(bib, nil); return }
            DispatchQueue.main.async {
                self?.win.setStatus("ADS: \(err ?? "miss") → DOI services …", ok: nil)
            }
            fetchCrossref(doi: doi) { fallback, fallbackError in
                finish(fallback, fallback == nil ? "ADS: \(err ?? "failed"); DOI: \(fallbackError ?? "failed")" : nil)
            }
        }
    }
}

// ───────────────────────────────────────────────── Entry

// Terminal mode:  BibGrab --doi <string>   → prints BibTeX, also copies it.
if let i = CommandLine.arguments.firstIndex(of: "--doi"),
   i + 1 < CommandLine.arguments.count {
    let doi = extractDOI(CommandLine.arguments[i + 1])
    guard looksLikeDOI(doi) else {
        print("failed: enter a DOI or arXiv link"); exit(1)
    }
    let sem = DispatchSemaphore(value: 0)
    var succeeded = false
    let show: BibResult = { bib, err in
        if let bib = bib {
            succeeded = true
            if !CommandLine.arguments.contains("--no-copy") {
                let pb = NSPasteboard.general
                pb.clearContents(); pb.setString(bib, forType: .string)
            }
            print(bib)
        } else {
            print("failed: \(err ?? "unknown")")
        }
        sem.signal()
    }
    if let tok = adsToken() {
        fetchADS(doi: doi, token: tok) { b, e in
            if b != nil { show(b, nil) } else {
                print("ADS: \(e ?? "miss") → DOI services")
                fetchCrossref(doi: doi, done: show)
            }
        }
    } else {
        fetchCrossref(doi: doi, done: show)
    }
    guard sem.wait(timeout: .now() + 75) == .success else {
        print("failed: lookup timed out"); exit(1)
    }
    exit(succeeded ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
installMainMenu()
let controller = Controller()
app.run()
