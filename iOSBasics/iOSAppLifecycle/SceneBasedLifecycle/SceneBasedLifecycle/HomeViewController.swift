//
//  ViewController.swift
//  SceneBasedLifecycle
//
//  Created by Denis Bystruev on 10/12/26.
//

import UIKit

class HomeViewController: UIViewController {
    
    private let cellId = "LogCell"
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Register a cell identifier for reuse
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        tableView.dataSource = self
        view = tableView
        
        // Observe log updates
        NotificationCenter.default.addObserver(self, selector: #selector(handleLogUpdate), name: .logDidUpdate, object: nil)
    }

    @objc private func handleLogUpdate() {
        // UI updates mush always run on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            
            // Automatically scroll to the latest log entry
            let totalRows = logNumberOfRows()
            guard 0 < totalRows else { return }
            let lastIndex = IndexPath(row: totalRows - 1, section: 0)
            tableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
    }

}

extension HomeViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        logNumberOfRows()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Re-use cell to prevent memory overhead
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        
        // Cell configuration
        var content = cell.defaultContentConfiguration()
        let text = logRow(indexPath.row)
        if let text {
            let attributedText = NSMutableAttributedString(string: text)
            
            // Find the position of the second space (after datetime stamp)
            let range: NSRange
            if let firstSpace = text.firstIndex(of: " "),
               let secondSpace = text[text.index(after: firstSpace)...].firstIndex(of: " ") {
                // Range from the start up to (but not including) the second space
                range = NSRange(text.startIndex..<secondSpace, in: text)
            } else {
                // Fallback: if there are fewer than 2 spaces, color the entire string
                range = NSRange(text.startIndex..., in: text)
            }
            
            attributedText.addAttribute(.foregroundColor, value: UIColor.blue, range: range)
            content.attributedText = attributedText
        } else {
            content.text = text
        }
        content.textProperties.numberOfLines = 0 // allow long log lines to wrap
        cell.contentConfiguration = content
        
        return cell
    }
}
