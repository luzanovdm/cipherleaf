import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class ToolLocatorTests: XCTestCase {
  func testRejectsExecutableDirectoryAsConfiguredTool() throws {
    let fixture = try TemporaryDirectory()
    let locator = ToolLocator(
      configurationStore: ToolConfigurationStore(
        ToolConfiguration(sopsPath: fixture.url.path)
      )
    )

    XCTAssertThrowsError(try locator.resolve(.sops)) { error in
      guard case ToolLocatorError.notRegularFile = error else {
        return XCTFail("Expected a non-regular-file error, got \(error).")
      }
    }
  }
}
