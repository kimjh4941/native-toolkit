//
//  TestHostAppDelegate.swift
//  IosLibraryTestHost
//

import UIKit

/// The host app of `IosLibraryTests`: the unit tests that need UIKit (presenting a real dialog)
/// run inside this app's process.
///
/// The app has one window scene (generated scene manifest, no scene delegate) and no window, so
/// that the library finds no view controller unless a test creates a key window itself. The tests
/// that do so remove the window before they end; the other tests see the same "nothing to present
/// from" state as before the host existed.
@main
final class TestHostAppDelegate: UIResponder, UIApplicationDelegate {}
