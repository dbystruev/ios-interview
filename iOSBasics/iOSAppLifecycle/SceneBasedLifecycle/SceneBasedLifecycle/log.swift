//
//  log.swift
//  SceneBasedLifecycle
//
//  Created by Denis Bystruev on 10/11/26.
//

import Foundation

extension Notification.Name {
    static let logDidUpdate = Notification.Name("logDidUpdate")
}

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss" // formats date without time zone suffix
    formatter.timeZone = .current // uses the user's local time zone
    return formatter
}()

private var rows = [String]()

func log(function: String = #function, _ items: Any...) {
    let timeStamp = logDateFormatter.string(from: Date())
    let allItems: [Any] = [timeStamp, function] + items
    let line = allItems.map { String(describing: $0) }.joined(separator: " ")
    print(line)
    rows.append(line)
    
    // Broadcast that a new log was added
    NotificationCenter.default.post(name: .logDidUpdate, object: nil)
}

func logNumberOfRows() -> Int {
    rows.count
}

func logRow(_ index: Int) -> String? {
    guard 0 <= index && index < rows.count else { return nil }
    return rows[index]
}
