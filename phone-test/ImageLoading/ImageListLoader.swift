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
    let downloadQueue: ImageDownloadQueue
    let imageCache: ImageCache
    let serialQueue: DispatchQueue
    let parallelQueue: DispatchQueue
    let imageLoaded: ImageLoaded
}

class TodoWhenLoaded {
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
    
    private func download() -> Promise<UIImage> {
        return params.downloadQueue.add(url: self.url)
    }
    
    private func addToHybridCache(_ image: UIImage) {
        self.params.imageCache.add(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
    }
    
    private func notifyUI(_ image: UIImage?) {
        params.imageLoaded(self.index, image)
    }
    
    private func afterLoad(result: Result<UIImage>) {
        let requestedTodoWhenLoaded = todoWhenLoaded!
        isLoading = false
        loadingResolver?.fulfill(())
        loadingResolver = .none
        todoWhenLoaded = .none
        loadingPromise = .none
        
        switch result {
        case .fulfilled(let image):
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
    
    private func beginLoading() {
        let (promise, resolver) = Promise<Void>.pending()
        isLoading = true
        loadingPromise = promise
        loadingResolver = resolver
        todoWhenLoaded = TodoWhenLoaded()
    }
    
    // Ensure that the image is in the memory cache
    func loadForHybridCache() -> Promise<Void> {
        if isLoading {
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
            .then(on: params.serialQueue) { cacheResult -> Promise<UIImage> in
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
    private let mainQueue = DispatchQueue(label: "net.vbfox.imageloader.main", qos: .userInitiated)
    private let imageProcessQueue = DispatchQueue(label: "net.vbfox.imageloader.process", qos: .background, attributes: .concurrent)
    private var all: [ImageToLoad] = []
    private let downloadQueue: ImageDownloadQueue
    
    init(urls: [URL], imageLoader: ImageUrlLoader, imageCache: ImageCache, imageLoaded: @escaping ImageLoaded) {
        downloadQueue = ImageDownloadQueue(loader: imageLoader, maxInProgress: 10)
        
        let imageLoadedOnMain = { (index: Int, image: UIImage?) in
            DispatchQueue.main.async {
                imageLoaded(index, image)
            }
        }
        
        let params = LoadingParameters(downloadQueue: downloadQueue,
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
    }
    
    func imageVisible(_ index: Int) {
        mainQueue.async {
            self.all[index].loadForUI().cauterize()
        }
    }
    
    func prefetch(_ index: Int) {
        mainQueue.async {
            self.all[index].loadForHybridCache().cauterize()
        }
    }
}
