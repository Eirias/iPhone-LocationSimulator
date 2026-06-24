//
//  GoIOS.swift
//  GoIOSKit
//
//  Thin async wrapper around the `go-ios` CLI. Locates the binary, runs subcommands,
//  parses go-ios' JSON-lines output, and maps failures to structured errors.
//
//  Verified behaviour (iPhone 16 Pro, iOS 26.5, go-ios local-build, June 2026):
//    * `go-ios list`                 -> {"deviceList":["<udid>", ...]}
//    * `go-ios info`                 -> one large JSON object (ProductVersion, DeviceName, ...)
//    * `go-ios image auto`           -> downloads + mounts the personalized DDI (no tunnel needed)
//    * `go-ios setlocation/...`      -> needs a running `sudo go-ios tunnel start`; otherwise
//                                       fails with InvalidService on com.apple.dt.simulatelocation
//
//  Only the tunnel needs root. list/info/image and set/reset location run as the normal
//  user and discover the tunnel via go-ios' local tunnel-info API (default port 28100).
//

import Foundation

/// Thread-safe mutable `Data` holder used to collect pipe output from background queues
/// (a `DispatchGroup` barrier for one-shot reads, or a `readabilityHandler` for streaming).
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        get { lock.lock(); defer { lock.unlock() }; return _data }
        set { lock.lock(); defer { lock.unlock() }; _data = newValue }
    }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        _data.append(chunk)
    }

    /// Current contents decoded as UTF-8.
    var string: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

public final class GoIOS: @unchecked Sendable {
    /// Resolved path to the go-ios executable.
    public let binaryURL: URL

    /// Writable working directory for every go-ios invocation. go-ios stores state
    /// relative to the current directory (e.g. `./devimages` for the DDI), so a GUI app
    /// launched with CWD=`/` would hit "read-only file system". We pin a writable dir.
    public let workingDirectory: URL

    /// - Parameter binaryURL: explicit path to the go-ios binary. If nil, a set of common
    ///   locations and `$PATH` are searched (see ``resolveBinary()``).
    /// - Throws: ``GoIOSError/binaryNotFound`` if no binary can be located.
    public init(binaryURL: URL? = nil) throws {
        if let binaryURL {
            self.binaryURL = binaryURL
        } else {
            self.binaryURL = try GoIOS.resolveBinary()
        }
        workingDirectory = GoIOS.resolveWorkingDirectory()
    }

    /// A writable directory for go-ios state, under Application Support, with a temp-dir
    /// fallback. Created if it does not exist.
    static func resolveWorkingDirectory() -> URL {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("LocationSimulator/goios", isDirectory: true)
            if (try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                return dir
            }
        }
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("goios", isDirectory: true)
        try? fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    // MARK: - Binary resolution

    /// Candidate locations for the go-ios binary, in priority order.
    public static func candidatePaths() -> [String] {
        var paths: [String] = []
        if let env = ProcessInfo.processInfo.environment["GOIOS_PATH"], !env.isEmpty {
            paths.append(env)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/go/bin/go-ios")
        paths.append("/opt/homebrew/bin/go-ios")
        paths.append("/usr/local/bin/go-ios")
        // Upstream docs install the binary as `ios`; support a symlink/alias too.
        paths.append("\(home)/go/bin/ios")
        paths.append("/opt/homebrew/bin/ios")
        paths.append("/usr/local/bin/ios")
        return paths
    }

    static func resolveBinary() throws -> URL {
        let candidates = candidatePaths()
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw GoIOSError.binaryNotFound(searched: candidates)
    }

    // MARK: - Orphan reaping

    /// Best-effort: kill any leftover held go-ios processes (tunnel / setlocation /
    /// setlocationgpx) for `udid`. macOS does NOT terminate child processes when the parent
    /// dies, so a force-killed or crashed app run (e.g. Xcode "Stop", which sends SIGKILL
    /// and skips all cleanup) leaves orphans (PPID 1) that keep holding the tunnel-info port
    /// 60105 and the device's LocationSimulation channel with a stale coordinate. Reaping
    /// before we start a fresh tunnel guarantees a clean slate regardless of how the
    /// previous run ended. Call this only when about to (re)start the tunnel — never while
    /// our own tunnel is meant to be running.
    static func reapStaleProcesses(udid: String?) {
        // (1) ANY go-ios tunnel agent. The tunnel-info server binds the SHARED port 60105,
        //     so even a leftover `tunnel start` with no `--udid` (or for another device)
        //     blocks us. SIGKILL releases the listener socket immediately.
        runPkill(["-9", "-f", "go-ios.* tunnel start"], describing: "tunnel")
        // (2) Held location processes for THIS device only (don't disturb other devices).
        if let udid, !udid.isEmpty {
            runPkill(["-9", "-f", "go-ios.*(setlocation|setlocationgpx).*\(udid)"],
                     describing: "location \(udid)")
        }
    }

    private static func runPkill(_ arguments: [String], describing what: String) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = arguments
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        do {
            try pkill.run()
            pkill.waitUntilExit()
            // pkill exits 0 when it killed something, 1 when nothing matched — both fine.
            if pkill.terminationStatus == 0 {
                NSLog("[go-ios] reaped stale %@ process(es)", what)
            }
        } catch {
            NSLog("[go-ios] reap (%@) failed: %@", what, error.localizedDescription)
        }
    }

    // MARK: - Process execution

    /// Environment for every go-ios invocation. We deliberately do NOT enable the
    /// experimental agent mode (`ENABLE_GO_IOS_AGENT`). The proven path (matching the
    /// working AppKit build) is a plain `tunnel start --userspace` whose tunnel-info server
    /// the location commands AUTO-DISCOVER. Enabling agent mode together with passing an
    /// explicit `--address`/`--rsd-port` endpoint made `setlocation` hang at "Looking for
    /// device" and never apply the location on-device.
    static func agentEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment
    }

    /// Run an arbitrary go-ios subcommand and return the parsed invocation result.
    /// Does **not** throw on a non-zero exit — inspect ``GoIOSInvocation`` yourself, or
    /// use the higher-level helpers which apply success rules.
    public func run(_ arguments: [String]) async throws -> GoIOSInvocation {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runBlocking(arguments)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous process invocation. Reads stdout and stderr concurrently to avoid
    /// pipe-buffer deadlocks on large output (e.g. the `info` dump).
    func runBlocking(_ arguments: [String]) throws -> GoIOSInvocation {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.agentEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Read stderr on a background queue while we drain stdout on this one. The box
        // is written only inside the closure and read only after `errGroup.wait()`, so
        // the access is ordered and safe.
        let errBox = DataBox()
        let errQueue = DispatchQueue(label: "goios.stderr")
        let errGroup = DispatchGroup()
        errGroup.enter()
        errQueue.async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }

        do {
            try process.run()
        } catch {
            throw GoIOSError.launchFailed(error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errBox.data, encoding: .utf8) ?? ""
        let raw = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        return GoIOSInvocation(raw: raw, exitCode: process.terminationStatus)
    }

    /// Parse newline-delimited JSON, dropping any line that is not a JSON object.
    static func parseJSONLines(_ text: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result.append(obj)
            }
        }
        return result
    }

    // MARK: - Argument builders (shared by sync + async paths)

    private static func infoArgs(_ udid: String?) -> [String] {
        var args = ["info"]
        if let udid { args += ["--udid=\(udid)"] }
        return args
    }

    private static func mountArgs(_ udid: String?, _ baseDir: String?) -> [String] {
        var args = ["image", "auto"]
        if let baseDir { args += ["--basedir=\(baseDir)"] }
        if let udid { args += ["--udid=\(udid)"] }
        return args
    }

    private static func setLocationArgs(_ udid: String?, _ lat: Double, _ lon: Double) -> [String] {
        var args = ["setlocation", "--lat=\(lat)", "--lon=\(lon)"]
        if let udid { args += ["--udid=\(udid)"] }
        return args
    }

    private static func resetLocationArgs(_ udid: String?) -> [String] {
        var args = ["resetlocation"]
        if let udid { args += ["--udid=\(udid)"] }
        return args
    }

    // MARK: - Result interpreters (shared by sync + async paths)

    private static func parseDeviceList(_ result: GoIOSInvocation) throws -> [String] {
        for line in result.jsonLines {
            if let list = line["deviceList"] as? [String] { return list }
        }
        // Empty device list is a valid, non-error outcome.
        if result.exitCode == 0 { return [] }
        throw failure(from: result)
    }

    private static func parseInfo(_ result: GoIOSInvocation, udid: String?) throws -> GoIOSDeviceInfo {
        guard let obj = result.jsonLines.first(where: {
            $0["ProductVersion"] != nil || $0["UniqueDeviceID"] != nil
        }) else {
            if !result.errorLines.isEmpty || result.exitCode != 0 {
                throw failure(from: result)
            }
            throw GoIOSError.unexpectedOutput("no device info object in:\n\(result.raw)")
        }
        let resolvedUDID = (obj["UniqueDeviceID"] as? String) ?? udid ?? ""
        return GoIOSDeviceInfo(
            udid: resolvedUDID,
            name: (obj["DeviceName"] as? String) ?? resolvedUDID,
            version: obj["ProductVersion"] as? String,
            productName: obj["ProductName"] as? String,
            productType: obj["ProductType"] as? String,
            connectionType: .usb
        )
    }

    private static func expectSuccess(_ result: GoIOSInvocation) throws {
        if result.exitCode == 0, result.errorLines.isEmpty { return }
        throw failure(from: result)
    }

    // MARK: - High-level operations (synchronous core)

    /// List UDIDs of all currently connected devices (`go-ios list`).
    public func listDeviceUDIDsSync() throws -> [String] {
        try GoIOS.parseDeviceList(runBlocking(["list"]))
    }

    /// Fetch structured info for a device (`go-ios info`).
    public func infoSync(udid: String?) throws -> GoIOSDeviceInfo {
        try GoIOS.parseInfo(runBlocking(GoIOS.infoArgs(udid)), udid: udid)
    }

    /// Download (if needed) and mount the (personalized) Developer Disk Image
    /// (`go-ios image auto`). Works over lockdown — no tunnel required.
    public func mountDeveloperImageSync(udid: String?, baseDir: String? = nil) throws {
        try GoIOS.expectSuccess(runBlocking(GoIOS.mountArgs(udid, baseDir)))
    }

    /// Set the simulated location (`go-ios setlocation`). Requires a running tunnel.
    public func setLocationSync(udid: String?, latitude: Double, longitude: Double) throws {
        try GoIOS.expectSuccess(runBlocking(GoIOS.setLocationArgs(udid, latitude, longitude)))
    }

    /// Stop spoofing and reset to the real device location (`go-ios resetlocation`).
    public func resetLocationSync(udid: String?) throws {
        try GoIOS.expectSuccess(runBlocking(GoIOS.resetLocationArgs(udid)))
    }

    // MARK: - High-level operations (async wrappers)

    /// List UDIDs of all currently connected devices (`go-ios list`).
    public func listDeviceUDIDs() async throws -> [String] {
        try GoIOS.parseDeviceList(await run(["list"]))
    }

    /// Fetch structured info for a device (`go-ios info`).
    /// - Parameter udid: target device; if nil, go-ios uses the first device.
    public func info(udid: String?) async throws -> GoIOSDeviceInfo {
        try GoIOS.parseInfo(await run(GoIOS.infoArgs(udid)), udid: udid)
    }

    /// Download (if needed) and mount the (personalized) Developer Disk Image.
    public func mountDeveloperImage(udid: String?, baseDir: String? = nil) async throws {
        try GoIOS.expectSuccess(await run(GoIOS.mountArgs(udid, baseDir)))
    }

    /// Set the simulated location (`go-ios setlocation`). Requires a running tunnel.
    public func setLocation(udid: String?, latitude: Double, longitude: Double) async throws {
        try GoIOS.expectSuccess(await run(GoIOS.setLocationArgs(udid, latitude, longitude)))
    }

    /// Set the simulated location from a GPX file (`go-ios setlocationgpx`).
    public func setLocationGPX(udid: String?, gpxPath: String) async throws {
        var args = ["setlocationgpx", "--gpxfilepath=\(gpxPath)"]
        if let udid { args += ["--udid=\(udid)"] }
        try GoIOS.expectSuccess(await run(args))
    }

    /// Stop spoofing and reset to the real device location (`go-ios resetlocation`).
    public func resetLocation(udid: String?) async throws {
        try GoIOS.expectSuccess(await run(GoIOS.resetLocationArgs(udid)))
    }

    /// The running tunnel's endpoint for `udid` (from `go-ios tunnel ls`), or nil if no
    /// tunnel is up. Requires the tunnel to have been started in agent mode.
    public func tunnelEndpoint(udid: String?) async -> GoIOSTunnelEndpoint? {
        guard let result = try? await run(["tunnel", "ls"]) else { return nil }
        return GoIOS.parseTunnelEndpoint(result.raw, udid: udid)
    }

    /// Synchronous variant for use from polling loops.
    public func tunnelEndpointBlocking(udid: String?) -> GoIOSTunnelEndpoint? {
        guard let result = try? runBlocking(["tunnel", "ls"]) else { return nil }
        return GoIOS.parseTunnelEndpoint(result.raw, udid: udid)
    }

    public func isTunnelRunning(udid: String?) async -> Bool {
        await tunnelEndpoint(udid: udid) != nil
    }

    public func isTunnelRunningBlocking(udid: String?) -> Bool {
        tunnelEndpointBlocking(udid: udid) != nil
    }

    /// `tunnel ls` prints a JSON **array** line (`[{...}]`). Parse it and pull the entry
    /// for the device (or the first one).
    static func parseTunnelEndpoint(_ raw: String, udid: String?) -> GoIOSTunnelEndpoint? {
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            let entry = udid.flatMap { id in array.first { ($0["udid"] as? String) == id } } ?? array.first
            if let entry,
               let address = entry["address"] as? String,
               let rsdPort = entry["rsdPort"] as? Int
            {
                return GoIOSTunnelEndpoint(address: address, rsdPort: rsdPort)
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Detect an error signature in raw go-ios output (used while watching a held
    /// process). Returns nil if no error is present.
    static func detectError(in raw: String) -> GoIOSError? {
        guard !raw.isEmpty else { return nil }
        let invocation = GoIOSInvocation(raw: raw, exitCode: 0)
        guard !invocation.errorLines.isEmpty else { return nil }
        return failure(from: GoIOSInvocation(raw: raw, exitCode: 1))
    }

    /// Map a failed invocation to the most specific error we can detect.
    static func failure(from result: GoIOSInvocation) -> GoIOSError {
        let haystack = (result.errorLines.compactMap { $0["msg"] as? String } + [result.raw])
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("invalidservice")
            || haystack.contains("simulatelocation")
            || haystack.contains("failed to get tunnel info")
        {
            return .tunnelNotRunning
        }
        let message = result.errorLines.compactMap { line -> String? in
            let msg = line["msg"] as? String
            let err = line["err"] as? String
            return [msg, err].compactMap { $0 }.joined(separator: ": ")
        }.first ?? "unknown error"
        return .commandFailed(message: message, raw: result.raw, exitCode: result.exitCode)
    }
}
