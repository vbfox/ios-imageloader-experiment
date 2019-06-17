import UIKit
import PromiseKit

class PhotoViewCell: UICollectionViewCell {
    private static let defaultImage = UIImage(named: "user")
    @IBOutlet weak var imageOutlet: UIImageView!
    
    @IBOutlet weak var foo: UILabel!
    
    private(set) var index: Int = -1
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        index = -1
        foo?.text = ""
        imageOutlet?.image = PhotoViewCell.defaultImage
    }
    
    func showUser(_ user: RandomUserInfo, atIndex index: Int) {
        self.index = index
        foo.text = user.name!.toString()
    }
    
    func showImage(_ image: UIImage?) {
        if let image = image {
            self.imageOutlet.image = image
        } else {
            backgroundColor = .red
        }
    }
}
