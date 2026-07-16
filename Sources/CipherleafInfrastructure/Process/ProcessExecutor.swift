import Darwin
@preconcurrency import Foundation

enum ProcessFailureOutputPolicy: Sendable {
  case diagnostic
  case redacted
}

struct ProcessRequest: Sendable {
  let executable: URL
  let arguments: [String]
  let input: Data?
  let currentDirectory: URL?
  let environment: [String: String]
  let failureOutputPolicy: ProcessFailureOutputPolicy
  let outputLimit: Int
  let timeoutSeconds: TimeInterval

  init(
    executable: URL,
    arguments: [String],
    input: Data? = nil,
    currentDirectory: URL? = nil,
    environment: [String: String] = [:],
    failureOutputPolicy: ProcessFailureOutputPolicy = .redacted,
    outputLimit: Int = 64 * 1_024 * 1_024,
    timeoutSeconds: TimeInterval = 120
  ) {
    self.executable = executable
    self.arguments = arguments
    self.input = input
    self.currentDirectory = currentDirectory
    self.environment = environment
    self.failureOutputPolicy = failureOutputPolicy
    self.outputLimit = outputLimit
    self.timeoutSeconds = timeoutSeconds
  }
}

struct ProcessOutput: Sendable {
  let standardOutput: Data
  let standardError: Data
}

struct ProcessExecutor: Sendable {
  func run(_ request: ProcessRequest) async throws -> ProcessOutput {
    try Task.checkCancellation()
    let state = ProcessExecutionState()
    let execution = Task.detached(priority: .userInitiated) {
      try Self.runSynchronously(request, state: state)
    }
    let output = try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
        group.addTask {
          try await execution.value
        }
        group.addTask {
          try await Task.sleep(
            for: .seconds(request.timeoutSeconds)
          )
          state.requestTermination(.timedOut)
          throw ProcessExecutorError.timedOut(
            executable: request.executable.lastPathComponent,
            seconds: request.timeoutSeconds
          )
        }

        guard let first = try await group.next() else {
          throw CancellationError()
        }
        group.cancelAll()
        return first
      }
    } onCancel: {
      state.requestTermination(.cancelled)
    }
    try Task.checkCancellation()
    return output
  }

  private static func runSynchronously(
    _ request: ProcessRequest,
    state: ProcessExecutionState
  ) throws -> ProcessOutput {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let inputPipe = Pipe()
    let outputCapture = PipeCapture(
      handle: outputPipe.fileHandleForReading,
      limit: request.outputLimit
    )
    let errorCapture = PipeCapture(
      handle: errorPipe.fileHandleForReading,
      limit: min(request.outputLimit, 1_024 * 1_024)
    )

    process.executableURL = request.executable
    process.arguments = request.arguments
    process.currentDirectoryURL = request.currentDirectory
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    process.standardInput = inputPipe
    process.environment = request.environment

    try process.run()
    do {
      try state.install(process)
    } catch {
      process.terminate()
      process.waitUntilExit()
      state.clear()
      throw error
    }
    defer {
      state.clear()
    }

    outputCapture.start()
    errorCapture.start()

    do {
      if let input = request.input {
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
      }
      try inputPipe.fileHandleForWriting.close()
    } catch {
      process.terminate()
      try? inputPipe.fileHandleForWriting.close()
      process.waitUntilExit()
      _ = try? outputCapture.finish()
      _ = try? errorCapture.finish()
      throw error
    }

    process.waitUntilExit()
    let output = try outputCapture.finish()
    let errorOutput = try errorCapture.finish()

    if let termination = state.termination {
      switch termination {
      case .cancelled:
        throw CancellationError()
      case .timedOut:
        throw ProcessExecutorError.timedOut(
          executable: request.executable.lastPathComponent,
          seconds: request.timeoutSeconds
        )
      }
    }

    guard process.terminationStatus == 0 else {
      throw ProcessExecutorError.commandFailed(
        executable: request.executable.lastPathComponent,
        status: process.terminationStatus,
        message:
          request.failureOutputPolicy == .diagnostic
          ? sanitize(errorOutput)
          : ""
      )
    }

    return ProcessOutput(
      standardOutput: output,
      standardError: errorOutput
    )
  }

  private static func sanitize(_ data: Data) -> String {
    let rawValue = String(decoding: data.prefix(8_192), as: UTF8.self)
    return
      rawValue
      .replacingOccurrences(
        of: #"AGE-SECRET-KEY-[A-Z0-9-]+"#,
        with: "[redacted age identity]",
        options: .regularExpression
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private enum ProcessTermination: Sendable {
  case cancelled
  case timedOut
}

private final class ProcessExecutionState: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var storedTermination: ProcessTermination?

  var termination: ProcessTermination? {
    lock.withLock {
      storedTermination
    }
  }

  func install(_ process: Process) throws {
    let wasTerminated = lock.withLock {
      let wasTerminated = storedTermination != nil
      self.process = process
      return wasTerminated
    }
    if wasTerminated {
      process.terminate()
      throw CancellationError()
    }
  }

  func requestTermination(_ termination: ProcessTermination) {
    let process = lock.withLock {
      if storedTermination == nil {
        storedTermination = termination
      }
      return self.process
    }
    guard let process, process.isRunning else {
      return
    }
    process.terminate()
    forceTerminateIfNeeded(process)
  }

  func clear() {
    lock.withLock {
      process = nil
    }
  }

  private func forceTerminateIfNeeded(_ process: Process) {
    let processIdentifier = process.processIdentifier
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + .seconds(1)
    ) { [weak self, weak process] in
      guard let self, let process else {
        return
      }
      let shouldTerminate = self.lock.withLock {
        self.process === process && process.isRunning
      }
      if shouldTerminate {
        Darwin.kill(processIdentifier, SIGKILL)
      }
    }
  }
}

private final class PipeCapture: @unchecked Sendable {
  private let group = DispatchGroup()
  private let handle: FileHandle
  private let limit: Int
  private let lock = NSLock()
  private var captured = Data()
  private var didOverflow = false

  init(handle: FileHandle, limit: Int) {
    self.handle = handle
    self.limit = limit
  }

  func start() {
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      defer {
        group.leave()
      }

      while true {
        let chunk = handle.readData(ofLength: 64 * 1_024)
        guard !chunk.isEmpty else {
          return
        }

        lock.withLock {
          if captured.count + chunk.count <= limit {
            captured.append(chunk)
          } else {
            didOverflow = true
          }
        }
      }
    }
  }

  func finish() throws -> Data {
    group.wait()
    return try lock.withLock {
      guard !didOverflow else {
        throw ProcessExecutorError.outputLimitExceeded(limit)
      }
      return captured
    }
  }
}

enum ProcessExecutorError: LocalizedError {
  case commandFailed(executable: String, status: Int32, message: String)
  case outputLimitExceeded(Int)
  case timedOut(executable: String, seconds: TimeInterval)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let executable, let status, let message):
      if message.isEmpty {
        "\(executable) exited with status \(status)."
      } else {
        "\(executable) exited with status \(status): \(message)"
      }
    case .outputLimitExceeded(let limit):
      "The command produced more than \(limit) bytes of output."
    case .timedOut(let executable, let seconds):
      "\(executable) did not finish within \(seconds.formatted()) seconds."
    }
  }
}
