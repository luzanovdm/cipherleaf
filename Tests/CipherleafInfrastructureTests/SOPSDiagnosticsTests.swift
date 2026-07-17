import CipherleafApplication
import XCTest

@testable import CipherleafInfrastructure

final class SOPSDiagnosticsTests: XCTestCase {
  func testFailingVersionCommandsAreReportedUnavailable() async {
    let client = SOPSCLIClient.live(
      configurationStore: ToolConfigurationStore(
        ToolConfiguration(
          sopsPath: "/usr/bin/false",
          ageKeygenPath: "/usr/bin/false"
        )
      )
    )

    let diagnostics = await client.diagnoseTools()

    XCTAssertEqual(diagnostics.count, 2)
    for diagnostic in diagnostics {
      guard case .unavailable = diagnostic.state else {
        return XCTFail(
          "\(diagnostic.name) should be unavailable when its version command fails."
        )
      }
    }
  }
}
