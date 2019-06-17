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

protocol ProgressReport {
    func progressChanged(current: Int, total: Int)
}

private class SessionWithProgressReport: NSObject, URLSessionDataDelegate {
    private(set) var session: URLSession!
    private let report: ProgressReport
    private var expectedContentLength = 0
    private var contentLength = 0
    
    init(report: ProgressReport) {
        self.report = report
        super.init()
        
        session = Foundation.URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        contentLength += data.count
        report.progressChanged(current: contentLength, total: expectedContentLength)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: (URLSession.ResponseDisposition) -> Void) {
        expectedContentLength = Int(response.expectedContentLength)
        report.progressChanged(current: 0, total: expectedContentLength)
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        report.progressChanged(current: expectedContentLength, total: expectedContentLength)
    }
}

func sessionWithProgressReport(withReport report: ProgressReport) -> URLSession {
    let session = SessionWithProgressReport.init(report: report)
    return session.session
}
