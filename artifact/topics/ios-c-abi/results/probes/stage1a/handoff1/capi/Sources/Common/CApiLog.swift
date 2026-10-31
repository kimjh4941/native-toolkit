// Hand-off 1 probe: the C ABI log (P1-18). Names, IDs and error values are public; user text is not logged.
import os

enum CApiLog {
    static let common = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: "Common")
    static let dialog = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: "Dialog")
    static let share = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: "Share")
    static let probe = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: "Probe")
}
