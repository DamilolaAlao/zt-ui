import Foundation
import Darwin

enum ServerLaunchError: LocalizedError {
    case missingResources(URL)
    case missingExecutable(URL)
    case unavailablePort
    case failedToStart(String)
    case terminated(Int32)
    case readinessTimeout(URL)

    var errorDescription: String? {
        switch self {
        case .missingResources(let url):
            return "The app bundle is missing its Resources directory at \(url.path)."
        case .missingExecutable(let url):
            return "The bundled zt-ui server is missing or not executable at \(url.path)."
        case .unavailablePort:
            return "Unable to allocate a local loopback port for the embedded server."
        case .failedToStart(let message):
            return "The embedded zt-ui server failed to start. \(message)"
        case .terminated(let status):
            return "The embedded zt-ui server exited early with status \(status)."
        case .readinessTimeout(let url):
            return "The embedded zt-ui server did not become healthy in time at \(url.absoluteString)."
        }
    }
}

final class ServerController {
    private let resourcesURL: URL
    private let executableURL: URL
    private let healthCheckTimeoutNanos: UInt64 = 10_000_000_000

    private var process: Process?
    private var logPipe: Pipe?
    private var stageURL: URL?

    init(bundle: Bundle = .main) throws {
        guard let resourcesURL = bundle.resourceURL else {
            throw ServerLaunchError.missingResources(bundle.bundleURL)
        }

        let executableURL = resourcesURL.appendingPathComponent("zt-ui-serve")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ServerLaunchError.missingExecutable(executableURL)
        }

        self.resourcesURL = resourcesURL
        self.executableURL = executableURL
    }

    func start() throws -> URL {
        if let stageURL {
            return stageURL
        }

        let port = try Self.allocateLoopbackPort()
        let stageURL = URL(string: "http://127.0.0.1:\(port)")!

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = resourcesURL

        var environment = ProcessInfo.processInfo.environment
        environment["ZT_UI_HOST"] = "127.0.0.1"
        environment["ZT_UI_PORT"] = "\(port)"
        process.environment = environment

        let logPipe = Pipe()
        logPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            FileHandle.standardError.write(data)
        }

        process.standardOutput = logPipe
        process.standardError = logPipe

        do {
            try process.run()
        } catch {
            throw ServerLaunchError.failedToStart(error.localizedDescription)
        }

        self.process = process
        self.logPipe = logPipe
        self.stageURL = stageURL
        return stageURL
    }

    func waitUntilReady() async throws {
        guard let stageURL else {
            throw ServerLaunchError.failedToStart("The stage URL was not initialized.")
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + healthCheckTimeoutNanos
        let healthURL = stageURL.appending(path: "healthz")

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let process, !process.isRunning {
                throw ServerLaunchError.terminated(process.terminationStatus)
            }

            if await isHealthy(url: healthURL) {
                return
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        throw ServerLaunchError.readinessTimeout(stageURL)
    }

    func stop() {
        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()
        }

        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe = nil
        self.process = nil
        stageURL = nil
    }

    private func isHealthy(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    private static func allocateLoopbackPort() throws -> Int {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw ServerLaunchError.unavailablePort
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
            throw ServerLaunchError.unavailablePort
        }

        var assignedAddress = sockaddr_in()
        var assignedLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let nameResult = withUnsafeMutablePointer(to: &assignedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(fileDescriptor, reboundPointer, &assignedLength)
            }
        }
        guard nameResult == 0 else {
            throw ServerLaunchError.unavailablePort
        }

        return Int(UInt16(bigEndian: assignedAddress.sin_port))
    }
}
