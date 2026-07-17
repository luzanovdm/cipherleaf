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
    self.outputLimit = max(0, outputLimit)
    self.timeoutSeconds = max(0, timeoutSeconds)
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
    let pipes = try SpawnPipes()
    defer {
      pipes.closeAll()
    }

    let processIdentifier = try spawn(request, pipes: pipes)
    pipes.closeChildEnds()
    state.install(processGroup: processIdentifier)
    defer {
      state.clear(processGroup: processIdentifier)
    }

    let outputCapture = PipeCapture(
      handle: pipes.outputRead,
      limit: request.outputLimit
    )
    let errorCapture = PipeCapture(
      handle: pipes.errorRead,
      limit: min(request.outputLimit, 1_024 * 1_024)
    )
    outputCapture.start()
    errorCapture.start()

    do {
      if let input = request.input {
        try writeAll(input, to: pipes.inputWrite.fileDescriptor)
      }
      try pipes.inputWrite.close()
    } catch {
      state.requestTermination(.cancelled)
      try? pipes.inputWrite.close()
      _ = try? waitForExit(processIdentifier)
      _ = try? outputCapture.finish()
      _ = try? errorCapture.finish()
      throw error
    }

    let status = try waitForExit(processIdentifier)
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

    let exitStatus = decodedExitStatus(status)
    guard exitStatus == 0 else {
      throw ProcessExecutorError.commandFailed(
        executable: request.executable.lastPathComponent,
        status: exitStatus,
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

  private static func spawn(
    _ request: ProcessRequest,
    pipes: SpawnPipes
  ) throws -> pid_t {
    guard
      request.environment.keys.allSatisfy({
        !$0.contains("=") && !$0.utf8.contains(0)
      })
    else {
      throw ProcessExecutorError.invalidRequest
    }
    var fileActions: posix_spawn_file_actions_t?
    try checkSpawnCall(
      posix_spawn_file_actions_init(&fileActions),
      operation: "initialize file actions"
    )
    defer {
      posix_spawn_file_actions_destroy(&fileActions)
    }

    try checkSpawnCall(
      posix_spawn_file_actions_adddup2(
        &fileActions,
        pipes.inputRead.fileDescriptor,
        STDIN_FILENO
      ),
      operation: "configure standard input"
    )
    try checkSpawnCall(
      posix_spawn_file_actions_adddup2(
        &fileActions,
        pipes.outputWrite.fileDescriptor,
        STDOUT_FILENO
      ),
      operation: "configure standard output"
    )
    try checkSpawnCall(
      posix_spawn_file_actions_adddup2(
        &fileActions,
        pipes.errorWrite.fileDescriptor,
        STDERR_FILENO
      ),
      operation: "configure standard error"
    )

    for descriptor in pipes.allDescriptors where descriptor > STDERR_FILENO {
      try checkSpawnCall(
        posix_spawn_file_actions_addclose(&fileActions, descriptor),
        operation: "close inherited pipe"
      )
    }

    if let currentDirectory = request.currentDirectory {
      let result = currentDirectory.withUnsafeFileSystemRepresentation { path in
        guard let path else {
          return EINVAL
        }
        return posix_spawn_file_actions_addchdir_np(&fileActions, path)
      }
      try checkSpawnCall(result, operation: "configure working directory")
    }

    var attributes: posix_spawnattr_t?
    try checkSpawnCall(
      posix_spawnattr_init(&attributes),
      operation: "initialize spawn attributes"
    )
    defer {
      posix_spawnattr_destroy(&attributes)
    }
    try checkSpawnCall(
      posix_spawnattr_setflags(
        &attributes,
        Int16(POSIX_SPAWN_SETPGROUP)
      ),
      operation: "configure process group"
    )
    try checkSpawnCall(
      posix_spawnattr_setpgroup(&attributes, 0),
      operation: "create process group"
    )

    let executablePath = request.executable.path
    let arguments = [executablePath] + request.arguments
    let environment = request.environment
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    var processIdentifier = pid_t()

    try withCStringArray(arguments) { argumentPointers in
      try withCStringArray(environment) { environmentPointers in
        let result = executablePath.withCString { executablePointer in
          argumentPointers.withUnsafeMutableBufferPointer { argumentsBuffer in
            environmentPointers.withUnsafeMutableBufferPointer {
              environmentBuffer in
              posix_spawn(
                &processIdentifier,
                executablePointer,
                &fileActions,
                &attributes,
                argumentsBuffer.baseAddress,
                environmentBuffer.baseAddress
              )
            }
          }
        }
        try checkSpawnCall(result, operation: "spawn process")
      }
    }
    return processIdentifier
  }

  private static func withCStringArray<Result>(
    _ values: [String],
    body: (inout [UnsafeMutablePointer<CChar>?]) throws -> Result
  ) throws -> Result {
    guard values.allSatisfy({ !$0.utf8.contains(0) }) else {
      throw ProcessExecutorError.invalidRequest
    }

    var pointers = try values.map { value in
      guard let pointer = strdup(value) else {
        throw ProcessExecutorError.systemCall(
          operation: "allocate process argument",
          code: ENOMEM
        )
      }
      return Optional(pointer)
    }
    pointers.append(nil)
    defer {
      for pointer in pointers {
        free(pointer)
      }
    }
    return try body(&pointers)
  }

  private static func checkSpawnCall(
    _ result: Int32,
    operation: String
  ) throws {
    guard result == 0 else {
      throw ProcessExecutorError.systemCall(
        operation: operation,
        code: result
      )
    }
  }

  private static func writeAll(
    _ data: Data,
    to descriptor: Int32
  ) throws {
    guard Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw ProcessExecutorError.systemCall(
        operation: "configure process input",
        code: errno
      )
    }
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else {
        return
      }
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if written < 0, errno == EINTR {
          continue
        }
        guard written > 0 else {
          throw ProcessExecutorError.systemCall(
            operation: "write process input",
            code: written == 0 ? EIO : errno
          )
        }
        offset += written
      }
    }
  }

  private static func waitForExit(_ processIdentifier: pid_t) throws -> Int32 {
    var status = Int32()
    while Darwin.waitpid(processIdentifier, &status, 0) < 0 {
      if errno != EINTR {
        throw ProcessExecutorError.systemCall(
          operation: "wait for process",
          code: errno
        )
      }
    }
    return status
  }

  private static func decodedExitStatus(_ status: Int32) -> Int32 {
    let signal = status & 0x7f
    if signal == 0 {
      return (status >> 8) & 0xff
    }
    return 128 + signal
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
