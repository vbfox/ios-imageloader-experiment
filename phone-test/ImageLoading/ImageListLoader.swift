import UIKit
import PromiseKit
import PMKFoundation

private struct LoadingParameters {
    let downloadQueue: ImageDownloadQueue
    let imageCache: ImageCache
    let serialQueue: DispatchQueue
    let imageLoaded: ImageLoaded
}

class ImageToLoad {
    let index: Int
    let url: URL
    private let params: LoadingParameters
    private var isLoading: Bool = false
    
    fileprivate init(index: Int, url: URL, params: LoadingParameters) {
        self.index = index
        self.url = url
        self.params = params
    }
    
    private func loadFromCache() -> Promise<UIImage?> {
        return firstly {
            self.params.imageCache.tryGet(url: url)
        }
        .recover(on: params.serialQueue) { (error: Error) -> Promise<UIImage?> in
            print("Load from cache error: \(error)")
            return Promise.value(.none)
        }
    }
    
    private func download() -> Promise<UIImage> {
        return params.downloadQueue.add(url: self.url)
    }
    
    private func addToCache(_ image: UIImage) {
        self.params.imageCache
            .add(url: self.url, image: image)
            .catch(on: params.serialQueue) { err in print("Can't add to cache: \(err)") }
    }
    
    private func notifyUI(_ image: UIImage?) {
        params.imageLoaded(self.index, image)
    }
    
    func load() {
        if isLoading {
            return
        }
        
        isLoading = true
        firstly
            {
                self.loadFromCache()
            }
            .then(on: params.serialQueue) { cacheResult -> Promise<(Bool, UIImage)> in
                if let cachedImage = cacheResult {
                    return Promise<(Bool, UIImage)>.value((false, cachedImage))
                } else {
                    return self.download().map { x in (true, x) }
                }
            }
            .done(on: params.serialQueue) { (addToCache, image) in
                self.isLoading = false
                if addToCache {
                    self.addToCache(image)
                }
                self.notifyUI(image)
            }
            .catch(on: params.serialQueue) { error in
                self.isLoading = false
                print("Image loading failed: \(error)")
                self.notifyUI(.none)
            }
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
                                       imageLoaded: imageLoadedOnMain)

        all =
            urls
            .enumerated()
            .map { (i, url) in
                ImageToLoad(index: i, url: url, params: params)
            }
    }
    
    func show(_ index: Int) {
        if index >= 0 && index < all.count {
            mainQueue.async {
                self.all[index].load()
            }
        }
    }
}
