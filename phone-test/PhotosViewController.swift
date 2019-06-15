import UIKit
import PromiseKit

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
