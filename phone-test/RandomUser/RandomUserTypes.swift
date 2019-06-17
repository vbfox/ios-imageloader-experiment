import Foundation

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
    var gender: String?
    var name: RandomuserName?
    var picture: RandomUserPicture?
}

class RandomUserResponse: Codable {
    var results: [RandomUserInfo] = []
}
