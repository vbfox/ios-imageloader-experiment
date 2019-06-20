import Foundation

import XCTest
import PromiseKit
@testable import phone_test

class TestLoader: ImageUrlLoader {
    var promises: Dictionary<String, Promise<UIImage>> = [:]
    
    func loadImageFrom(_ url: URL, on queue: DispatchQueue) -> Promise<UIImage> {
        let p = promises[url.absoluteString]!
        promises[url.absoluteString] = nil
        return p
    }
}

class ImageDownloadQueueTests: XCTestCase {
    let url1 = URL(string: "http://example.com/1")!
    let img1 = UIImage(named: "PoopRainbow_Avatar")!
    let url2 = URL(string: "http://example.com/2")!
    let img2 = UIImage(named: "zenly_lion")!
    
    func testAddDownloads() {
        let ex = expectation(description: "")
        let loader = TestLoader()
        let dlQueue = ImageDownloadQueue(loader: loader, maxInProgress: 1)
        
        let (p1, r1) = Promise<UIImage>.pending()
        loader.promises[url1.absoluteString] = p1
        
        dlQueue.add(url: url1).done { i in
            XCTAssertEqual(i, self.img1)
            ex.fulfill()
        }.cauterize()
        
        r1.fulfill(img1)
        waitForExpectations(timeout: 1)
    }
    
    func testParallelLimit() {
        let ex1 = expectation(description: "")
        let ex2 = expectation(description: "")
        let loader = TestLoader()
        let dlQueue = ImageDownloadQueue(loader: loader, maxInProgress: 1)
        
        let (p1, r1) = Promise<UIImage>.pending()
        loader.promises[url1.absoluteString] = p1
        
        dlQueue.add(url: url1).done { i in
            XCTAssertEqual(i, self.img1)
            ex1.fulfill()
        }.cauterize()
        
        dlQueue.add(url: url2).done { i in
            XCTAssertEqual(i, self.img2)
            ex2.fulfill()
        }.cauterize()
        
        Thread.sleep(forTimeInterval: 1)
        
        let (p2, r2) = Promise<UIImage>.pending()
        loader.promises[url2.absoluteString] = p2
        r1.fulfill(img1)
        
        wait(for: [ex1], timeout: 1)
        
        r2.fulfill(img2)
        wait(for: [ex2], timeout: 1)
    }
}
