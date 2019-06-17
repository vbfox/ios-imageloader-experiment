import UIKit
import PromiseKit
import PMKFoundation
import Cache

protocol ImageUrlLoader {
    func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage>
}

class ImageUrlSessionLoader: ImageUrlLoader {
    func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage> {
        func makeImageRequest() -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        
        let req = makeImageRequest()
        let p = URLSession.shared.dataTask(.promise, with: req)
        
        return firstly {
            p.validate()
        }.compactMap(on: queue) {
                UIImage(data: $0.data)
        }
    }
}
