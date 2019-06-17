import Foundation
import Cache
import UIKit
import PromiseKit

protocol ImageCache {
    func add(url: URL, image: UIImage) -> Promise<Void>
    func tryGet(url: URL) -> Promise<UIImage?>
    func clear()
}

class InMemoryImageCache: ImageCache {
    private var cache = NSCache<NSString, UIImage>()
    
    func add(url: URL, image: UIImage) -> Promise<Void> {
        cache.setObject(image, forKey: url.absoluteString as NSString)
        return Promise<Void>.value(())
    }
    
    func tryGet(url: URL) -> Promise<UIImage?> {
        let value = cache.object(forKey: url.absoluteString as NSString)
        return Promise.value(value)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

enum FileSystemCacheError: Error {
    case cacheExistsButIsAFile(path: String)
}

class CacheImageCache: ImageCache {
    private let storage: Storage<UIImage>
    
    init(name: String, sizeLimit: UInt) throws {
        let diskConfig = DiskConfig(name: "net.vbfox.image-loader.\(name)", maxSize: sizeLimit)
        let memoryConfig = MemoryConfig(expiry: .never, countLimit: 10, totalCostLimit: 10)
        
        storage = try Storage(
            diskConfig: diskConfig,
            memoryConfig: memoryConfig,
            transformer: TransformerFactory.forImage()
        )
        
        storage.async.removeExpiredObjects { _ in }
    }
    
    func add(url: URL, image: UIImage) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        
        storage.async.setObject(image, forKey: url.absoluteString) { result in
            switch result {
            case .value:
                resolver.fulfill(())
            case .error(let err):
                resolver.reject(err)
            }
        }
        
        return promise
    }
    
    func tryGet(url: URL) -> Promise<UIImage?> {
        let (promise, resolver) = Promise<UIImage?>.pending()
        
        storage.async.object(forKey: url.absoluteString) { result in
            switch result {
            case .value(let image):
                resolver.fulfill(image)
            case .error(let err):
                print(err)
                resolver.fulfill(.none)
            }
        }
        
        return promise
    }
    
    func clear() {
        try! storage.removeAll()
    }
}
