import CipherleafDomain
import XCTest

@testable import CipherleafApplication

@MainActor
final class DocumentSessionFormatValidationTests: XCTestCase {
  func testDotenvCreatesDottedNameAsOneFlatKey() async throws {
    let session = try await makeSession(
      format: .dotenv,
      root: .object(["TOKEN": .string("synthetic")])
    )

    let path = try session.pathForNewValue(" SERVICE.TOKEN ")
    try session.add(.string("dotted-synthetic"), at: path)

    XCTAssertEqual(path.components, [.key("SERVICE.TOKEN")])
    XCTAssertEqual(
      session.value(at: path),
      .string("dotted-synthetic")
    )
  }

  func testDotenvRejectsNestedMutationBeforeSave() async throws {
    let session = try await makeSession(
      format: .dotenv,
      root: .object(["TOKEN": .string("synthetic")])
    )
    let nestedPath = try SecretPath.parseEditablePath("SERVICE.TOKEN")

    XCTAssertThrowsError(
      try session.add(.string("nested-synthetic"), at: nestedPath)
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("one-level keys"))
      XCTAssertFalse(error.localizedDescription.contains("nested-synthetic"))
    }
    XCTAssertFalse(session.isDirty)
    XCTAssertFalse(session.canUndo)
  }

  func testReservedSOPSMetadataPathIsRejectedBeforeMutation() async throws {
    let session = try await makeSession(
      format: .yaml,
      root: .object(["token": .string("synthetic")])
    )
    let metadataPath = try SecretPath.parseEditablePath("sops.mac")

    XCTAssertThrowsError(
      try session.add(.string("synthetic-mac"), at: metadataPath)
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("reserved"))
      XCTAssertFalse(error.localizedDescription.contains("synthetic-mac"))
    }
    XCTAssertFalse(session.isDirty)
  }

  func testRenameNormalizesWhitespaceAcceptedByValidation() async throws {
    let source = SecretPath(components: [.key("token")])
    let session = try await makeSession(
      format: .yaml,
      root: .object(["token": .string("synthetic")])
    )

    XCTAssertTrue(session.isValidRenameKey(" credential ", at: source))
    let destination = try session.rename(at: source, to: " credential ")

    XCTAssertEqual(destination, SecretPath(components: [.key("credential")]))
    XCTAssertEqual(session.value(at: destination), .string("synthetic"))
  }

  func testDotenvCanRenameDottedFlatKey() async throws {
    let source = SecretPath(components: [.key("SERVICE.TOKEN")])
    let session = try await makeSession(
      format: .dotenv,
      root: .object(["SERVICE.TOKEN": .string("synthetic")])
    )

    XCTAssertTrue(session.canRename(at: source))
    XCTAssertTrue(
      session.isValidRenameKey("SERVICE.CREDENTIAL", at: source)
    )
    let destination = try session.rename(
      at: source,
      to: "SERVICE.CREDENTIAL"
    )

    XCTAssertEqual(
      destination,
      SecretPath(components: [.key("SERVICE.CREDENTIAL")])
    )
    XCTAssertEqual(session.value(at: destination), .string("synthetic"))
  }

  func testJSONCanRenameAddressableKeyContainingDot() async throws {
    let source = SecretPath(components: [.key("service.token")])
    let session = try await makeSession(
      format: .json,
      root: .object(["service.token": .string("synthetic")])
    )

    XCTAssertTrue(session.canRename(at: source))
    XCTAssertTrue(session.isValidRenameKey("credential", at: source))
    let destination = try session.rename(at: source, to: "credential")

    XCTAssertEqual(destination, SecretPath(components: [.key("credential")]))
    XCTAssertEqual(session.value(at: destination), .string("synthetic"))
  }

  func testRenameValidationRejectsNoOpAndExistingSibling() async throws {
    let source = SecretPath(components: [.key("token")])
    let session = try await makeSession(
      format: .yaml,
      root: .object([
        "credential": .string("synthetic-credential"),
        "token": .string("synthetic-token"),
      ])
    )

    XCTAssertFalse(session.isValidRenameKey(" token ", at: source))
    XCTAssertFalse(session.isValidRenameKey("credential", at: source))
  }

  private func makeSession(
    format: SOPSFileFormat,
    root: SecretValue
  ) async throws -> DocumentSession {
    let recipient = try AgeRecipient(
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    )
    let client = EncryptedFileClient(
      open: { _, _ in
        OpenedSOPSFile(
          root: root,
          format: format,
          recipients: [recipient],
          identityRecipients: [recipient],
          policyURL: nil,
          revision: FileRevision(
            digest: "initial",
            byteCount: 1,
            modifiedAt: nil
          )
        )
      },
      save: { _ in
        XCTFail("Format validation must reject invalid mutations before save.")
        return SavedSOPSFile(
          revision: FileRevision(
            digest: "unexpected",
            byteCount: 1,
            modifiedAt: nil
          ),
          sourceContainsComments: false
        )
      },
      diagnoseTools: { [] }
    )
    let session = DocumentSession(client: client)
    try await session.open(
      manifestURL: URL(fileURLWithPath: "/tmp/synthetic.sops.\(format.rawValue)"),
      identityURL: URL(fileURLWithPath: "/tmp/synthetic-identity.txt")
    )
    return session
  }
}
