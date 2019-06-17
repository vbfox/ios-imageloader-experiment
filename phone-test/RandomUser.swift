import Foundation
import PromiseKit
import PMKFoundation

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

class RandomUser
{
    static let bgq = DispatchQueue.global(qos: .userInitiated)
    
    static func get(resultCount: Int = 500,
                    session: URLSession = URLSession.shared,
                    bgQueue: DispatchObject? = bgq,
                    reportProgressTo progress: @escaping ProgressReport)
        -> Promise<RandomUserResponse> {
        
        func createRequest() -> URLRequest {
            let url = URL(string: "https://randomuser.me/api/?results=\(resultCount)&seed=zenly&inc=name,picture&noinfo")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
        
        let x: Promise<Data> = downloadWithProgress(createRequest(), reportProgressTo: progress)
        return firstly {
            x
        }.compactMap(on: bgq) { data in
            try JSONDecoder().decode(RandomUserResponse.self, from: data)
        }
    }
}
