import Foundation

/// Captures the text that a synchronous call writes to the standard output of
/// the process, so that a test can make assertions on what an example prints.
///
/// The capture moves the `STDOUT_FILENO` descriptor onto a pipe while the call
/// runs, and then puts the original descriptor back. A child task reads the
/// pipe while the call runs, so a large write cannot fill the pipe and block
/// the call.
///
/// The redirection applies to the whole process. Tests run in parallel, so a
/// different test that prints while the call runs also writes into the
/// capture. A caller must thus keep only the lines that its own call writes.
enum StandardOutputCapture {
    /// The failures that stop a capture.
    enum CaptureError: Error {
        /// `dup(_:)` could not make a copy of the original standard output
        /// descriptor. `code` is the `errno` value.
        case duplicateFailed(code: Int32)
        /// `dup2(_:_:)` could not move the pipe onto standard output. `code`
        /// is the `errno` value.
        case redirectFailed(code: Int32)
        /// `dup2(_:_:)` could not put the original descriptor back onto
        /// standard output. `code` is the `errno` value.
        case restoreFailed(code: Int32)
        /// The captured bytes are not valid UTF-8.
        case invalidUTF8
    }

    /// Runs `body` and returns all of the text that the process wrote to
    /// standard output while `body` ran.
    ///
    /// - Parameter body: the call whose standard output to capture.
    /// - Returns: the captured text, decoded as UTF-8.
    /// - Throws: `CaptureError` when a descriptor operation fails, or when
    ///   the captured bytes are not valid UTF-8.
    static func capture(_ body: () -> Void) async throws -> String {
        let pipe = Pipe()
        let originalDescriptor = dup(STDOUT_FILENO)
        guard originalDescriptor >= 0 else {
            throw CaptureError.duplicateFailed(code: errno)
        }
        defer { close(originalDescriptor) }

        // Write the text that the C streams hold now to the original
        // destination, before the redirection starts.
        fflush(nil)
        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
            throw CaptureError.redirectFailed(code: errno)
        }

        async let captured = readToEnd(of: pipe.fileHandleForReading)
        body()
        // Write the text that `body` left in the C stream buffers into the
        // pipe, before the original descriptor comes back.
        fflush(nil)
        let restoreFailure = restoreStandardOutput(from: originalDescriptor)
        // The pipe gets its end of file only when no descriptor refers to its
        // write end. The reader task then stops.
        try pipe.fileHandleForWriting.close()
        let data = try await captured

        if let restoreFailure {
            throw restoreFailure
        }
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw CaptureError.invalidUTF8
        }
        return text
    }

    /// Puts `originalDescriptor` back onto standard output.
    ///
    /// When `dup2(_:_:)` fails, this closes `STDOUT_FILENO`, so that no
    /// descriptor refers to the write end of the pipe and the reader task can
    /// stop.
    ///
    /// - Parameter originalDescriptor: the copy of the original standard output
    ///   descriptor.
    /// - Returns: `nil` on success, or the failure to throw after the reader
    ///   task stops.
    private static func restoreStandardOutput(from originalDescriptor: Int32) -> CaptureError? {
        guard dup2(originalDescriptor, STDOUT_FILENO) < 0 else {
            return nil
        }
        let failure = CaptureError.restoreFailed(code: errno)
        close(STDOUT_FILENO)
        return failure
    }

    /// Reads `handle` until its end of file.
    ///
    /// - Parameter handle: the read end of the capture pipe.
    /// - Returns: all of the bytes that the pipe carried.
    private static func readToEnd(of handle: FileHandle) async throws -> Data {
        try handle.readToEnd() ?? Data()
    }
}
