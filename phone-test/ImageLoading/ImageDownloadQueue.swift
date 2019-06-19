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
    private let dispatch = DispatchQueue(label: "net.vbfox.downloadqueue", qos: .background)
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
        let item = ImageDownloadQueueItem(url: url)
        dispatch.async {
            self.queue.append(item)
            self.fill()
        }
        return item.promise
    }
    
    private func fill() {
        while(inProgress <= maxInProgress && queue.count > 0) {
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
            print("Finished \(toLoad.url)")
            fill()
        }
        
        print("Starting \(toLoad.url)")
        inProgress += 1
        firstly {
            self.loader.loadImageFrom(toLoad.url, on: processQueue)
            }.done(on: dispatch) { image in
                toLoad.resolver.fulfill(image)
                loadingFinished()
            }.catch(on: dispatch) { error in
                toLoad.resolver.reject(error)
                print("Failed loading '\(toLoad.url)': \(error)")
                loadingFinished()
        }
    }
    
    public func prioritize(url: URL) {
        dispatch.async {
            let index = self.queue.firstIndex { x in x.url == url }
            if let index = index {
                if index != 0 {
                    let value = self.queue[index]
                    self.queue.remove(at: index)
                    self.queue.insert(value, at: 0)
                }
            }
        }
    }
}
