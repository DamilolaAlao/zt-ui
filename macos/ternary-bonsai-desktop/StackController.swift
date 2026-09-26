import Foundation
import Darwin

enum StackLaunchError: LocalizedError {
    case missingResources(URL)
    case missingExecutable(String, URL)
    case unavailablePort
    case failedToStart(String)
    case terminated(String, Int32)
    case readinessTimeout(String, URL)
    case missingModel(URL)

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
        case .missingModel(let url):
            return "The bundled MLX model is missing at \(url.path)."
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
    /// MLX bf16 export of https://huggingface.co/LiquidAI/LFM2.5-2.6B
    private let modelRepo = "LiquidAI/LFM2.5-2.6B"
    private let modelDirName = "LFM2.5-2.6B-MLX-bf16"

    private var processes: [Process] = []
    private var logPipes: [Pipe] = []
    private var urls: StackURLs?
    private let readinessTimeoutNanos: UInt64 = 600_000_000_000

    var stackURLs: StackURLs? { urls }

    init(bundle: Bundle = .main) throws {
        guard let resourcesURL = bundle.resourceURL else {
            throw StackLaunchError.missingResources(bundle.bundleURL)
        }
        self.resourcesURL = resourcesURL
    }

    /// MLX weights shipped inside the app bundle by the macOS build.
    func bundledModelURL() throws -> URL {
        let modelURL = resourcesURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(modelDirName, isDirectory: true)
        let index = modelURL.appendingPathComponent("model.safetensors.index.json")
        let single = modelURL.appendingPathComponent("model.safetensors")
        if FileManager.default.fileExists(atPath: index.path) || FileManager.default.fileExists(atPath: single.path) {
            return modelURL
        }
        throw StackLaunchError.missingModel(modelURL)
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

        progress("Starting LFM2.5-2.6B (MLX)…")
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
        env["MODEL_NAME"] = modelRepo
        env["MODEL_FAMILY"] = "lfm"

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
