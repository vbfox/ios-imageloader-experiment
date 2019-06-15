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

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + self.lowercased().dropFirst()
    }
}

class RandomUserPicture: Codable {
    var large: String?
    var medium: String?
    var thumbnail: String?
}

class RandomuserName: Codable {
    var title: String = ""
    var first: String = ""
    var last: String = ""
    
    func toString() -> String {
        return "\(first.capitalizingFirstLetter()) \(last.capitalizingFirstLetter())"
    }
}

class RandomUserInfo: Codable {
    var gender: String = ""
    var name: RandomuserName
    var picture: RandomUserPicture
}


class RandomUserResponse: Codable {
    var results: [RandomUserInfo] = []
}

final class PhotosViewController: UICollectionViewController {
    private let reuseIdentifier = "PhotoCell"
    private let itemsPerRow: Int = 3
    private let sectionInsets = UIEdgeInsets(top: 20.0, left: 10.0, bottom: 20.0, right: 10.0)
    let bgq = DispatchQueue.global(qos: .userInitiated)
    var users: [RandomUserInfo] = []
    var photos: [UIImage?] = []
    
    override func viewDidLoad() {
        NSLog("viewDidLoad")
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Do any additional setup after loading the view.
        self.startLoadingResults();
    }

    func getRandomUsers() -> Promise<RandomUserResponse> {
        func createRequest() -> URLRequest {
            let url = URL(string: "https://randomuser.me/api/?results=500&seed=zenly")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
        
        return firstly {
            URLSession.shared.dataTask(.promise, with: createRequest()).validate()
        }.compactMap(on: bgq) {
            try JSONDecoder().decode(RandomUserResponse.self, from: $0.data)
        }
    }
    
    func startLoadingResults() {
        firstly {
            getRandomUsers()
        }.done { foo in
            self.users = foo.results
            self.photos = Array(repeating: nil, count: foo.results.count)
            for i in 0...foo.results.count-1 {
                let user = foo.results[i]
                self.collectionView!.reloadData()
                self.loadUserImageAndUpdate(index: i, user: user);
            }
            print(foo.results.count)
            print(foo.results[0].gender)
            print(foo.results[0].picture.large!)
        }.catch {
            print($0)
        }
    }
    
    func loadUserImageAndUpdate(index: Int, user: RandomUserInfo) {
        firstly {
            loadUserImage(user: user)
        }.done { image in
            self.photos[index] = image;
            print(String(format: "Loaded user image at index %i", index))
            self.collectionView!.reloadData()
            }.catch {
                print($0)
        }
    }
    
    func loadUserImage(user: RandomUserInfo) -> Promise<UIImage> {
        func makeImageRequest(urlString: String) -> URLRequest {
            let url = URL(string: urlString)!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        
        let req = makeImageRequest(urlString: user.picture.large!)
        return firstly {
            URLSession.shared.dataTask(.promise, with: req).validate()
        }.compactMap(on: bgq) {
            UIImage(data: $0.data)
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
        return self.photos.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! PhotoViewCell
        
        let image = self.photos[indexPath.row]
        let user = self.users[indexPath.row]
        //cell.backgroundColor = UIColor.orange
        cell.foo.text = user.name.toString()
        if image != nil {
            cell.backgroundColor = UIColor.white
            cell.imageOutlet.image = image
            cell.foo.textColor = UIColor.white

        } else {
            cell.backgroundColor = UIColor.red
            cell.foo.textColor = UIColor.black
        }
        
        
        return cell
    }
}

extension PhotosViewController: UICollectionViewDelegateFlowLayout
{
    //1
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        //2
        let paddingSpace = sectionInsets.left * (CGFloat(itemsPerRow) + 1)
        let availableWidth = view.frame.width - paddingSpace
        let widthPerItem = availableWidth / CGFloat(itemsPerRow)
        
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
    
    //3
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        
        return sectionInsets
    }
    
    // 4
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return sectionInsets.left
    }
}
