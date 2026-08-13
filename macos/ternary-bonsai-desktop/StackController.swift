import Foundation
import Darwin

enum StackLaunchError: LocalizedError {
    case missingResources(URL)
    case missingExecutable(String, URL)
    case unavailablePort
    case failedToStart(String)
    case terminated(String, Int32)
    case readinessTimeout(String, URL)
    case modelDownload(String)

    var errorDescription: String? {
        switch self {
        case .missingResources(let url):
            return "The app bundle is missing its Resources directory at \(url.path)."
        case .missingExecutable(let name, let url):
            return "Bundled executable `\(name)` is missing or not executable at \(url.path)."
        case .unavailablePort:
            return "Unable to allocate a local loopback port."
        case .failedToStart(let message):
            return "A stack process failed to start. \(message)"
        case .terminated(let name, let status):
            return "`\(name)` exited early with status \(status)."
        case .readinessTimeout(let name, let url):
            return "`\(name)` did not become healthy in time at \(url.absoluteString)."
        case .modelDownload(let message):
            return "Model download failed. \(message)"
        }
    }
}

struct StackURLs {
    let bridge: URL
    let ztUI: URL
    let inference: URL
}

final class StackController {
    private let resourcesURL: URL
    private let supportURL: URL
    private let mlxRepo = "prism-ml/Ternary-Bonsai-1.7B-mlx-2bit"
    private let mlxModelDirName = "Ternary-Bonsai-1.7B-mlx-2bit"

    private var processes: [Process] = []
    private var logPipes: [Pipe] = []
    private var urls: StackURLs?
    private let readinessTimeoutNanos: UInt64 = 300_000_000_000

    var stackURLs: StackURLs? { urls }

    init(bundle: Bundle = .main) throws {
        guard let resourcesURL = bundle.resourceURL else {
            throw StackLaunchError.missingResources(bundle.bundleURL)
        }
        self.resourcesURL = resourcesURL

        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let supportURL = supportRoot.appendingPathComponent("zt-ui Ternary Bonsai", isDirectory: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        self.supportURL = supportURL
    }

    /// Ensures the MLX weight directory exists under Application Support.
    func ensureModel(progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        let modelURL = supportURL.appendingPathComponent(mlxModelDirName, isDirectory: true)
        let weights = modelURL.appendingPathComponent("model.safetensors")
        if FileManager.default.fileExists(atPath: weights.path) {
            progress("MLX model ready.")
            return modelURL
        }

        let python = try mlxPython()
        progress("Downloading Ternary-Bonsai-1.7B MLX 2-bit (~480 MB)…")

        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-c",
            """
            from huggingface_hub import snapshot_download
            snapshot_download(
                repo_id="\(mlxRepo)",
                local_dir=r"\(modelURL.path)",
            )
            print("ok")
            """,
        ]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw StackLaunchError.modelDownload(error.localizedDescription)
        }

        process.waitUntilExit()
        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: weights.path) else {
            throw StackLaunchError.modelDownload(log.isEmpty ? "huggingface_hub snapshot_download failed." : log)
        }

        progress("MLX model saved.")
        return modelURL
    }

    func start(modelURL: URL, progress: @escaping @Sendable (String) -> Void) throws -> StackURLs {
        if let urls {
            return urls
        }

        let inferencePort = try Self.allocateLoopbackPort()
        let bridgePort = try Self.allocateLoopbackPort()
        let ztPort = try Self.allocateLoopbackPort()

        let inferenceURL = URL(string: "http://127.0.0.1:\(inferencePort)")!
        let bridgeURL = URL(string: "http://127.0.0.1:\(bridgePort)")!
        let ztURL = URL(string: "http://127.0.0.1:\(ztPort)")!

        progress("Starting zt-ui…")
        try startZtUI(port: ztPort)

        progress("Starting Ternary Bonsai (MLX)…")
        try startMlx(port: inferencePort, modelURL: modelURL)

        progress("Starting AudioEvent bridge…")
        try startBridge(port: bridgePort, inferenceURL: inferenceURL, ztURL: ztURL)

        let stack = StackURLs(bridge: bridgeURL, ztUI: ztURL, inference: inferenceURL)
        self.urls = stack
        return stack
    }

    func waitUntilReady(progress: @escaping @Sendable (String) -> Void) async throws {
        guard let urls else {
            throw StackLaunchError.failedToStart("Stack URLs were not initialized.")
        }

        progress("Waiting for MLX server…")
        try await waitHealthy(
            name: "mlx_lm.server",
            url: urls.inference.appending(path: "v1/models"),
            acceptStatuses: [200]
        )

        progress("Waiting for bridge…")
        try await waitHealthy(name: "bridge", url: urls.bridge.appending(path: "healthz"), acceptStatuses: [200])

        progress("Waiting for zt-ui…")
        try await waitHealthy(name: "zt-ui", url: urls.ztUI.appending(path: "healthz"), acceptStatuses: [200])
    }

    func stop() {
        for process in processes.reversed() {
            if process.isRunning {
                process.terminate()
            }
        }
        for pipe in logPipes {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        processes.removeAll()
        logPipes.removeAll()
        urls = nil
    }

    private func mlxPython() throws -> URL {
        let candidates = [
            resourcesURL.appendingPathComponent("mlx-venv/bin/python3"),
            resourcesURL.appendingPathComponent("mlx-venv/bin/python"),
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        throw StackLaunchError.missingExecutable("mlx-venv/bin/python", candidates[0])
    }

    private func startZtUI(port: Int) throws {
        let executable = resourcesURL.appendingPathComponent("zt-ui-serve")
        try requireExecutable("zt-ui-serve", at: executable)

        var env = ProcessInfo.processInfo.environment
        env["ZT_UI_HOST"] = "127.0.0.1"
        env["ZT_UI_PORT"] = "\(port)"

        try launch(
            name: "zt-ui-serve",
            executable: executable,
            arguments: [],
            currentDirectory: resourcesURL,
            environment: env
        )
    }

    private func startMlx(port: Int, modelURL: URL) throws {
        let python = try mlxPython()
        try launch(
            name: "mlx_lm.server",
            executable: python,
            arguments: [
                "-m", "mlx_lm.server",
                "--model", modelURL.path,
                "--host", "127.0.0.1",
                "--port", "\(port)",
            ],
            currentDirectory: resourcesURL,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private func startBridge(port: Int, inferenceURL: URL, ztURL: URL) throws {
        let node = resourcesURL.appendingPathComponent("node/bin/node")
        try requireExecutable("node", at: node)

        let bridgeRoot = resourcesURL.appendingPathComponent("bridge", isDirectory: true)
        let server = bridgeRoot.appendingPathComponent("src/server.mjs")
        guard FileManager.default.fileExists(atPath: server.path) else {
            throw StackLaunchError.missingExecutable("bridge/src/server.mjs", server)
        }

        var env = ProcessInfo.processInfo.environment
        env["HOST"] = "127.0.0.1"
        env["PORT"] = "\(port)"
        env["LLAMA_URL"] = inferenceURL.absoluteString
        env["ZT_UI_URL"] = ztURL.absoluteString
        env["INFERENCE_BACKEND"] = "mlx"
        env["MODEL_NAME"] = mlxRepo

        try launch(
            name: "bridge",
            executable: node,
            arguments: [server.path],
            currentDirectory: bridgeRoot,
            environment: env
        )
    }

    private func launch(
        name: String,
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment

        let logPipe = Pipe()
        logPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            FileHandle.standardError.write(Data("[\(name)] ".utf8))
            FileHandle.standardError.write(data)
        }
        process.standardOutput = logPipe
        process.standardError = logPipe

        do {
            try process.run()
        } catch {
            throw StackLaunchError.failedToStart("\(name): \(error.localizedDescription)")
        }

        processes.append(process)
        logPipes.append(logPipe)
    }

    private func requireExecutable(_ name: String, at url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw StackLaunchError.missingExecutable(name, url)
        }
    }

    private func ensureProcessesAlive() throws {
        for process in processes {
            if !process.isRunning {
                let name = process.executableURL?.lastPathComponent ?? "process"
                throw StackLaunchError.terminated(name, process.terminationStatus)
            }
        }
    }

    private func waitHealthy(name: String, url: URL, acceptStatuses: Set<Int>) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + readinessTimeoutNanos
        while DispatchTime.now().uptimeNanoseconds < deadline {
            try ensureProcessesAlive()
            if await isHealthy(url: url, acceptStatuses: acceptStatuses) {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        throw StackLaunchError.readinessTimeout(name, url)
    }

    private func isHealthy(url: URL, acceptStatuses: Set<Int>) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return acceptStatuses.contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func allocateLoopbackPort() throws -> Int {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw StackLaunchError.unavailablePort
        }
        defer { close(fileDescriptor) }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = in_port_t(0).bigEndian
        socketAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                bind(fileDescriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bindResult == 0 else {
            throw StackLaunchError.unavailablePort
        }

        var assignedAddress = sockaddr_in()
        var assignedLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let nameResult = withUnsafeMutablePointer(to: &assignedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(fileDescriptor, reboundPointer, &assignedLength)
            }
        }
        guard nameResult == 0 else {
            throw StackLaunchError.unavailablePort
        }

        return Int(UInt16(bigEndian: assignedAddress.sin_port))
    }
}
