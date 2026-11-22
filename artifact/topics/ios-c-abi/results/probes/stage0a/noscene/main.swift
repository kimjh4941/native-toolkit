// Stage 0a throwaway: a UIKit app WITHOUT UIApplicationSceneManifest that calls IosLibrary's
// key-window lookups (IosDialogManager.getRootViewController / showAlert, IosShareManager.share).
import UIKit
import IosLibrary

func log(_ s: String) { print("[NOSCENE] \(s)"); fflush(stdout) }

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController()
        vc.view.backgroundColor = .systemTeal
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        let manifest = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
        log("didFinishLaunching manifest=\(manifest) windowScene=\(w.windowScene != nil) scenes=\(application.connectedScenes.count)")
        let mode = CommandLine.arguments.last ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let scenes = application.connectedScenes.map { "\(type(of: $0)) state=\($0.activationState.rawValue)" }
            log("scenes=\(scenes) keyWindow=\(w.isKeyWindow)")
            let root = IosDialogManager.shared.getRootViewController()
            log("getRootViewController=\(root.map { String(describing: type(of: $0)) } ?? "nil")")
            if mode == "share" {
                IosShareManager.shared.share(content: ShareContent(items: [.text("noscene")])) { ok, completed, type, err in
                    log("share completion ok=\(ok) completed=\(completed) type=\(type ?? "nil") err=\(err ?? "nil")")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    log("presented after share=\(String(describing: vc.presentedViewController.map { type(of: $0) }))")
                }
            } else {
                IosDialogManager.shared.showAlert(title: "NoScene", message: "alert from a scene-less app", completion: { ok, err in
                    log("showAlert completion ok=\(ok) err=\(err ?? "nil") presented=\(String(describing: vc.presentedViewController.map { type(of: $0) }))")
                })
            }
        }
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
