import Foundation
import PromiseKit
import PMKFoundation

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + self.lowercased().dropFirst()
    }
}

private func adapter<T, U>(_ seal: Resolver<(data: T, response: U)>) -> (T?, U?, Error?) -> Void {
    return { t, u, e in
        if let t = t, let u = u {
            seal.fulfill((t, u))
        } else if let e = e {
            seal.reject(e)
        } else {
            seal.reject(PMKError.invalidCallingConvention)
        }
    }
}

extension URLSession {
    public func dataTaskAndPromise(with convertible: URLRequestConvertible) -> (task: URLSessionDataTask, promise: Promise<(data: Data, response: URLResponse)>) {
        var task: URLSessionDataTask?
        let promise = Promise<(data: Data, response: URLResponse)> {
            task = dataTask(with: convertible.pmkRequest, completionHandler: adapter($0))
            task!.resume()
        }
        
        return (task!, promise)
    }
}
