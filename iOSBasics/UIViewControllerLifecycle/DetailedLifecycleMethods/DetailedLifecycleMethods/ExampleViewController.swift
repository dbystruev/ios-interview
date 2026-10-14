//
//  ExampleViewController.swift
//  DetailedLifecycleMethods
//
//  Created by Denis Bystruev on 10/14/26.
//
//  Derived from https://github.com/mukundjogi/ios-interview/blob/main/docs/ios-basics.md#detailed-lifecycle-methods

import UIKit

class ExampleViewController: UIViewController {
    
    // MARK: - Properties
    
    private let cellId = "LogCell"
    private let tableView = UITableView()
    private let titleLabel = UILabel()
    private let dataService = DataService()
    
    // MARK: - Initialization
    
    init() {
        super.init(nibName: nil, bundle: nil)
        log("\n1. ViewController initialized")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        log("\n1. ViewController initialized from storyboard")
    }
    
    deinit {
        log("\n10. ViewController deallocated")
        // Cleanup observers, timers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Lifecycle Methods
    override func loadView() {
        super.loadView()
        log("\n2. Create view hierarchy")
        // Only override if creating views programmatically without storyboard
    }
    
    override func loadViewIfNeeded() {
        super.loadViewIfNeeded()
        log("\n2. Create view hierarchy")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        log("\n3. View loaded into memory")
        
        // Called once when view is first loaded
        // Perfect for:
        // - Initial setup
        // - Adding subviews
        // - Setting up constraints
        // - Registering for notifications
        
        setupUI()
        setupConstraints()
        registerNotifications()
        
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) {
            NotificationCenter.default.post(name: .dataUpdated, object: nil)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log(animated, "\n4. View is about to appear")
        
        // Called every time view is about to appear
        // Perfect for:
        // - Refreshing data
        // - Starting animations
        // - Updating UI
        
        navigationController?.setNavigationBarHidden(false, animated: animated)
        refreshData()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        log("\n5. About to layout subviews")
        
        // Called when bounds change (rotation, multitasking)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        log("\n6. Subviews laid out")
        
        // Perfect for:
        // - Frame-based layout adjustments
        // - Updating layer properties
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        log(animated, "\n7. View appeared on screen")
        
        // Called when view is fully visible
        // Perfect for:
        // - Starting heavy tasks
        // - Analytics tracking
        // - Starting media playback
        
        startTimer()
        trackScreenView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        log(animated, "\n8. View about to disappear")
        
        // Perfect for:
        // - Saving state
        // - Stopping animations
        // - Pausing media
        
        saveUserInput()
        stopTimer()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        log(animated, "\n9. View disappeared")
        
        // Perfect for:
        // - Cleanup
        // - Stopping background tasks
    }
    
    // MARK: - Memory Warning
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        log("Memory warning received")
        
        // Perfect for:
        // - Cleaning caches
        // - Releasing recreatable resources
        
        imageCache.removeAll()
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        log()
        view.backgroundColor = .white
        
        titleLabel.text = "Example"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        view.addSubview(titleLabel)
        
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        log()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func registerNotifications() {
        log()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataUpdatedNotification), name: .dataUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLogUpdatedNotification), name: .logDidUpdate, object: nil)
    }
    
    @objc private func handleDataUpdatedNotification() {
        log()
        refreshData()
    }
    
    @objc private func handleLogUpdatedNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // 1. Reload data
            self.tableView.reloadData()
            
            // 2. Force table view to synchronously update rows and layout
            self.tableView.layoutIfNeeded()
            
            // 3. Scroll using the table view's updated row count
            
            let totalRows = self.tableView.numberOfRows(inSection: 0)
            guard 0 < totalRows else { return }
            self.tableView.scrollToRow(at: IndexPath(row: totalRows - 1, section: 0), at: .bottom, animated: true)
        }
    }
    
    private func refreshData() {
        log()
        dataService.fetchData { [weak self] result in
            DispatchQueue.main.async {
                self?.updateUI(with: result)
            }
        }
    }
    
    private func updateUI(with data: Any) {
        log()
    }
    
    private func startTimer() { log() }
    private func stopTimer() { log() }
    private func saveUserInput() { log() }
    private func trackScreenView() { log() }
    
    private var imageCache: [String: UIImage] = [:]
}

// MARK: - UITableViewDataSource
extension ExampleViewController: UITableViewDataSource {
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

// Supporting types
class DataService {
    func fetchData(notify: Bool = true, completion: @escaping (Any) -> Void) {
        log()
        completion("data fetched")
    }
}

extension Notification.Name {
    static let dataUpdated = Notification.Name("dataUpdated")
}
