//
//  CommonRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi

/// Common.h.
enum CommonRows {
    static let section = CApiRowSection(id: "common", rows: [
        CApiRow(id: "common.version") { report in
            report(String(format: "0x%06X", ntk_version()))
        },
        CApiRow(id: "common.lastSystemCode") { report in
            report(String(ntk_last_system_code()))
        },
    ])
}
