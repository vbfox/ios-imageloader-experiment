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
        .recover { (error: Error) -> Promise<UIImage?> in
            print("Load from cache error: \(error)")
            return Promise.value(.none)
        }
    }
    
    private func download() -> Promise<UIImage> {
        return params.downloadQueue.add(url: self.url)
    }
    
    private func addToCache(_ image: UIImage) {
        self.params.imageCache.add(url: self.url, image: image).catch { err in print("Can't add to cache: \(err)") }
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
            .then(on: params.serialQueue) { cacheResult -> Promise<UIImage> in
                if let cachedImage = cacheResult {
                    return Promise<UIImage>.value(cachedImage)
                } else {
                    return self.download()
                }
            }
            .ensure(on: params.serialQueue) {
                self.isLoading = false
            }
            .done(on: params.serialQueue) { image in
                self.addToCache(image)
                self.notifyUI(image)
            }
            .catch(on: params.serialQueue) { error in
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
    
    func imageVisible(_ index: Int) {
        mainQueue.async {
            self.all[index].load()
        }
    }
    
    func prefetch(_ index: Int) {
        mainQueue.async {
            self.all[index].load()
        }
    }
}
