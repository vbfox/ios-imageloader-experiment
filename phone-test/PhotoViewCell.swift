import UIKit
import PromiseKit

class PhotoViewCell: UICollectionViewCell {
    @IBOutlet weak var imageOutlet: UIImageView!
    
    @IBOutlet weak var foo: UILabel!
    
    private var imagePromise: Promise<UIImage>?
    private(set) var index: Int = -1
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        imagePromise = nil
        index = -1
        foo?.text = ""
        imageOutlet?.image = nil
    }
    
    func showUser(_ user: RandomUserInfo, withImage image: Promise<UIImage>, atIndex index: Int) {
        self.index = index
        imagePromise = image
        foo.text = user.name!.toString()
        showImage(image)
    }
    
    private func showImage(_ image: Promise<UIImage>) {
        switch image.result {
        case nil:
            break
        case .fulfilled(let finalImage)?:
            self.imageOutlet.image = finalImage
        case .rejected?:
            backgroundColor = .red
        }
    }
    
    func refreshPhoto() {
        showImage(imagePromise!)
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
    }
}
