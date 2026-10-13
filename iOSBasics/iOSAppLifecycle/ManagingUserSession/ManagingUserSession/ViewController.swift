//
//  ViewController.swift
//  ManagingUserSession
//
//  Created by Denis Bystruev on 10/13/26.
//

import UIKit

class ViewController: UIViewController {
    private let cellId = "LogCell"
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        view = tableView
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleLogUpdate), name: .logDidUpdate, object: nil)
    }
    
    @objc private func handleLogUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            
            let rowsCount = logNumberOfRows()
            guard 0 < rowsCount else { return }
            
            let last = IndexPath(row: rowsCount - 1, section: 0)
            self.tableView.scrollToRow(at: last, at: .bottom, animated: true)
        }
    }

}

// MARK: - UITableViewDataSource
extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        logNumberOfRows()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        
        var content = cell.defaultContentConfiguration()
        content.attributedText = logRow(indexPath.row)
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        
        return cell
    }
    
}
