import Darwin
@preconcurrency import Foundation

final class SpawnPipes {
  let errorRead: FileHandle
  let errorWrite: FileHandle
  let inputRead: FileHandle
  let inputWrite: FileHandle
  let outputRead: FileHandle
  let outputWrite: FileHandle

  init() throws {
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    inputRead = input.fileHandleForReading
    inputWrite = input.fileHandleForWriting
    outputRead = output.fileHandleForReading
    outputWrite = output.fileHandleForWriting
    errorRead = error.fileHandleForReading
    errorWrite = error.fileHandleForWriting

    for descriptor in allDescriptors {
      guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) != -1 else {
        throw ProcessExecutorError.systemCall(
          operation: "secure process pipe",
          code: errno
        )
      }
    }
  }

  var allDescriptors: [Int32] {
    [
      inputRead.fileDescriptor,
      inputWrite.fileDescriptor,
      outputRead.fileDescriptor,
      outputWrite.fileDescriptor,
      errorRead.fileDescriptor,
      errorWrite.fileDescriptor,
    ]
  }

  func closeChildEnds() {
    try? inputRead.close()
    try? outputWrite.close()
    try? errorWrite.close()
  }

  func closeAll() {
    try? inputRead.close()
    try? inputWrite.close()
    try? outputRead.close()
    try? outputWrite.close()
    try? errorRead.close()
    try? errorWrite.close()
  }
}

enum ProcessTermination: Sendable {
  case cancelled
  case timedOut
}

final class ProcessExecutionState: @unchecked Sendable {
  private let lock = NSLock()
  private var processGroup: pid_t?
  private var storedTermination: ProcessTermination?

  var termination: ProcessTermination? {
    lock.withLock {
      storedTermination
    }
  }

  func install(processGroup: pid_t) {
    let shouldTerminate = lock.withLock {
      self.processGroup = processGroup
      return storedTermination != nil
    }
    if shouldTerminate {
      terminate(processGroup)
    }
  }

  func requestTermination(_ termination: ProcessTermination) {
    let processGroup = lock.withLock {
      if storedTermination == nil {
        storedTermination = termination
      }
      return self.processGroup
    }
    if let processGroup {
      terminate(processGroup)
    }
  }

  func clear(processGroup: pid_t) {
    lock.withLock {
      if self.processGroup == processGroup {
        self.processGroup = nil
      }
    }
  }

  private func terminate(_ processGroup: pid_t) {
    _ = Darwin.kill(-processGroup, SIGTERM)
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + .seconds(1)
    ) { [weak self] in
      guard let self else {
        return
      }
      let shouldTerminate = self.lock.withLock {
        self.processGroup == processGroup
      }
      if shouldTerminate {
        _ = Darwin.kill(-processGroup, SIGKILL)
      }
    }
  }
}

final class PipeCapture: @unchecked Sendable {
  private let group = DispatchGroup()
  private let handle: FileHandle
  private let limit: Int
  private let lock = NSLock()
  private var captured = Data()
  private var didOverflow = false
  private var readError: Error?

  init(handle: FileHandle, limit: Int) {
    self.handle = handle
    self.limit = limit
  }

  func start() {
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      defer {
        try? handle.close()
        group.leave()
      }

      do {
        while let chunk = try handle.read(upToCount: 64 * 1_024),
          !chunk.isEmpty
        {
          lock.withLock {
            if captured.count + chunk.count <= limit {
              captured.append(chunk)
            } else {
              didOverflow = true
            }
          }
        }
      } catch {
        lock.withLock {
          readError = error
        }
      }
    }
  }

  func finish() throws -> Data {
    group.wait()
    return try lock.withLock {
      if let readError {
        throw readError
      }
      guard !didOverflow else {
        throw ProcessExecutorError.outputLimitExceeded(limit)
      }
      return captured
    }
  }
}

enum ProcessExecutorError: LocalizedError {
  case commandFailed(executable: String, status: Int32, message: String)
  case invalidRequest
  case outputLimitExceeded(Int)
  case systemCall(operation: String, code: Int32)
  case timedOut(executable: String, seconds: TimeInterval)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let executable, let status, let message):
      if message.isEmpty {
        "\(executable) exited with status \(status)."
      } else {
        "\(executable) exited with status \(status): \(message)"
      }
    case .invalidRequest:
      "The process request contains an invalid null byte."
    case .outputLimitExceeded(let limit):
      "The command produced more than \(limit) bytes of output."
    case .systemCall(let operation, let code):
      "\(operation) failed with errno \(code)."
    case .timedOut(let executable, let seconds):
      "\(executable) did not finish within \(seconds.formatted()) seconds."
    }
  }
}
