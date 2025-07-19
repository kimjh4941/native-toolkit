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
        let logMessage = "[DEBUG] \(tag): \(message)"
        print(logMessage)
        NSLog("NSLog - %@", logMessage)
    }
    
    public static func i(_ tag: String, _ message: String) {
        let logMessage = "[INFO] \(tag): \(message)"
        print(logMessage)
        NSLog("NSLog - %@", logMessage)
    }
    
    public static func w(_ tag: String, _ message: String) {
        let logMessage = "[WARNING] \(tag): \(message)"
        print(logMessage)
        NSLog("NSLog - %@", logMessage)
    }
    
    public static func e(_ tag: String, _ message: String) {
        let logMessage = "[ERROR] \(tag): \(message)"
        print(logMessage)
        NSLog("NSLog - %@", logMessage)
    }
}
