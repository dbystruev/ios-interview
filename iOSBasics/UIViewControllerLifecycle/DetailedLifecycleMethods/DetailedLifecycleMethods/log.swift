//
//  log.swift
//  DetailedLifecycleMethods
//
//  Created by Denis Bystruev on 10/11/26.
//  Updated to atttributed string on 10/13/26.
//

import UIKit

extension Notification.Name {
    static let logDidUpdate = Notification.Name("logDidUpdate")
}

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss" // formats date without time zone suffix
    formatter.timeZone = .current // uses the user's local time zone
    return formatter
}()

private var rows = [NSAttributedString]()

func log(function: String = #function, _ items: Any...) {
    let timeStamp = logDateFormatter.string(from: Date())
    let text = items.map { String(describing: $0) }.joined(separator: " ")
    
    // Plain text print for console
    let console = "\(timeStamp) \(function) \(text)".trimmingCharacters(in: .whitespaces)
    print(console)
    
    // Build the attributed string
    let row = NSMutableAttributedString()
    let space = NSAttributedString(string: " ")
    
    // — Date in blue color
    let date = NSAttributedString(string: timeStamp, attributes: [.foregroundColor: UIColor.systemBlue])
    row.append(date)
    row.append(space)
    
    // — Function name in bold
    let name = NSAttributedString(string: function, attributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
    row.append(name)
    row.append(space)
    
    // — The rest as is
    if !items.isEmpty {
        let rest = NSAttributedString(string: text)
        row.append(space)
        row.append(rest)
    }
    
    rows.append(row)
    
    // Broadcast that a new log was added
    NotificationCenter.default.post(name: .logDidUpdate, object: nil)
}

func logNumberOfRows() -> Int {
    rows.count
}

func logRow(_ index: Int) -> NSAttributedString? {
    guard 0 <= index && index < rows.count else { return nil }
    return rows[index]
}
