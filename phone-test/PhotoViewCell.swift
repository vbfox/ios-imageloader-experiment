//
//  PhotoCellCollectionViewCell.swift
//  phone-test
//
//  Created by Julien Roncaglia on 15/06/2019.
//  Copyright © 2019 Julien Roncaglia. All rights reserved.
//

import UIKit

class PhotoViewCell: UICollectionViewCell {
    @IBOutlet weak var imageOutlet: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func load() {
        self.backgroundColor = UIColor.orange
    }
}
