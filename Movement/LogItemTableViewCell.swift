//
//  LogItemTableViewCell.swift
//  Movement
//
//  Created by Sean Simmons on 2017-12-01.
//  Copyright © 2017 Sean Simmons. All rights reserved.
//

import UIKit

class LogItemTableViewCell: UITableViewCell {
  @IBOutlet weak var logLabel: UILabel!
  
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
}
