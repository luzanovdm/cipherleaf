import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class ProcessExecutorTests: XCTestCase {
  func testTimeoutTerminatesLongRunningProcess() async {
    let startedAt = ContinuousClock.now

    do {
      _ = try await ProcessExecutor().run(
        ProcessRequest(
          executable: URL(fileURLWithPath: "/bin/sleep"),
          arguments: ["5"],
          timeoutSeconds: 0.1
        )
      )
      XCTFail("Expected the process to time out.")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("did not finish"))
      XCTAssertLessThan(
        startedAt.duration(to: .now),
        .seconds(2)
      )
    }
  }

  func testDiagnosticOutputRedactsAgeIdentity() async {
    let identity = "AGE-" + "SECRET-" + "KEY-1SYNTHETIC"

    do {
      _ = try await ProcessExecutor().run(
        ProcessRequest(
          executable: URL(fileURLWithPath: "/bin/sh"),
          arguments: [
            "-c",
            "printf '%s' '\(identity)' >&2; exit 1",
          ],
          failureOutputPolicy: .diagnostic
        )
      )
      XCTFail("Expected the process to fail.")
    } catch {
      XCTAssertFalse(error.localizedDescription.contains(identity))
      XCTAssertTrue(
        error.localizedDescription.contains("[redacted age identity]")
      )
    }
  }

  func testTimeoutForceTerminatesProcessThatIgnoresTerminate() async {
    let startedAt = ContinuousClock.now

    do {
      _ = try await ProcessExecutor().run(
        ProcessRequest(
          executable: URL(fileURLWithPath: "/bin/sh"),
          arguments: [
            "-c",
            "trap '' TERM; while :; do :; done",
          ],
          timeoutSeconds: 0.1
        )
      )
      XCTFail("Expected the process to time out.")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("did not finish"))
      XCTAssertLessThan(
        startedAt.duration(to: .now),
        .seconds(3)
      )
    }
  }
}
