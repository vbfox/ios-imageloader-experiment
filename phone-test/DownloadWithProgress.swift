import Foundation
import PromiseKit
import PMKFoundation

typealias ProgressReport = (Int, Int) -> Void

private class SessionWithProgressReport: NSObject, URLSessionDataDelegate {
    private(set) var session: URLSession!
    private(set) var promise: Promise<Data>! = .none
    private(set) var resolver: Resolver<Data>! = .none
    private var data: Data = Data()
    private let report: ProgressReport
    private var expectedContentLength = 0
    private var contentLength = 0
    
    init(report: @escaping ProgressReport) {
        self.report = report
        super.init()
        
        let (promise, resolver) = Promise<Data>.pending()
        self.resolver = resolver
        self.promise = promise
        
        session = Foundation.URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.data.append(data)
        contentLength += data.count
        report(contentLength, expectedContentLength)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: (URLSession.ResponseDisposition) -> Void) {
        expectedContentLength = Int(response.expectedContentLength)
        report(0, expectedContentLength)
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        report(expectedContentLength, expectedContentLength)
        if let error = error {
            resolver.reject(error)
        } else {
            resolver.fulfill(data)
        }
    }
}

private func sessionWithProgressReport(reportProgressTo progress: @escaping ProgressReport) -> (URLSession, Promise<Data>) {
    let session = SessionWithProgressReport(report: progress)
    return (session.session, session.promise)
}

func downloadWithProgress(_ url: URLRequestConvertible, reportProgressTo progress: @escaping ProgressReport) -> Promise<Data> {
    let (session, promise) = sessionWithProgressReport(reportProgressTo: progress)
    session.dataTask(with: url.pmkRequest).resume()
    return promise
}
