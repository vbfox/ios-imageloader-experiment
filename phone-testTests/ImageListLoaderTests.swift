import Foundation
import XCTest
import PromiseKit
@testable import phone_test

class ImageListLoaderTests: XCTestCase {
    let url1 = URL(string: "http://example.com/1")!
    let img1 = UIImage(named: "PoopRainbow_Avatar")!
    let url2 = URL(string: "http://example.com/2")!
    let img2 = UIImage(named: "zenly_lion")!
    
    func getLoader() -> TestLoader {
        let loader = TestLoader()
        
        let (p1, r1) = Promise<UIImage>.pending()
        loader.promises[url1.absoluteString] = p1
        let (p2, r2) = Promise<UIImage>.pending()
        loader.promises[url2.absoluteString] = p2
        
        r1.fulfill(img1)
        r2.fulfill(img2)
        
        return loader
    }
    
    func testShow() {
        let ex1 = expectation(description: "1")
        let ex2 = expectation(description: "2")
        let loaded = { (index: Int, image: UIImage?) in
            if index == 0 {
                ex1.fulfill()
            } else if index == 1 {
                ex2.fulfill()
            }
        }
        let loader = getLoader()
        let cache = try! CacheImageCache.init(sizeLimit: 10 * 1000)
        cache.clear()
        let listLoader = ImageListLoader(urls: [url1, url2], imageLoader: loader, imageCache: cache, imageLoaded: loaded)
        
        listLoader.show(1)
        wait(for: [ex2], timeout: 1)
        
        listLoader.show(0)
        wait(for: [ex1], timeout: 1)
    }
}
