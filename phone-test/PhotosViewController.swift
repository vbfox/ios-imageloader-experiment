//
//  PhotosCollectionViewController.swift
//  phone-test
//
//  Created by Julien Roncaglia on 15/06/2019.
//  Copyright © 2019 Julien Roncaglia. All rights reserved.
//

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

final class PhotosViewController: UICollectionViewController {
    private let reuseIdentifier = "PhotoCell"
    private let itemsPerRow: Int = 3
    private let sectionInsets = UIEdgeInsets(top: 20.0, left: 10.0, bottom: 20.0, right: 10.0)
    let bgq = DispatchQueue.global(qos: .userInitiated)
    var users: [RandomUserInfo] = []
    var loader: ImageLoader?
    
    override func viewDidLoad() {
        NSLog("viewDidLoad")
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Do any additional setup after loading the view.
        URLCache.shared.removeAllCachedResponses()
        self.startLoadingResults();
    }
   
    func startLoadingResults() {
        firstly {
            RandomUser.get(resultCount: 500)
        }.done { response in
            let urls = response.results.map { user in URL(string: user.picture!.large!)! }
            self.users = response.results
            self.loader = ImageLoader.init(urls: urls)
            self.loader?.imageFinished = self.onImageFinishedLoading
            self.collectionView!.reloadData()
            
        }.catch {
            print($0)
        }
    }

    func onImageFinishedLoading(index: Int) {
        for cell in self.collectionView!.visibleCells {
            let photoCell = cell as! PhotoViewCell
            if photoCell.index == index {
                photoCell.refreshPhoto()
            }
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using [segue destinationViewController].
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: UICollectionViewDataSource



    // MARK: UICollectionViewDelegate

    /*
    // Uncomment this method to specify if the specified item should be highlighted during tracking
    override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    */

    /*
    // Uncomment this method to specify if the specified item should be selected
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    */

    /*
    // Uncomment these methods to specify if an action menu should be displayed for the specified item, and react to actions performed on the item
    override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return false
    }

    override func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {
    
    }
    */

}

extension PhotosViewController
{
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.users.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! PhotoViewCell
        
        let image = self.loader!.promises[indexPath.row]
        let user = self.users[indexPath.row]
        
        cell.showUser(user, withImage: image, atIndex: indexPath.row)
        
        return cell
    }
}

extension PhotosViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // TODO: Use a better size computation
        let paddingSpace = sectionInsets.left * (CGFloat(itemsPerRow) + 1)
        let availableWidth = view.frame.width - paddingSpace
        let widthPerItem = availableWidth / CGFloat(itemsPerRow)
        
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        
        return sectionInsets
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return sectionInsets.left
    }
}
