import XCTest

@testable import CipherleafDomain

final class DocumentPatchTests: XCTestCase {
  func testPatchContainsMinimalPathOperations() throws {
    let baseline = SecretValue.object([
      "changed": .string("old-synthetic"),
      "nested": .object([
        "kept": .boolean(true),
        "removed": .string("removed-synthetic"),
      ]),
    ])
    let candidate = SecretValue.object([
      "added": .string("added-synthetic"),
      "changed": .string("new-synthetic"),
      "nested": .object([
        "kept": .boolean(true)
      ]),
    ])

    let patch = DocumentPatch.between(
      baseline: baseline,
      candidate: candidate
    )

    XCTAssertEqual(
      patch.changes.map(\.path.display),
      ["$.added", "$.changed", "$.nested.removed"]
    )
    XCTAssertEqual(
      patch.changes.map(\.kind),
      [.added, .changed, .removed]
    )
  }

  func testPatchNeverExposesValuesThroughChangeDescriptions() {
    let baseline = SecretValue.object([
      "token": .string("old-synthetic")
    ])
    let candidate = SecretValue.object([
      "token": .string("new-synthetic")
    ])

    let rendered =
      DocumentPatch
      .between(baseline: baseline, candidate: candidate)
      .changes
      .map(\.id)
      .joined(separator: "\n")

    XCTAssertFalse(rendered.contains("old-synthetic"))
    XCTAssertFalse(rendered.contains("new-synthetic"))
  }

  func testArrayChangeUsesSingleSetAtElementPath() {
    let baseline = SecretValue.object([
      "items": .array([.string("one"), .string("two")])
    ])
    let candidate = SecretValue.object([
      "items": .array([.string("one"), .string("changed")])
    ])

    let patch = DocumentPatch.between(
      baseline: baseline,
      candidate: candidate
    )

    XCTAssertEqual(
      patch.operations,
      [
        .set(
          path: SecretPath(
            components: [.key("items"), .index(1)]
          ),
          value: .string("changed")
        )
      ]
    )
  }

  func testArrayShrinkUnsetsIndicesFromEnd() {
    let baseline = SecretValue.object([
      "items": .array([
        .string("one"),
        .string("two"),
        .string("three"),
        .string("four"),
      ])
    ])
    let candidate = SecretValue.object([
      "items": .array([.string("one"), .string("two")])
    ])

    let patch = DocumentPatch.between(
      baseline: baseline,
      candidate: candidate
    )

    XCTAssertEqual(
      patch.operations,
      [
        .unset(
          path: SecretPath(components: [.key("items"), .index(3)])
        ),
        .unset(
          path: SecretPath(components: [.key("items"), .index(2)])
        ),
      ]
    )
  }

  func testArrayRemovalUsesOriginalIndexWhenCandidateIsSubsequence() {
    let baseline = SecretValue.object([
      "items": .array([
        .string("one"),
        .string("two"),
        .string("three"),
      ])
    ])
    let candidate = SecretValue.object([
      "items": .array([.string("one"), .string("three")])
    ])
    let patch = DocumentPatch.between(
      baseline: baseline,
      candidate: candidate
    )

    XCTAssertEqual(
      patch.operations,
      [
        .unset(
          path: SecretPath(components: [.key("items"), .index(1)])
        )
      ]
    )
  }
}
