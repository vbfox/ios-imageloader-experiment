import Foundation
import PromiseKit
import PMKFoundation

class RandomUser
{
    static let bgq = DispatchQueue.global(qos: .userInitiated)
    
    static func get(resultCount: Int = 500,
                    session: URLSession = URLSession.shared,
                    bgQueue: DispatchObject? = bgq)
        -> Promise<RandomUserResponse> {
        
        func createRequest() -> URLRequest {
            let url = URL(string: "https://randomuser.me/api/?results=\(resultCount)&inc=name,picture&noinfo")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
        
        return firstly {
            URLSession.shared.dataTask(.promise, with: createRequest()).validate()
            }.compactMap(on: bgq) { (data, _) in
            try JSONDecoder().decode(RandomUserResponse.self, from: data)
        }
    }
}
