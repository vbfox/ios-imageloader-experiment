import UIKit
import PromiseKit
import PMKFoundation

enum ImageLoadingError: Error {
    case invalidSate
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
    
    private func addInProgress(recursionCount: Int = 0) {
        if remaining.count == 0 {
            return
        }
        
        let toLoad = remaining[0]
        remaining.remove(at: 0)

        if (recursionCount < 100) && (toLoad.state == LoadingState.finished) {
            // This can happen when the cache was hit, the rest of the method would work in this case but
            // it's faster to avoid going back to the dispatcher and immediately try the next image instead
            // We can't always do that as we might stackoverflow, so there is a recursion limit
            addInProgress(recursionCount: recursionCount + 1)
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
