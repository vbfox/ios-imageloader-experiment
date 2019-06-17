import UIKit
import PromiseKit
import PMKFoundation
import Cache

enum ImageLoadingError: Error {
    case invalidSate
}

protocol ImageUrlLoader {
    func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage>
}

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

class ImageUrlSessionLoader: ImageUrlLoader {
    init() {
    }
    
    func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage> {
        func makeImageRequest() -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        
        let req = makeImageRequest()
        let (_, p) = URLSession.shared.dataTaskAndPromise(with: req)
        
        return firstly {
            p.validate()
        }.compactMap(on: queue) {
            UIImage(data: $0.data)
        }
    }
}

enum LoadingState {
    case notLoaded
    case loading
    case finished
}

class ImageToLoad {
    private(set) var index: Int
    let url: URL
    let promise: Promise<UIImage>
    private let cacheLoading: Promise<UIImage?>
    private(set) var state: LoadingState
    private var resolver: Resolver<UIImage>
    private let imageLoader: ImageUrlLoader
    private let imageCache: ImageCache
    private let loadingRequested: Bool = false
    private let queue: DispatchQueue
    
    init(index: Int, url: URL, imageLoader: ImageUrlLoader, imageCache: ImageCache, queue: DispatchQueue) {
        self.index = index
        self.url = url
        self.imageLoader = imageLoader
        self.queue = queue
        self.imageCache = imageCache
        self.state = LoadingState.notLoaded
        
        let (promise, resolver) = Promise<UIImage>.pending()
        self.promise = promise
        self.resolver = resolver
        
        cacheLoading = imageCache.tryGet(url: url)
        loadFromCache()
    }
    
    private func loadFromCache() {
        firstly {
            cacheLoading
        }.done(on: queue) { (image: UIImage?) in
            if let foundImage = image {
                print("Found in cache: \(self.url)")
                self.resolver.fulfill(foundImage)
                self.state = LoadingState.finished
            } else {
                print("NOT found in cache: \(self.url)")
            }
        }.cauterize()
    }
    
    private func loadFromNetworkAndCache() -> Promise<UIImage> {
        return firstly {
            self.imageLoader.loadImageFrom(self.url, on: self.queue)
        }.then { image -> Promise<UIImage> in
            // Don't wait for the add to finish, if it fail we can't do much
            self.imageCache.add(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
            return Promise<UIImage>.value(image)
        }
    }
    
    func startLoading() throws -> Promise<UIImage> {
        if state != LoadingState.notLoaded {
            return self.promise
        }
        
        state = LoadingState.loading
        
        firstly {
            return self.cacheLoading
        }.then { cacheResult -> Promise<UIImage> in
            if let cachedImage = cacheResult {
                return Promise<UIImage>.value(cachedImage)
            } else {
                return self.loadFromNetworkAndCache()
            }
        }.pipe { result in
            if self.state == LoadingState.loading {
                self.resolver.resolve(result)
                self.state = LoadingState.finished
            }
        }
        
        return self.promise
    }
}

class ImageListLoader {
    private var inProgress: Int = 0
    private let minInProgress: Int = 20
    private let maxInProgress: Int = 20
    private let mainQueue = DispatchQueue(label: "net.vbfox.imageloader.main", qos: .userInitiated)
    private let imageProcessQueue = DispatchQueue(label: "net.vbfox.imageloader.process", qos: .background, attributes: .concurrent)
    private var all: [ImageToLoad] = []
    private var remaining: [ImageToLoad] = []
    private let currentIndex: Int = 0
    private(set) var promises: [Promise<UIImage>] = []
    var imageFinished: ((Int) -> ())?
    
    init(urls: [URL], imageLoader: ImageUrlLoader, imageCache: ImageCache) {
        all =
            urls
            .enumerated()
            .map { (i, url) in
                ImageToLoad.init(index: i, url: url, imageLoader: imageLoader, imageCache: imageCache, queue: imageProcessQueue)
            }
        remaining = all
        promises = remaining.map { toLoad in toLoad.promise }

        for image in all {
            firstly { image.promise }
                .done { _ in self.callImageFinished(index: image.index) }
                .cauterize()
        }
        
        mainQueue.async {
            self.fill()
        }
    }
    
    private func fill() {
        while(inProgress < minInProgress && remaining.count > 0) {
            addInProgress()
        }
    }
    
    private func callImageFinished(index: Int) {
        if imageFinished != nil {
            DispatchQueue.main.async {
                self.imageFinished?(index)
            }
        }
    }
    
    private func addInProgress() {
        if remaining.count == 0 {
            return
        }
        
        let toLoad = remaining[0]
        remaining.remove(at: 0)

        if toLoad.state == LoadingState.finished {
            // This can happen when the cache was hit, the rest of the method would work in this case but
            // it's faster to avoid going back to the dispatcher and immediately try the next image instead
            addInProgress()
            return
        }
        
        func loadingFinished() {
            inProgress -= 1
            print("Finished \(toLoad.index)")
            fill()
        }
        
        print("Starting \(toLoad.index)")
        inProgress += 1
        firstly {
            try! toLoad.startLoading()
        }.done(on: mainQueue) { _ in
            loadingFinished()
        }.catch(on: mainQueue) {
            // Not much we can do, the UI also has the promise and can better handle it
            print("Failed loading '\(toLoad.url)': \($0)")
            loadingFinished()
        }
    }
    
    func prioritize(index: Int, isPrefetch: Bool) {
        mainQueue.async {
            let task = self.all[index]
            if task.state == .notLoaded {
                let indexInRemaining = self.remaining.firstIndex { value in value.index == index }
                if indexInRemaining != nil {
                    self.remaining.remove(at: indexInRemaining!)
                    self.remaining.insert(task, at: 0)
                    if !isPrefetch && (self.inProgress < self.maxInProgress) {
                        self.addInProgress()
                    }
                }
            }
        }
    }
}
