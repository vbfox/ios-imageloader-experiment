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

typealias TransformImage = (UIImage) -> UIImage

private struct LoadingParameters {
    let imageLoader: ImageUrlLoader
    let imageCache: ImageCache
    let serialQueue: DispatchQueue
    let parallelQueue: DispatchQueue
    let transform: TransformImage?
    let imageLoaded: ImageLoaded
}

class ImageToLoad {
    private(set) var index: Int
    let url: URL
    let promise: Promise<UIImage>
    private let cacheLoading: Promise<UIImage?>
    private(set) var state: LoadingState
    private var resolver: Resolver<UIImage>
    private let loadingRequested: Bool = false
    private let params: LoadingParameters
    
    fileprivate init(index: Int, url: URL, params: LoadingParameters) {
        self.index = index
        self.url = url
        self.params = params
        self.state = LoadingState.notLoaded
        
        let (promise, resolver) = Promise<UIImage>.pending()
        self.promise = promise
        self.resolver = resolver
        
        cacheLoading = params.imageCache.tryGet(url: url)
        firstly { promise }.done { image in params.imageLoaded(self.index, image) }.cauterize()
        loadFromCache()
    }
    
    private func loadFromCache() {
        firstly {
            cacheLoading
        }
        .map(on: params.parallelQueue) { image -> UIImage? in
            if let foundImage = image {
                return self.runTransform(foundImage)
            } else {
                return .none
            }
        }
        .done(on: params.serialQueue) { (image: UIImage?) in
            if let foundImage = image {
                print("Found in cache: \(self.url)")
                self.resolver.fulfill(foundImage)
                self.state = LoadingState.finished
            } else {
                print("NOT found in cache: \(self.url)")
            }
        }
        .catch {
            print("Load from cache error: \($0)")
        }
    }
    
    private func loadFromNetworkAndCache() -> Promise<UIImage> {
        return firstly {
            self.params.imageLoader.loadImageFrom(self.url, on: self.params.parallelQueue)
        }
        .then(on: params.parallelQueue) { image -> Promise<UIImage> in
            // Don't wait for the add to finish, if it fail we can't do much
            self.params.imageCache.add(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
            return Promise<UIImage>.value(image)
        }
        .map(on: params.parallelQueue) { image -> UIImage in
            return self.runTransform(image)
        }
    }
    
    private func runTransform(_ image: UIImage) -> UIImage {
        if let transform = self.params.transform {
            return transform(image)
        } else {
            return image
        }
    }
    
    func startLoading() throws -> Promise<UIImage> {
        if state != LoadingState.notLoaded {
            return self.promise
        }
        
        state = LoadingState.loading
        
        firstly {
            return self.cacheLoading
        }
        .then(on: params.serialQueue) { cacheResult -> Promise<UIImage> in
            if let cachedImage = cacheResult {
                return Promise<UIImage>.value(cachedImage)
            } else {
                return self.loadFromNetworkAndCache()
            }
        }
        .pipe { result in
            if self.state == LoadingState.loading {
                self.resolver.resolve(result)
                self.state = LoadingState.finished
            }
        }
        
        return self.promise
    }
}

typealias ImageLoaded = (Int, UIImage?) -> Void

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
    
    init(urls: [URL], transform: TransformImage? = .none, imageLoader: ImageUrlLoader, imageCache: ImageCache, imageLoaded: @escaping ImageLoaded) {
        let params = LoadingParameters(imageLoader: imageLoader,
                                       imageCache: imageCache,
                                       serialQueue: mainQueue,
                                       parallelQueue: imageProcessQueue,
                                       transform: transform,
                                       imageLoaded: imageLoaded)

        all =
            urls
            .enumerated()
            .map { (i, url) in
                ImageToLoad(index: i, url: url, params: params)
            }
        remaining = all
        promises = remaining.map { toLoad in toLoad.promise }
        
        mainQueue.async {
            self.fill()
        }
    }
    
    private func fill() {
        while(inProgress < minInProgress && remaining.count > 0) {
            addInProgress()
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
    
    func imageVisible(index: Int) {
    }
    
    func prefetch(index: Int) {
        
    }
}
