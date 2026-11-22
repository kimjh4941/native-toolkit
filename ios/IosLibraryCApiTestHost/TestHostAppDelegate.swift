//
//  TestHostAppDelegate.swift
//  IosLibraryCApiTestHost
//

import UIKit

/// The host app of `IosLibraryCApiTests`: the tests run inside this app's process.
///
/// It never requests the notification permission, and neither may the tests: the rows of the design
/// that expect `PERMISSION_DENIED` depend on it (C ABI design part 2, 12.1). The UI test app of
/// TB-2b, where permissions are granted, has another bundle identifier for the same reason.
///
/// One window scene (generated scene manifest, no scene delegate) and no window, as in
/// `IosLibraryTestHost`.
@main
final class TestHostAppDelegate: UIResponder, UIApplicationDelegate {}
