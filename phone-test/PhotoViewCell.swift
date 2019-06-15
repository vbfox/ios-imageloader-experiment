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
    
    @IBOutlet weak var foo: UILabel!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        foo?.text = ""
        imageOutlet?.image = nil
    }
    
    func showUser(_ user: RandomUserInfo, withImage image: UIImage?) {
        foo.text = user.name.toString()
        if image != nil {
            backgroundColor = UIColor.white
            imageOutlet.image = image
            foo.textColor = UIColor.white
            
        } else {
            backgroundColor = UIColor.red
            foo.textColor = UIColor.black
        }
    }
}
