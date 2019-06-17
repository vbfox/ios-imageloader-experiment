import UIKit
import PromiseKit

final class PhotosViewController: UICollectionViewController {
    private let reuseIdentifier = "PhotoCell"
    private let itemsPerRow: Int = 3
    private let sectionInsets = UIEdgeInsets(top: 20.0, left: 10.0, bottom: 20.0, right: 10.0)
    private var users: [RandomUserInfo] = []
    private var loader: ImageListLoader?
    private var cells: Set<PhotoViewCell> = Set<PhotoViewCell>()
    private var imageCache: ImageCache!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(title: "Clear Caches", style: .plain, target: self, action: #selector(clearCaches))
        ]
        
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Refresh", style: .plain, target: self, action: #selector(refresh))
        ]
        
        imageCache = try! CacheImageCache.init(name: "Photos", sizeLimit: 10 * 1024 * 1024)
        self.startLoadingResults();
    }

    let progressView = UIProgressView(progressViewStyle: .default)
    let spinnerView = UIActivityIndicatorView(style: .gray)
    
    func showSpinnerView() {
        if spinnerView.superview == .none {
            self.view.addSubview(spinnerView)
            spinnerView.hidesWhenStopped = true
            spinnerView.center = self.view.center
            spinnerView.startAnimating()
        }
    }
    
    func showProgressView() {
        if progressView.superview == .none {
            self.view.addSubview(progressView)
            progressView.center = self.view.center
            progressView.setProgress(0, animated: false)
        }
    }
    
    func hideSpinnerAndProgressView() {
        spinnerView.stopAnimating()
        progressView.removeFromSuperview()
        spinnerView.removeFromSuperview()
    }
    
    @objc
    private func clearCaches() {
        URLCache.shared.removeAllCachedResponses()
        imageCache.clear()
    }
    
    @objc
    private func refresh() {
        startLoadingResults()
    }
    
    private func clearResults() {
        users = []
        self.loader?.imageFinished = .none
        loader = .none
        cells.removeAll()
        collectionView!.reloadData()
    }
    
    private func startLoadingResults() {
        clearResults()
        showSpinnerView()
        
        firstly {
            RandomUser.get(resultCount: 5000, reportProgressTo: self.progressChanged)
        }.ensure {
            self.hideSpinnerAndProgressView()
        }.done { response in
            let urls = response.results.map { user in URL(string: user.picture!.large!)! }
            self.users = response.results
            self.loader = ImageListLoader.init(urls: urls, transform: self.transformImage, imageLoader: ImageUrlSessionLoader.init(), imageCache: self.imageCache)
            self.loader?.imageFinished = self.onImageFinishedLoading
            self.collectionView!.reloadData()
        }.catch {
            print($0)
        }
    }

    func transformImage(image: UIImage) -> UIImage {
        // Beware transformations run on a separate queue
        return image.rounded(radius: 20)
    }
    
    func progressChanged(current: Int, total: Int) {
        let percent = Float(current) / Float(total)
        DispatchQueue.main.async {
            if total > 0 {
                if current != total {
                    self.showProgressView()
                }
                self.progressView.setProgress(percent, animated: true)
            } else {
                self.showSpinnerView()
            }
        }
    }
    
    private func onImageFinishedLoading(index: Int) {
        // We can't use visibleCells as it's missing loaded cells that are out of screen, and cells can't
        // subscribe to their promises as tehre is not way to unsubscribe also looping a few elements and
        // comparing integers is cheap (We're on the main thread)
        for cell in cells {
            if cell.index == index {
                cell.refreshPhoto()
            }
        }
    }
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
        cells.insert(cell)
        
        let photoIndex = indexPath.row
        let image = self.loader!.promises[photoIndex]
        let user = self.users[photoIndex]
        
        if image.result == nil {
            // The image isn't there yet, try to start loading it immediately
            loader!.prioritize(index: photoIndex, isPrefetch: false)
        }
        
        cell.showUser(user, withImage: image, atIndex: photoIndex)
        
        return cell
    }
}

extension PhotosViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            // Prioritize it's download but don't force start
            loader!.prioritize(index: indexPath.row, isPrefetch: true)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // No need to cancel as we don't force-start downloads until the item is really in view
    }
}

extension PhotosViewController: UICollectionViewDelegateFlowLayout
{
    func getItemSize() -> CGFloat {
        let padding = sectionInsets.left * (CGFloat(itemsPerRow) + 1)
        let availableWidth = view.frame.width - padding
        return availableWidth / CGFloat(itemsPerRow)
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemSize = getItemSize();

        
        return CGSize(width: itemSize, height: itemSize)
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
