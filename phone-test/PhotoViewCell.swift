import UIKit
import PromiseKit

class PhotoViewCell: UICollectionViewCell {
    private static let defaultImage = UIImage(named: "user")
    @IBOutlet weak var photoImageView: UIImageView!
    
    @IBOutlet weak var nameLabel: UILabel!
    
    private(set) var index: Int = -1
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        index = -1
        nameLabel?.text = ""
        photoImageView?.image = PhotoViewCell.defaultImage
    }
    
    func showUser(_ user: RandomUserInfo, atIndex index: Int) {
        self.index = index
        nameLabel.text = user.name!.toString()
    }
    
    func showImage(_ image: UIImage?) {
        if let image = image {
            self.photoImageView.image = image
        } else {
            backgroundColor = .red
        }
    }
}
