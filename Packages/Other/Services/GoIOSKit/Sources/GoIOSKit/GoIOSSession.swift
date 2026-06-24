//
//  GoIOSSession.swift
//  GoIOSKit
//
//  Long-lived process management for the iOS 17+/26 spoofing flow.
//
//  Two empirical facts (verified iPhone 16 Pro, iOS 26.5, June 2026) drive this design:
//
//  1. NO ROOT. `go-ios tunnel start --userspace` brings up the iOS 17.4+ lockdown tunnel
//     as a normal user — no sudo, no privileged helper, no `remoted` pause needed.
//     => The app can manage the tunnel as a plain child process.
//
//  2. `setlocation` HOLDS the session. The `go-ios setlocation` process does NOT exit;
//     it keeps the DVT connection open to maintain the simulated location. Closing it
//     reverts the device to its real GPS. => Location is a *session*, not a one-shot.
//
//  ``GoIOSTunnel`` owns the tunnel child; ``GoIOSLocationSession`` owns the held
//  setlocation child. Both are root-free.
//

import Foundation

// MARK: - Diagnostics

/// Streams a child process' output to the system log so the *real* go-ios diagnostics are
/// visible. Previously tunnel/setlocation output went to `/dev/null`, which hid why a
/// spoof silently failed on-device (e.g. a foreign tunnel agent on the tunnel-info port).
/// Attach to a `Pipe`'s read handle; logs line-prefixed. Pass `capture` to also accumulate
/// the bytes (so `start()` can inspect the exit reason).
enum GoIOSLog {
    static func stream(_ pipe: Pipe, tag: String, capture: DataBox? = nil) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            capture?.append(data)
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
                NSLog("[go-ios/%@] %@", tag, String(line))
            }
        }
    }
}

// MARK: - Tunnel

/// Manages the long-lived `go-ios tunnel start --userspace` child process.
/// Root-free on iOS 17.4+. Keep one instance alive for as long as you want to spoof.
public final class GoIOSTunnel: @unchecked Sendable {
    private let goios: GoIOS
    private let udid: String?
    private let queue = DispatchQueue(label: "com.locationsimulator.goios.tunnel")
    private var process: Process?

    public init(goios: GoIOS, udid: String?) {
        self.goios = goios
        self.udid = udid
    }

    public var isProcessAlive: Bool {
        queue.sync { process?.isRunning ?? false }
    }

    /// Start the tunnel and block until it is queryable (or `timeout` elapses).
    /// Idempotent: a no-op if a tunnel process is already alive here.
    public func start(userspace: Bool = true, timeout: TimeInterval = 25) throws {
        if isProcessAlive { return }
        let infoPort = 60105
        let maxAttempts = 3
        var lastError: Error = GoIOSError.tunnelPortInUse(port: infoPort)
        for attempt in 1 ... maxAttempts {
            // Reap leftover agents/sessions that own the shared tunnel-info port (incl. a
            // global `tunnel start` with no udid, or orphans from a SIGKILLed prior run).
            // We retry to absorb the brief window before the OS releases the socket.
            GoIOS.reapStaleProcesses(udid: udid)
            do {
                try startOnce(userspace: userspace, timeout: timeout, infoPort: infoPort)
                return
            } catch let error as GoIOSError {
                lastError = error
                if case .tunnelPortInUse = error, attempt < maxAttempts {
                    NSLog("[go-ios] tunnel port %d busy (attempt %d/%d) — reaping & retrying",
                          infoPort, attempt, maxAttempts)
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    /// One tunnel-start attempt: spawn our child and block until `tunnel ls` answers while
    /// our child is alive, or fail (port conflict / early exit / timeout).
    private func startOnce(userspace: Bool, timeout: TimeInterval, infoPort: Int) throws {
        // Captures the child's stderr so we can read *why* it exited (e.g. port conflict),
        // while GoIOSLog.stream still mirrors it to the system log.
        let errBox = DataBox()

        try queue.sync {
            if process?.isRunning == true { return }

            var args = ["-v", "tunnel", "start"]
            if userspace { args.append("--userspace") }
            if let udid { args += ["--udid=\(udid)"] }

            let proc = Process()
            proc.executableURL = goios.binaryURL
            proc.arguments = args
            proc.currentDirectoryURL = goios.workingDirectory
            // Agent/daemon mode: makes `tunnel ls` reliably report the tunnel endpoint
            // (address + rsdPort), which we then pass explicitly to set/gpx commands. Every
            // other go-ios invocation uses the same env (GoIOS.agentEnvironment).
            proc.environment = GoIOS.agentEnvironment()
            // Stream output to the system log (instead of /dev/null) so tunnel failures —
            // port conflict, pairing/trust, exit-before-ready — are diagnosable on-device.
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            GoIOSLog.stream(outPipe, tag: "tunnel/out")
            GoIOSLog.stream(errPipe, tag: "tunnel/err", capture: errBox)
            do {
                try proc.run()
            } catch {
                throw GoIOSError.launchFailed("tunnel: \(error.localizedDescription)")
            }
            process = proc
        }

        // Poll until the tunnel is reachable. Runs outside the lock so other calls aren't blocked.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // A port conflict can be reported before the child fully exits — detect it
            // directly so we never ride a foreign agent's tunnel.
            if errBox.string.localizedCaseInsensitiveContains("address already in use") {
                stop()
                throw GoIOSError.tunnelPortInUse(port: infoPort)
            }
            // Our own child exited before becoming ready — surface the captured reason
            // (checked before the API so a foreign agent can't mask our child's death).
            if !isProcessAlive {
                let raw = errBox.string
                stop()
                throw GoIOSError.commandFailed(
                    message: "tunnel process exited before becoming ready",
                    raw: raw, exitCode: -1
                )
            }
            // Ready only when `tunnel ls` answers AND our own child is still alive (above).
            if goios.isTunnelRunningBlocking(udid: udid) { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        stop()
        throw GoIOSError.commandFailed(message: "tunnel did not become ready in \(Int(timeout))s", raw: "", exitCode: -1)
    }

    /// Terminate the tunnel. Any active location session ends with it.
    public func stop() {
        queue.sync {
            process?.terminate()
            process = nil
        }
    }

    deinit { stop() }
}

// MARK: - Location session

/// Manages the held `go-ios setlocation` child process. Setting a new location replaces
/// the previous holder; stopping ends the simulation (device reverts to real GPS).
public final class GoIOSLocationSession: @unchecked Sendable {
    private let goios: GoIOS
    private let udid: String?
    private let queue = DispatchQueue(label: "com.locationsimulator.goios.location")
    private var process: Process?
    /// Grace window to catch an immediate failure (e.g. tunnel not running) before we
    /// treat the held process as "location applied".
    private let confirmWindow: TimeInterval

    public init(goios: GoIOS, udid: String?, confirmWindow: TimeInterval = 2.0) {
        self.goios = goios
        self.udid = udid
        self.confirmWindow = confirmWindow
    }

    public var isActive: Bool {
        queue.sync { process?.isRunning ?? false }
    }

    /// Set (and hold) a single simulated location. Replaces any previous holder.
    /// Pass `endpoint` to connect to a known tunnel directly (more reliable than
    /// auto-discovery; required for GPX).
    /// - Throws: ``GoIOSError/tunnelNotRunning`` if the tunnel is down, or
    ///           ``GoIOSError/commandFailed`` on other errors.
    public func setLocation(latitude: Double, longitude: Double, endpoint: GoIOSTunnelEndpoint? = nil) throws {
        var args = ["setlocation", "--lat=\(latitude)", "--lon=\(longitude)"]
        if let udid { args += ["--udid=\(udid)"] }
        args += endpoint?.arguments ?? []
        try startHeldProcess(args: args, label: "setlocation")
    }

    /// Play a GPX track (navigation along a route). Held as a long-lived process; the
    /// device moves along the track until it ends or `stop()` is called. `setlocationgpx`
    /// does not auto-discover the iOS 17+ tunnel reliably, so `endpoint` is effectively
    /// required.
    public func playGPX(path: String, endpoint: GoIOSTunnelEndpoint? = nil) throws {
        var args = ["setlocationgpx", "--gpxfilepath=\(path)"]
        args += endpoint?.arguments ?? []
        if let udid { args += ["--udid=\(udid)"] }
        try startHeldProcess(args: args, label: "setlocationgpx")
    }

    /// Like ``setLocation(latitude:longitude:endpoint:)`` but returns as soon as the holder
    /// is launched (no 2 s confirm wait), so callers can step it along a route at a steady
    /// cadence. Used to drive navigation via the proven setlocation path rather than the
    /// unreliable `setlocationgpx` GPX playback.
    public func step(latitude: Double, longitude: Double, endpoint: GoIOSTunnelEndpoint? = nil) throws {
        var args = ["setlocation", "--lat=\(latitude)", "--lon=\(longitude)"]
        if let udid { args += ["--udid=\(udid)"] }
        args += endpoint?.arguments ?? []
        try startHeldProcess(args: args, label: "setlocation", confirm: 0)
    }

    /// Spawn a go-ios command that is expected to KEEP RUNNING (it holds the location /
    /// plays a track). Replaces any previous holder. Watches a short confirm window: if
    /// the process dies or emits an ERROR line, surface it; otherwise treat it as live.
    private func startHeldProcess(args: [String], label: String, confirm: TimeInterval? = nil) throws {
        let errPipe = Pipe()
        let errBox = DataBox()
        // Capture stderr for error detection AND mirror it to the system log so a held
        // process that fails to apply the location on-device is diagnosable.
        GoIOSLog.stream(errPipe, tag: "\(label)/err", capture: errBox)

        let proc = Process()
        proc.executableURL = goios.binaryURL
        proc.currentDirectoryURL = goios.workingDirectory
        proc.environment = GoIOS.agentEnvironment()
        proc.arguments = ["-v"] + args
        // Stream stdout too — go-ios prints its confirmation / failure detail here.
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        GoIOSLog.stream(outPipe, tag: "\(label)/out")
        proc.standardError = errPipe

        queue.sync {
            process?.terminate()
            process = nil
        }

        do {
            try proc.run()
        } catch {
            throw GoIOSError.launchFailed("\(label): \(error.localizedDescription)")
        }
        queue.sync { process = proc }

        let deadline = Date().addingTimeInterval(confirm ?? confirmWindow)
        while Date() < deadline {
            if let failure = GoIOS.detectError(in: errBox.string) {
                stop()
                throw failure
            }
            if !proc.isRunning {
                let raw = errBox.string
                if proc.terminationStatus == 0, GoIOS.detectError(in: raw) == nil { return }
                throw GoIOS.failure(from: GoIOSInvocation(raw: raw, exitCode: proc.terminationStatus))
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// End the location simulation. The device reverts to its real GPS location.
    public func stop() {
        queue.sync {
            process?.terminate()
            process = nil
        }
    }

    deinit { stop() }
}
