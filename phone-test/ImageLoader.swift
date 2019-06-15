import UIKit
import PromiseKit
import PMKFoundation

enum LoadingState {
    case notLoaded
    case loading
    case finished
}

enum ImageLoadingError: Error {
    case invalidSate
}

class ImageToLoad {
    private(set) var indexes: [Int]
    let url: URL
    let promise: Promise<UIImage>
    private(set) var state: LoadingState
    private var resolver: Resolver<UIImage>
    private let urlSession: URLSession
    
    init(index: Int, url: URL, urlSession: URLSession) {
        self.urlSession = urlSession
        self.state = LoadingState.notLoaded
        self.indexes = [index]
        self.url = url
        let (promise, resolver) = Promise<UIImage>.pending()
        self.promise = promise
        self.resolver = resolver
    }
    
    func addIndex(_ index: Int) {
        indexes.append(index)
    }
    
    static func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage> {
        func makeImageRequest() -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        
        let req = makeImageRequest()
        return firstly {
            URLSession.shared.dataTask(.promise, with: req).validate()
            }.compactMap(on: queue) {
                UIImage(data: $0.data)
        }
    }
    
    func startLoading(on queue: DispatchQueue) throws -> Promise<UIImage> {
        if state != LoadingState.notLoaded {
            throw ImageLoadingError.invalidSate
        }
        
        state = LoadingState.loading
        
        firstly {
            ImageToLoad.loadImageFrom(url, on: queue)
            }.pipe { result in
                self.resolver.resolve(result)
                self.state = LoadingState.finished
        }
        
        return self.promise
    }
}

class ImageLoader {
    private var inProgress: Int = 0
    private let minInProgress: Int = 10
    private let maxInProgress: Int = 20
    private let mainQueue = DispatchQueue(label: "net.vbfox.imageloader.main", qos: .userInitiated)
    private let imageProcessQueue = DispatchQueue(label: "net.vbfox.imageloader.process", qos: .background, attributes: .concurrent)
    private var remaining: [ImageToLoad] = []
    private let currentIndex: Int = 0
    private(set) var promises: [Promise<UIImage>] = []
    var imageFinished: ((Int) -> ())?
    
    init(urls: [URL], urlSession: URLSession = URLSession.shared) {
        for (i, url) in urls.enumerated() {
            let existing = remaining.first { r in r.url == url }
            switch existing {
            case .none:
                let toLoad = ImageToLoad.init(index: i, url: url, urlSession: urlSession)
                remaining.append(toLoad)
                promises.append(toLoad.promise)
            case .some(let someExisting):
                someExisting.addIndex(i)
                promises.append(someExisting.promise)
            }
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
    
    private func addInProgress() {
        if remaining.count == 0 {
            return
        }
        
        let toLoad = remaining[0]
        remaining.remove(at: 0)
        
        func loadingFinished() {
            inProgress -= 1
            print("Finished \(toLoad.indexes)")
            fill()
            if imageFinished != nil {
                DispatchQueue.main.async {
                    for index in toLoad.indexes {
                        self.imageFinished?(index)
                    }
                }
            }
        }
        
        print("Starting \(toLoad.indexes)")
        inProgress += 1
        firstly {
            try! toLoad.startLoading(on: imageProcessQueue)
            }.done(on: mainQueue) { _ in
                loadingFinished()
            }.catch(on: mainQueue) {
                // Not much we can do, the UI also has the promise and can better handle it
                print("Failed loading '\(toLoad.url)': \($0)")
                loadingFinished()
        }
    }
}
