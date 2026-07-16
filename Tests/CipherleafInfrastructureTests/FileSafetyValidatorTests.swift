import Darwin
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class FileSafetyValidatorTests: XCTestCase {
  func testIdentityRequiresPrivatePermissions() throws {
    let fixture = try TemporaryDirectory()
    let identityURL = fixture.url.appendingPathComponent("identity.txt")
    try Data("synthetic-identity".utf8).write(to: identityURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: identityURL.path
    )

    XCTAssertThrowsError(
      try FileSafetyValidator().validateIdentity(identityURL)
    )

    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: identityURL.path
    )
    XCTAssertNoThrow(
      try FileSafetyValidator().validateIdentity(identityURL)
    )
  }

  func testManifestRejectsSymbolicLink() throws {
    let fixture = try TemporaryDirectory()
    let targetURL = fixture.url.appendingPathComponent("target.sops.yaml")
    let linkURL = fixture.url.appendingPathComponent("link.sops.yaml")
    try Data("synthetic-ciphertext".utf8).write(to: targetURL)
    try FileManager.default.createSymbolicLink(
      at: linkURL,
      withDestinationURL: targetURL
    )

    XCTAssertThrowsError(
      try FileSafetyValidator().validateManifest(linkURL)
    )
  }

  func testIdentityRejectsUnexpectedlyLargeFile() throws {
    let fixture = try TemporaryDirectory()
    let identityURL = fixture.url.appendingPathComponent("identity.txt")
    try Data(repeating: 0, count: 1_024 * 1_024 + 1).write(to: identityURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: identityURL.path
    )

    XCTAssertThrowsError(
      try FileSafetyValidator().validateIdentity(identityURL)
    )
  }
}
