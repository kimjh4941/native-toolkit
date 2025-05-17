//
//  Log.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import Foundation

@objcMembers
public class Log: NSObject {
    public static func d(_ tag: String, _ message: String) {
        print("[DEBUG] \(tag): \(message)")
    }

    public static func i(_ tag: String, _ message: String) {
        print("[INFO] \(tag): \(message)")
    }

    public static func w(_ tag: String, _ message: String) {
        print("[WARNING] \(tag): \(message)")
    }

    public static func e(_ tag: String, _ message: String) {
        print("[ERROR] \(tag): \(message)")
    }
}
