import CipherleafDomain
import XCTest

@testable import CipherleafApplication

@MainActor
final class DocumentSessionTests: XCTestCase {
  func testUndoRedoAndSaveLifecycle() async throws {
    let manifestURL = URL(fileURLWithPath: "/tmp/synthetic.sops.yaml")
    let identityURL = URL(fileURLWithPath: "/tmp/synthetic-identity.txt")
    let recipient = try AgeRecipient(
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    )
    let root = SecretValue.object([
      "token": .string("synthetic")
    ])
    let revision = FileRevision(
      digest: "initial",
      byteCount: 1,
      modifiedAt: nil
    )

    let client = EncryptedFileClient(
      open: { _, _ in
        OpenedSOPSFile(
          root: root,
          format: .yaml,
          recipients: [recipient],
          identityRecipients: [recipient],
          policyURL: nil,
          revision: revision
        )
      },
      save: { request in
        XCTAssertEqual(
          request.candidate.root.value(
            at: SecretPath(components: [.key("token")])
          ),
          .string("updated-synthetic")
        )
        return SavedSOPSFile(
          revision: FileRevision(
            digest: "saved",
            byteCount: 2,
            modifiedAt: nil
          ),
          sourceContainsComments: false
        )
      },
      diagnoseTools: { [] }
    )
    let session = DocumentSession(client: client)
    let tokenPath = SecretPath(components: [.key("token")])

    try await session.open(
      manifestURL: manifestURL,
      identityURL: identityURL
    )
    try session.set(.string("updated-synthetic"), at: tokenPath)
    session.endHistoryCoalescing()

    XCTAssertTrue(session.canUndo)
    session.undo()
    XCTAssertEqual(session.value(at: tokenPath), .string("synthetic"))
    session.redo()
    XCTAssertEqual(
      session.value(at: tokenPath),
      .string("updated-synthetic")
    )

    let candidate = try XCTUnwrap(
      session.prepareSave(incrementingGeneration: false)
    )
    try await session.save(candidate)

    XCTAssertFalse(session.isDirty)
    XCTAssertEqual(session.revision?.digest, "saved")
  }

  func testTypingCoalescesUndoHistoryPerPath() async throws {
    let root = SecretValue.object(["token": .string("")])
    let recipient = try AgeRecipient(
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    )
    let client = EncryptedFileClient(
      open: { _, _ in
        OpenedSOPSFile(
          root: root,
          format: .yaml,
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
        SavedSOPSFile(
          revision: FileRevision(
            digest: "saved",
            byteCount: 1,
            modifiedAt: nil
          ),
          sourceContainsComments: false
        )
      },
      diagnoseTools: { [] }
    )
    let session = DocumentSession(client: client)
    let path = SecretPath(components: [.key("token")])
    try await session.open(
      manifestURL: URL(fileURLWithPath: "/tmp/synthetic.sops.yaml"),
      identityURL: URL(fileURLWithPath: "/tmp/identity.txt")
    )

    try session.set(.string("a"), at: path)
    try session.set(.string("ab"), at: path)
    try session.set(.string("abc"), at: path)
    session.endHistoryCoalescing()
    session.undo()

    XCTAssertEqual(session.value(at: path), .string(""))
  }

  func testCloseClearsSensitiveSessionReferences() async throws {
    let recipient = try AgeRecipient(
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    )
    let client = EncryptedFileClient(
      open: { _, _ in
        OpenedSOPSFile(
          root: .object(["token": .string("synthetic")]),
          format: .yaml,
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
        SavedSOPSFile(
          revision: FileRevision(
            digest: "saved",
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
      manifestURL: URL(fileURLWithPath: "/tmp/synthetic.sops.yaml"),
      identityURL: URL(fileURLWithPath: "/tmp/synthetic-identity.txt")
    )
    try session.close()

    XCTAssertNil(session.document)
    XCTAssertNil(session.identityURL)
    XCTAssertNil(session.manifestURL)
    XCTAssertTrue(session.identityRecipients.isEmpty)
    XCTAssertTrue(session.recipients.isEmpty)
    XCTAssertEqual(session.phase, .closed)
  }

  func testSavingRejectsConcurrentMutationAndClose() async throws {
    let gate = SaveGate()
    let recipient = try AgeRecipient(
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    )
    let tokenPath = SecretPath(components: [.key("token")])
    let client = EncryptedFileClient(
      open: { _, _ in
        OpenedSOPSFile(
          root: .object(["token": .string("synthetic")]),
          format: .yaml,
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
        await gate.block()
        return SavedSOPSFile(
          revision: FileRevision(
            digest: "saved",
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
      manifestURL: URL(fileURLWithPath: "/tmp/synthetic.sops.yaml"),
      identityURL: URL(fileURLWithPath: "/tmp/synthetic-identity.txt")
    )
    try session.set(.string("candidate"), at: tokenPath)
    let candidate = try XCTUnwrap(
      session.prepareSave(incrementingGeneration: false)
    )

    let saveTask = Task {
      try await session.save(candidate)
    }
    await gate.waitUntilBlocked()

    XCTAssertEqual(session.phase, .saving)
    XCTAssertThrowsError(
      try session.set(.string("late-edit"), at: tokenPath)
    )
    XCTAssertThrowsError(try session.close())

    await gate.release()
    try await saveTask.value

    XCTAssertEqual(session.value(at: tokenPath), .string("candidate"))
    XCTAssertEqual(session.phase, .open)
  }
}

private actor SaveGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isBlocked = false

  func block() async {
    isBlocked = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilBlocked() async {
    while !isBlocked {
      await Task.yield()
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}
