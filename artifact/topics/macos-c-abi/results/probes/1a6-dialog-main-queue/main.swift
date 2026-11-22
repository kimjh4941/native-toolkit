// Probe for macos-c-abi 1a-6: does the main queue drain while NSAlert.runModal() is open,
// depending on how runModal() was entered, and which path can cancel the modal?
import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ntk-1a6.jsonl"
FileManager.default.createFile(atPath: outPath, contents: nil)
let out = FileHandle(forWritingAtPath: outPath)!
let t0 = Date()
func log(_ s: String) {
    let line = String(format: "%.3f ", Date().timeIntervalSince(t0)) + s + "\n"
    out.write(line.data(using: .utf8)!)
}

final class Probe: NSObject {
    var scenario = ""
    var modalOpen = false
    @objc func viaPerformSelector() { mark("performSelector(onMainThread,modes:common)") }
    func mark(_ path: String) {
        log("\(scenario) ran path=\(path) duringModal=\(modalOpen) isMain=\(Thread.isMainThread)")
    }
    // Enqueue every delivery path from a background thread while the modal is open.
    func enqueueAll() {
        DispatchQueue.global().async {
            DispatchQueue.main.async { self.mark("DispatchQueue.main.async") }
            Task { @MainActor in self.mark("Task@MainActor") }
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { self.mark("CFRunLoopPerformBlock(common)") }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            self.performSelector(onMainThread: #selector(Probe.viaPerformSelector), with: nil, waitUntilDone: false, modes: [RunLoop.Mode.common.rawValue])
            RunLoop.main.perform(inModes: [.common]) { self.mark("RunLoop.main.perform(common)") }
        }
    }
    // Try to cancel from a background thread through one path.
    func cancel(via path: String) {
        DispatchQueue.global().async {
            let body = {
                log("\(self.scenario) cancel-run path=\(path) modalWindow=\(NSApp.modalWindow != nil)")
                NSApp.abortModal()
            }
            switch path {
            case "gcd": DispatchQueue.main.async(execute: body)
            case "cfrunloop":
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, body)
                CFRunLoopWakeUp(CFRunLoopGetMain())
            default: break
            }
        }
    }
    func showAlert(cancelPath: String) {
        let alert = NSAlert()
        alert.messageText = "ntk probe 1a-6 \(scenario)"
        alert.addButton(withTitle: "OK")
        // Safety net: always end the modal after 6 s through a timer in the modal mode.
        let safety = Timer(timeInterval: 6, repeats: false) { _ in
            log("\(self.scenario) safety-timer abort")
            NSApp.abortModal()
        }
        RunLoop.main.add(safety, forMode: .modalPanel)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { self.enqueueAll() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { self.cancel(via: cancelPath) }
        modalOpen = true
        log("\(scenario) runModal-enter isMain=\(Thread.isMainThread)")
        let r = alert.runModal()
        modalOpen = false
        safety.invalidate()
        log("\(scenario) runModal-return response=\(r.rawValue)")
    }
}

let probe = Probe()
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Scenarios run one after another; each waits until the previous modal returned.
var scenarios: [(String, () -> Void)] = []
func next() {
    guard !scenarios.isEmpty else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { log("done"); exit(0) }
        return
    }
    let (name, run) = scenarios.removeFirst()
    probe.scenario = name
    // Give queued work from the previous scenario time to drain.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { run() }
}
// A: today's MacDialogManager path, runModal inside a DispatchQueue.main.async block; cancel via GCD.
scenarios.append(("A-gcdEntry-gcdCancel", {
    DispatchQueue.main.async { probe.showAlert(cancelPath: "gcd"); next() }
}))
// A with cancel via CFRunLoopPerformBlock.
scenarios.append(("A-gcdEntry-cfCancel", {
    DispatchQueue.main.async { probe.showAlert(cancelPath: "cfrunloop"); next() }
}))
// T: Swift main actor entry (0e/0f style), cancel via CFRunLoopPerformBlock.
scenarios.append(("T-mainActorEntry-cfCancel", {
    Task { @MainActor in probe.showAlert(cancelPath: "cfrunloop"); next() }
}))
// A': entered outside any GCD block, from a run loop block in common modes; cancel via GCD.
scenarios.append(("Aprime-cfEntry-gcdCancel", {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { probe.showAlert(cancelPath: "gcd"); next() }
    CFRunLoopWakeUp(CFRunLoopGetMain())
}))
// A' entered from a Timer on the main run loop (default mode); cancel via GCD.
scenarios.append(("Aprime-timerEntry-gcdCancel", {
    let t = Timer(timeInterval: 0.01, repeats: false) { _ in probe.showAlert(cancelPath: "gcd"); next() }
    RunLoop.main.add(t, forMode: .default)
}))

log("start os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
next()
app.run()
