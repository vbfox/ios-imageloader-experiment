import Foundation
import PromiseKit
import PMKFoundation

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
