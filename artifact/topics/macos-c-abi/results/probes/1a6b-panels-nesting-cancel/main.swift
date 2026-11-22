// Probe for macos-c-abi 1a-6 (part 2): file panels under A / A', a second dialog in the same turn
// (nested vs queued), and cancelling only our own modal while a host modal exists.
// Everything closes itself; no user input is needed. Run only in the test VM.
import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ntk-1a6b.jsonl"
FileManager.default.createFile(atPath: outPath, contents: nil)
let out = FileHandle(forWritingAtPath: outPath)!
let t0 = Date()
func log(_ s: String) { out.write((String(format: "%.3f ", Date().timeIntervalSince(t0)) + s + "\n").data(using: .utf8)!) }

// Enter a block outside any GCD block (option A').
func onRunLoop(_ body: @escaping () -> Void) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, body)
    CFRunLoopWakeUp(CFRunLoopGetMain())
}
func safety(_ seconds: TimeInterval, _ label: String) -> Timer {
    let t = Timer(timeInterval: seconds, repeats: false) { _ in log("\(label) safety abort"); NSApp.abortModal() }
    RunLoop.main.add(t, forMode: .modalPanel)
    return t
}
func probeDeliveries(_ label: String, modalOpen: @escaping () -> Bool) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        DispatchQueue.main.async { log("\(label) gcd ran duringModal=\(modalOpen())") }
        Task { @MainActor in log("\(label) task ran duringModal=\(modalOpen())") }
    }
}

// --- P: file panels ---
func runPanel(_ label: String, viaGCD: Bool, done: @escaping () -> Void) {
    let body = {
        let panel = NSOpenPanel()
        panel.message = "ntk probe \(label)"
        var open = true
        let s = safety(4, label)
        probeDeliveries(label) { open }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            DispatchQueue.main.async { log("\(label) gcd-cancel ran open=\(open)"); if open { NSApp.abortModal() } }
        }
        log("\(label) runModal-enter")
        let r = panel.runModal()
        open = false; s.invalidate()
        log("\(label) runModal-return response=\(r.rawValue)")
        done()
    }
    if viaGCD { DispatchQueue.main.async(execute: body) } else { onRunLoop(body) }
}

// --- N: second dialog in the same turn ---
final class Presenter {
    var active = false
    var pending: [() -> Void] = []
    func present(_ show: @escaping (@escaping () -> Void) -> Void) {
        onRunLoop {
            if self.active { self.pending.append({ self.present(show) }); log("queued") ; return }
            self.active = true
            show {
                self.active = false
                if !self.pending.isEmpty { self.pending.removeFirst()() }
            }
        }
    }
}
func alert(_ name: String, closeAfter: TimeInterval, finished: @escaping () -> Void) {
    let a = NSAlert(); a.messageText = "ntk probe \(name)"; a.addButton(withTitle: "OK")
    let t = Timer(timeInterval: closeAfter, repeats: false) { _ in
        if NSApp.modalWindow === a.window { log("\(name) timer close own"); NSApp.abortModal() } else { log("\(name) timer: not frontmost modal, skip") }
    }
    RunLoop.main.add(t, forMode: .modalPanel)
    let s = safety(8, name)
    log("\(name) enter")
    let r = a.runModal()
    t.invalidate(); s.invalidate()
    log("\(name) return response=\(r.rawValue)")
    finished()
}

// --- H: host modal plus ours; cancel only ours ---
var ourAlert: NSAlert?
func cancelOurs(_ label: String) {
    DispatchQueue.global().async {
        DispatchQueue.main.async {
            let ours = ourAlert?.window
            let front = NSApp.modalWindow
            if let ours, front === ours { log("\(label) cancel: ours is frontmost -> abort"); NSApp.abortModal() }
            else { log("\(label) cancel: ours is not frontmost (front is \(front === nil ? "none" : "other")) -> refuse") }
        }
    }
}

var steps: [(String, (@escaping () -> Void) -> Void)] = []
func next() {
    guard !steps.isEmpty else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { log("done"); exit(0) }; return }
    let (name, run) = steps.removeFirst()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { log("== \(name)"); run { next() } }
}
steps.append(("P-A-openPanel-gcdEntry", { done in runPanel("P-A", viaGCD: true, done: done) }))
steps.append(("P-Aprime-openPanel-runLoopEntry", { done in runPanel("P-A'", viaGCD: false, done: done) }))
steps.append(("N1-naive-twoRequests", { done in
    var finished = 0
    let fin = { finished += 1; if finished == 2 { done() } }
    onRunLoop { alert("N1-first", closeAfter: 2.0, finished: fin) }
    onRunLoop { alert("N1-second", closeAfter: 1.0, finished: fin) }
}))
steps.append(("N2-queued-twoRequests", { done in
    let p = Presenter(); var finished = 0
    let fin = { finished += 1; if finished == 2 { done() } }
    p.present { end in alert("N2-first", closeAfter: 1.0) { end(); fin() } }
    p.present { end in alert("N2-second", closeAfter: 1.0) { end(); fin() } }
}))
steps.append(("H1-hostBelow-oursOnTop-cancelOurs", { done in
    onRunLoop {
        let host = NSAlert(); host.messageText = "ntk probe host modal"; host.addButton(withTitle: "OK")
        let hs = safety(6, "H1-host")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            onRunLoop {
                let a = NSAlert(); a.messageText = "ntk probe ours"; a.addButton(withTitle: "OK"); ourAlert = a
                let s = safety(6, "H1-ours")
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { cancelOurs("H1") }
                log("H1-ours enter"); let r = a.runModal(); s.invalidate(); ourAlert = nil
                log("H1-ours return response=\(r.rawValue) frontAfter=\(NSApp.modalWindow === host.window ? "host" : "other/none")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if NSApp.modalWindow === host.window { log("H1 host still open -> close host"); NSApp.abortModal() } }
            }
        }
        log("H1-host enter"); let r = host.runModal(); hs.invalidate(); log("H1-host return response=\(r.rawValue)"); done()
    }
}))
steps.append(("H2-oursBelow-hostOnTop-cancelOurs", { done in
    onRunLoop {
        let a = NSAlert(); a.messageText = "ntk probe ours"; a.addButton(withTitle: "OK"); ourAlert = a
        let s = safety(7, "H2-ours")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            onRunLoop {
                let host = NSAlert(); host.messageText = "ntk probe host modal"; host.addButton(withTitle: "OK")
                let hs = safety(3, "H2-host")
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { cancelOurs("H2") }
                log("H2-host enter"); let r = host.runModal(); hs.invalidate(); log("H2-host return response=\(r.rawValue)")
            }
        }
        log("H2-ours enter"); let r = a.runModal(); s.invalidate(); ourAlert = nil; log("H2-ours return response=\(r.rawValue)"); done()
    }
}))

log("start os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
let app = NSApplication.shared
app.setActivationPolicy(.regular)
next()
app.run()
