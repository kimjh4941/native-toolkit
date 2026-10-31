// Stage 1a: a Swift app built with the lowest supported Xcode that imports both frameworks.
import IosLibrary
import IosLibraryCApi
import UIKit

private let pasteboardName = "com.jonghyunkim.nativetoolkit.stage1a.probe"

@main
final class SwiftConsumerAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setvbuf(stdout, nil, _IOLBF, 0)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        print("SWIFTAPP ntk_version=0x\(String(ntk_version(), radix: 16)) NTK_VERSION=0x\(String(NTK_VERSION, radix: 16))")
        _ = UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)
        // The Swift API of IosLibrary (swiftinterface built by Xcode 26.6).
        IosClipboardManager.shared.copy(.plainText("swift-app"), scope: .named(pasteboardName)) { ok, code, _ in
            print("SWIFTAPP IosLibrary copy ok=\(ok) code=\(code ?? "nil")")
            // The C ABI from Swift (the clang module of IosLibraryCApi only).
            let callback: ntk_probe_text_fn = { _, requestId, error, _, text in
                let value = text.flatMap { ntk_string_data($0) }.map { String(cString: $0) } ?? "nil"
                ntk_string_free(text)
                print("SWIFTAPP C ABI callback id=\(requestId) error=\(error) text=\(value) main=\(Thread.isMainThread)")
            }
            let release: ntk_release_fn = { _ in
                print("SWIFTAPP release main=\(Thread.isMainThread)")
                exit(0)
            }
            let error = ntk_probe_clipboard_read_text_async(callback, nil, release, nil)
            print("SWIFTAPP read_text_async returned \(error)")
        }
        return true
    }
}
