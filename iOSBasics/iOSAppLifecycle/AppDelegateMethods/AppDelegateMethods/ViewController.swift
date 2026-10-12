//
//  ViewController.swift
//  AppDelegateMethods
//
//  Created by Denis Bystruev on 10/11/26.
//

import UIKit

class ViewController: UIViewController {
    
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
        // UI updates must always run on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            
            // Automatically scroll to the latest log entry
            let totalRows = logNumberOfRows()
            guard 0 < totalRows else { return }
            let lastIndex = IndexPath(row: totalRows - 1, section: 0)
            self.tableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        logNumberOfRows()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Re-use cell to prevent memory overhead
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        
        // Cell configuration
        var content = cell.defaultContentConfiguration()
        content.text = logRow(indexPath.row)
        content.textProperties.numberOfLines = 0 // allow long log lines to wrap
        cell.contentConfiguration = content
        
        return cell
    }
    
}
