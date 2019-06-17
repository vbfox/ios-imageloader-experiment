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
    private var loading = false
    private var loadingPromise: Promise<Void>? = .none
    private let loadingRequested: Bool = false
    private let params: LoadingParameters
    
    fileprivate init(index: Int, url: URL, params: LoadingParameters) {
        self.index = index
        self.url = url
        self.params = params
    }
    
    private func loadFromCache() -> Promise<UIImage?> {
        return firstly {
            self.params.imageCache.tryGet(url: url)
        }
        .map(on: params.parallelQueue) { image -> UIImage? in
            if let foundImage = image {
                return self.runTransform(foundImage)
            } else {
                return .none
            }
        }
        .recover { (error: Error) -> Promise<UIImage?> in
            print("Load from cache error: \(error)")
            return Promise.value(.none)
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
    
    func startLoading() -> Promise<Void> {
        if loading {
            return loadingPromise!
        }
        
        loading = true
        
        let (promise, resolver) = Promise<Void>.pending()
        self.loadingPromise = .some(promise)
        
        firstly {
            self.loadFromCache()
        }
        .then(on: params.serialQueue) { cacheResult -> Promise<UIImage> in
            if let cachedImage = cacheResult {
                return Promise<UIImage>.value(cachedImage)
            } else {
                return self.loadFromNetworkAndCache()
            }
        }
        .ensure(on: params.serialQueue) {
            self.loading = false
            self.loadingPromise = .none
            resolver.fulfill(())
        }
        .done(on: params.serialQueue) {
            self.params.imageLoaded(self.index, $0)
        }
        .catch {
            print("Image loading failed: \($0)")
            self.params.imageLoaded(self.index, .none)
        }
        
        return promise
    }
    
    func preload() -> Promise<Void> {
        if (params.imageCache.contains(url: url)) {
            return Promise<Void>.value(())
        }
        
        return startLoading()
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
    
    init(urls: [URL], transform: TransformImage? = .none, imageLoader: ImageUrlLoader, imageCache: ImageCache, imageLoaded: @escaping ImageLoaded) {
        let imageLoadedOnMain = { (index: Int, image: UIImage?) in
            DispatchQueue.main.async {
                imageLoaded(index, image)
            }
        }
        let params = LoadingParameters(imageLoader: imageLoader,
                                       imageCache: imageCache,
                                       serialQueue: mainQueue,
                                       parallelQueue: imageProcessQueue,
                                       transform: transform,
                                       imageLoaded: imageLoadedOnMain)

        all =
            urls
            .enumerated()
            .map { (i, url) in
                ImageToLoad(index: i, url: url, params: params)
            }
        remaining = all
        
        mainQueue.async {
            self.fill()
        }
    }
    
    private func fill() {
        while(inProgress < minInProgress && remaining.count > 0) {
            addInProgress()
        }
    }
    
    private func addInProgress() {
        if remaining.count == 0 {
            return
        }
        
        let toLoad = remaining[0]
        remaining.remove(at: 0)
        
        func loadingFinished() {
            inProgress -= 1
            print("Finished \(toLoad.index)")
            fill()
        }
        
        print("Starting \(toLoad.index)")
        inProgress += 1
        firstly {
            toLoad.preload()
        }.done(on: mainQueue) { _ in
            loadingFinished()
        }.catch(on: mainQueue) {
            // Not much we can do, the UI also has the promise and can better handle it
            print("Failed loading '\(toLoad.url)': \($0)")
            loadingFinished()
        }
    }
    
    func imageVisible(_ index: Int) {
        all[index].startLoading().cauterize()
    }
    
    func prefetch(_ index: Int) {
        all[index].preload().cauterize()
    }
}
