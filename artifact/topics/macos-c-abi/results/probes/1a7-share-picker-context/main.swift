// Probe for macos-c-abi 1a-7: can NSSharingServicePicker be shown outside a real mouseDown
// (from GCD, a main-actor Task, a keyDown, or a synthetic mouseDown)? The picker is only shown
// and then closed with close(); no service is chosen and nothing is sent.
import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ntk-1a7.jsonl"
FileManager.default.createFile(atPath: outPath, contents: nil)
let out = FileHandle(forWritingAtPath: outPath)!
let t0 = Date()
func log(_ s: String) {
    out.write((String(format: "%.3f ", Date().timeIntervalSince(t0)) + s + "\n").data(using: .utf8)!)
}

final class Delegate: NSObject, NSSharingServicePickerDelegate {
    var scenario = ""
    func sharingServicePicker(_ p: NSSharingServicePicker, didChoose service: NSSharingService?) {
        log("\(scenario) didChoose service=\(service?.title ?? "nil")")
    }
}
let delegate = Delegate()

final class AnchorView: NSView {
    var onMouseDown: (() -> Void)?
    var onKeyDown: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { log("\(delegate.scenario) mouseDown handler"); onMouseDown?() }
    override func keyDown(with event: NSEvent) { log("\(delegate.scenario) keyDown handler"); onKeyDown?() }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
let anchor = AnchorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
window.contentView = anchor
window.title = "ntk probe 1a-7"

func visibleWindowSummary() -> String {
    app.windows.filter { $0.isVisible && $0 !== window }.map { String(describing: type(of: $0)) }.joined(separator: ",")
}

func show(_ scenario: String) {
    delegate.scenario = scenario
    let picker = NSSharingServicePicker(items: ["ntk probe text"])
    picker.delegate = delegate
    log("\(scenario) show begin isMain=\(Thread.isMainThread) currentEvent=\(String(describing: app.currentEvent?.type.rawValue))")
    picker.show(relativeTo: NSRect(x: 190, y: 140, width: 20, height: 20), of: anchor, preferredEdge: .minY)
    log("\(scenario) show returned")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        log("\(scenario) after1.5s otherVisibleWindows=[\(visibleWindowSummary())]")
        picker.close()
        log("\(scenario) close called")
    }
}

var steps: [(String, () -> Void)] = []
func next() {
    guard !steps.isEmpty else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { log("done"); exit(0) }; return }
    let (name, run) = steps.removeFirst()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { delegate.scenario = name; run(); DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { next() } }
}
steps.append(("S1-gcd", { DispatchQueue.main.async { show("S1-gcd") } }))
steps.append(("S2-mainActorTask", { Task { @MainActor in show("S2-mainActorTask") } }))
steps.append(("S3-syntheticMouseDown", {
    anchor.onMouseDown = { show("S3-syntheticMouseDown") }
    let p = NSPoint(x: 200, y: 150)
    let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    app.postEvent(e, atStart: false)
}))
steps.append(("S4-syntheticKeyDown", {
    anchor.onMouseDown = nil
    anchor.onKeyDown = { show("S4-syntheticKeyDown") }
    window.makeFirstResponder(anchor)
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
    app.postEvent(e, atStart: false)
}))
steps.append(("S5-backgroundThreadDirect", { DispatchQueue.global().async { DispatchQueue.main.async { show("S5-fromBackgroundViaGCD") } } }))

log("start os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
next()
app.run()
