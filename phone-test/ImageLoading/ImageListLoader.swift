import UIKit
import PromiseKit
import PMKFoundation

enum ImageLoadingError: Error {
    case invalidSate
}

enum LoadingState {
    case notLoading
    case loadingForDiskCache
    case loadingForPrefetch
    case loadingForDisplay
}

private struct LoadingParameters {
    let imageLoader: ImageUrlLoader
    let imageCache: ImageCache
    let serialQueue: DispatchQueue
    let parallelQueue: DispatchQueue
    let imageLoaded: ImageLoaded
}

class TodoWhenLoaded {
    var addToDiskCache: Bool = false
    var addToHybridCache: Bool = false
    var notifyUI = false
}

class ImageToLoad {
    private(set) var index: Int
    let url: URL
    private let params: LoadingParameters
    private var isLoading: Bool = false
    private var todoWhenLoaded: TodoWhenLoaded? = .none
    private var loadingPromise: Promise<Void>? = .none
    private var loadingResolver: Resolver<Void>? = .none
    
    fileprivate init(index: Int, url: URL, params: LoadingParameters) {
        self.index = index
        self.url = url
        self.params = params
    }
    
    private func loadFromCache() -> Promise<UIImage?> {
        return firstly {
            self.params.imageCache.tryGet(url: url)
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
    }
    
    private func download() -> Promise<UIImage> {
        return params.imageLoader.loadImageFrom(self.url, on: self.params.parallelQueue)
    }
    
    private func addToDiskCache(_ image: UIImage) {
        params.imageCache.addToDisk(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
    }
    
    private func addToHybridCache(_ image: UIImage) {
        self.params.imageCache.add(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
    }
    
    private func notifyUI(_ image: UIImage?) {
        params.imageLoaded(self.index, image)
    }
    
    func afterLoad(result: Result<UIImage>) {
        let requestedTodoWhenLoaded = todoWhenLoaded!
        isLoading = false
        loadingResolver?.fulfill(())
        loadingResolver = .none
        todoWhenLoaded = .none
        loadingPromise = .none
        
        switch result {
        case .fulfilled(let image):
            if requestedTodoWhenLoaded.addToDiskCache {
                addToDiskCache(image)
            }
            if requestedTodoWhenLoaded.addToHybridCache {
                addToHybridCache(image)
            }
            if (requestedTodoWhenLoaded.notifyUI) {
                notifyUI(image)
            }
            loadingResolver = .none
        case .rejected(let error):
            print("Image loading failed: \(error)")
            if (requestedTodoWhenLoaded.notifyUI) {
                notifyUI(.none)
            }
        }
    }
    
    func beginLoading() {
        let (promise, resolver) = Promise<Void>.pending()
        isLoading = true
        loadingPromise = promise
        loadingResolver = resolver
        todoWhenLoaded = TodoWhenLoaded()
    }
    
    // Ensure that the image is in the disk cache
    func loadForDiskCache() -> Promise<Void>{
        if isLoading {
            // Any type of async load will add to the disk cache one way or another
            return loadingPromise!
        }
        
        if self.params.imageCache.containsOnDisk(url: self.url) {
            return Promise.value(())
        }
        
        beginLoading()
        todoWhenLoaded?.addToDiskCache = true
        firstly { self.download() }.tap(on: params.serialQueue, self.afterLoad).cauterize()
        
        return loadingPromise!
    }
    
    // Ensure that the image is in the memory cache
    func loadForHybridCache() -> Promise<Void> {
        if isLoading {
            todoWhenLoaded?.addToDiskCache = false
            todoWhenLoaded?.addToHybridCache = true
            return loadingPromise!
        }

        if params.imageCache.contains(url: self.url) {
            return Promise.value(())
        }
        
        beginLoading()
        todoWhenLoaded?.addToHybridCache = true
        firstly { self.download() }.tap(on: params.serialQueue, self.afterLoad).cauterize()
        
        return loadingPromise!
    }
    
    func loadForUI() -> Promise<Void> {
        if isLoading {
            todoWhenLoaded?.addToDiskCache = false
            todoWhenLoaded?.addToHybridCache = true
            todoWhenLoaded?.notifyUI = true
            return loadingPromise!
        }
        
        beginLoading()
        todoWhenLoaded?.notifyUI = true
        firstly
            {
                self.loadFromCache()
            }
            .then { cacheResult -> Promise<UIImage> in
                if let cachedImage = cacheResult {
                    return Promise<UIImage>.value(cachedImage)
                } else {
                    self.todoWhenLoaded?.addToHybridCache = true
                    return self.download()
                }
            }
            .tap(on: params.serialQueue, self.afterLoad)
            .cauterize()
        return loadingPromise!
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
    
    init(urls: [URL], imageLoader: ImageUrlLoader, imageCache: ImageCache, imageLoaded: @escaping ImageLoaded) {
        let imageLoadedOnMain = { (index: Int, image: UIImage?) in
            DispatchQueue.main.async {
                imageLoaded(index, image)
            }
        }
        let params = LoadingParameters(imageLoader: imageLoader,
                                       imageCache: imageCache,
                                       serialQueue: mainQueue,
                                       parallelQueue: imageProcessQueue,
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
            toLoad.loadForDiskCache()
        }.done(on: mainQueue) { _ in
            loadingFinished()
        }.catch(on: mainQueue) {
            // Not much we can do, the UI also has the promise and can better handle it
            print("Failed loading '\(toLoad.url)': \($0)")
            loadingFinished()
        }
    }
    
    func imageVisible(_ index: Int) {
        all[index].loadForUI().cauterize()
    }
    
    func prefetch(_ index: Int) {
        all[index].loadForHybridCache().cauterize()
    }
}
