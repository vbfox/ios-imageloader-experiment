import Foundation
import Cache
import UIKit
import PromiseKit

protocol ImageCache {
    func add(url: URL, image: UIImage) -> Promise<Void>
    func addToDisk(url: URL, image: UIImage) -> Promise<Void>
    func tryGet(url: URL) -> Promise<UIImage?>
    func clear()
    func containsOnDisk(url: URL) -> Bool
    func contains(url: URL) -> Bool
}

enum FileSystemCacheError: Error {
    case cacheExistsButIsAFile(path: String)
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
    
    func addToDisk(url: URL, image: UIImage) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        
        serialQueue.async {
            do {
                try self.diskStorage.setObject(image, forKey: url.absoluteString, expiry: nil)
                resolver.fulfill(())
            } catch {
                resolver.reject(error)
            }
        }

        return promise
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
    
    func containsOnDisk(url: URL) -> Bool {
        return try! diskStorage.existsObject(forKey: url.absoluteString)
    }
    
    func clear() {
        try! storage.removeAll()
    }
}
