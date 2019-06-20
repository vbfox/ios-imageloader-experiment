import Foundation
import PromiseKit
import UIKit

struct ImageDownloadQueueItem {
    let url: URL
    let promise: Promise<UIImage>
    let resolver: Resolver<UIImage>
    
    init(url: URL) {
        self.url = url
        (promise, resolver) = Promise<UIImage>.pending()
    }
}

class ImageDownloadQueue {
    // Where the download queue is managed
    private let dispatch = DispatchQueue(label: "net.vbfox.downloadqueue", qos: .background)
    // Where the bytes are decoded to an image
    private let processQueue = DispatchQueue(label: "net.vbfox.net.vbfox.downloadqueue.process", qos: .background, attributes: .concurrent)
    private var queue: [ImageDownloadQueueItem] = []
    private var inProgress: Int = 0
    private let maxInProgress: Int
    private let loader: ImageUrlLoader
    
    init(loader: ImageUrlLoader, maxInProgress: Int) {
        self.maxInProgress = maxInProgress
        self.loader = loader
    }
    
    func add(url: URL) -> Promise<UIImage> {
        return dispatch.sync {
            let maybeItem = queue.first { x in x.url == url }
            if let item = maybeItem {
                return item.promise
            } else {
                let item = ImageDownloadQueueItem(url: url)
                self.queue.append(item)
                self.fill()
                return item.promise
            }
        }
    }
    
    private func fill() {
        while(inProgress < maxInProgress && queue.count > 0) {
            addInProgress()
        }
    }
    
    private func addInProgress() {
        if queue.count == 0 {
            return
        }
        
        let toLoad = queue[0]
        queue.remove(at: 0)
        
        func loadingFinished() {
            inProgress -= 1
            print("ImageDownloadQueue: Finished \(toLoad.url)")
            fill()
        }
        
        print("ImageDownloadQueue: Starting \(toLoad.url)")
        inProgress += 1
        firstly {
            self.loader.loadImageFrom(toLoad.url, on: processQueue)
        }.done(on: dispatch) { image in
            toLoad.resolver.fulfill(image)
            loadingFinished()
        }.catch(on: dispatch) { error in
            toLoad.resolver.reject(error)
            print("ImageDownloadQueue: Failed loading '\(toLoad.url)': \(error)")
            loadingFinished()
        }
    }
}
