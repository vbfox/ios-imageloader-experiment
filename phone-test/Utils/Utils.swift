import Foundation
import UIKit

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + self.lowercased().dropFirst()
    }
}

extension UIImage {
    public func rounded(radius: CGFloat) -> UIImage {
        return autoreleasepool { () -> UIImage in
            let rect = CGRect(origin: .zero, size: size)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            draw(in: rect)
            return UIGraphicsGetImageFromCurrentImageContext()!
        }
    }
    
    func resize(toSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(toSize, false, self.scale)
        self.draw(in: CGRect(x: 0, y: 0, width: toSize.width, height: toSize.height))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaledImage!
    }
    
    func resizeKeepAspect(inTargetSize: CGSize) -> UIImage {
        let widthRatio  = inTargetSize.width  / self.size.width
        let heightRatio = inTargetSize.height / self.size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        return resize(toSize: newSize)
    }
}
