import Foundation
import Cache
import UIKit
import PromiseKit

protocol ImageCache {
    func add(url: URL, image: UIImage) -> Promise<Void>
    func tryGet(url: URL) -> Promise<UIImage?>
    func clear()
    func contains(url: URL) -> Bool
}

class CacheImageCache: ImageCache {
    private let memoryStorage: MemoryStorage<UIImage>
    private let diskStorage: DiskStorage<UIImage>
    private let hybridStorage: HybridStorage<UIImage>
    private let storage: Storage<UIImage>
    private let serialQueue: DispatchQueue
    
    init(name: String, sizeLimit: UInt) throws {
        let transformer = TransformerFactory.forImage()
        let diskConfig = DiskConfig(name: "net.vbfox.image-loader.\(name)", maxSize: sizeLimit)
        let memoryConfig = MemoryConfig(countLimit: 50)
        
        diskStorage = try DiskStorage(config: diskConfig, transformer: transformer)
        memoryStorage = MemoryStorage<UIImage>(config: memoryConfig)
        hybridStorage = HybridStorage(memoryStorage: memoryStorage, diskStorage: diskStorage)
        
        serialQueue = DispatchQueue(label: "Cache.AsyncStorage.SerialQueue")
        
        storage = Storage(hybridStorage: hybridStorage)
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
    
    func contains(url: URL) -> Bool {
        return try! storage.existsObject(forKey: url.absoluteString)
    }
    
    func clear() {
        do {
            try storage.removeAll()
        } catch {
            // Permission errors can happen on real device
        }
    }
}
