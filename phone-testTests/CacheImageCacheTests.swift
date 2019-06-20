import XCTest
import PromiseKit
@testable import phone_test

class CacheImageCacheTests: XCTestCase {
    func testInit() throws {
        let _ = try CacheImageCache.init(sizeLimit: 10 * 1000)
    }
    
    func testAddAndGet() throws {
        let ex = expectation(description: "")
        let cache = try CacheImageCache.init(sizeLimit: 10 * 1000)
        
        let url = URL(string: "https://example.com/a")!
        cache.add(url: url, image: UIImage(named: "zenly_lion")!).done { _ in ex.fulfill() }.cauterize()
        waitForExpectations(timeout: 1)
    }
    
    func testContains() throws {
        let ex = expectation(description: "")
        let cache = try CacheImageCache.init(sizeLimit: 10 * 1000)
        let url = URL(string: "https://example.com/a")!
        
        XCTAssertFalse(cache.contains(url: url))
        
        cache.add(url: url, image: UIImage(named: "zenly_lion")!).done { _ in
            XCTAssertTrue(cache.contains(url: url))
            ex.fulfill()
            }.cauterize()
        waitForExpectations(timeout: 1)
    }
    
    func testClear() throws {
        let ex = expectation(description: "")
        let cache = try CacheImageCache.init(sizeLimit: 10 * 1000)
        let url = URL(string: "https://example.com/a")!
        
        cache.add(url: url, image: UIImage(named: "zenly_lion")!).done { _ in
            cache.clear()
            XCTAssertFalse(cache.contains(url: url))
            ex.fulfill()
            }.cauterize()
        waitForExpectations(timeout: 1)
    }
}
