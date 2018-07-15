//
//  LogItemTableViewController.swift
//  Movement
//
//  Created by Sean Simmons on 2017-12-01.
//  Copyright © 2017 Sean Simmons. All rights reserved.
//

import UIKit

class LogItemTableViewController: UITableViewController {
  var logItems: [String] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    (UIApplication.shared.delegate as! AppDelegate).delegate = self
    self.clearsSelectionOnViewWillAppear = false
    
    tableView.rowHeight = UITableViewAutomaticDimension
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  // MARK: - Table view data source
  
  override func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }
  
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return logItems.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = tableView.dequeueReusableCell(withIdentifier: "LogItemTableViewCell", for: indexPath) as? LogItemTableViewCell else {
      fatalError("Unable to dequeue a LogItemTableViewCell")
    }
    let logItem = logItems[indexPath.row]
    cell.logLabel.text = logItem
    //cell.logLabel.numberOfLines = 0
    // Configure the cell...
     return cell
  }
}

extension LogItemTableViewController: LogItemDelegate {
  func didUpdateLogItems(logItems: [String]) {
    self.logItems = logItems
    self.tableView.reloadData()
  }
}
