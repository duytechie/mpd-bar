import Darwin
import Foundation

public struct MPDConfiguration: Sendable, Equatable {
    public var host: String
    public var port: UInt16
    public var password: String?

    public init(host: String, port: UInt16 = 6600, password: String? = nil) {
        self.host = host
        self.port = port
        self.password = password
    }
}

public enum MPDClientError: LocalizedError, Sendable {
    case resolutionFailed(String)
    case connectionFailed(String, UInt16)
    case invalidGreeting
    case disconnected
    case server(String)
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .resolutionFailed(let host):
            "Could not resolve \(host)"
        case .connectionFailed(let host, let port):
            "Could not connect to \(host):\(port)"
        case .invalidGreeting:
            "The server did not identify itself as MPD"
        case .disconnected:
            "The MPD server closed the connection"
        case .server(let message):
            message
        case .writeFailed:
            "Could not send a command to MPD"
        }
    }
}

public enum MPDCommand: Sendable {
    case play
    case pause
    case next
    case previous

    fileprivate var wireValue: String {
        switch self {
        case .play: "play"
        case .pause: "pause 1"
        case .next: "next"
        case .previous: "previous"
        }
    }
}

public enum MPDClient {
    public static func fetchStatus(configuration: MPDConfiguration) throws -> MPDSnapshot {
        var connection = try Connection(configuration: configuration)
        defer { connection.close() }

        try connection.authenticate(password: configuration.password)
        let status = try connection.request("status")
        let song = try connection.request("currentsong")
        return MPDResponseParser.snapshot(status: status, song: song)
    }

    public static func send(_ command: MPDCommand, configuration: MPDConfiguration) throws {
        var connection = try Connection(configuration: configuration)
        defer { connection.close() }

        try connection.authenticate(password: configuration.password)
        _ = try connection.request(command.wireValue)
    }
}

private struct Connection {
    private var descriptor: Int32
    private var reader: SocketLineReader

    init(configuration: MPDConfiguration) throws {
        descriptor = try Self.connect(host: configuration.host, port: configuration.port)
        reader = SocketLineReader(descriptor: descriptor)

        guard let greeting = try reader.readLine(), greeting.hasPrefix("OK MPD ") else {
            Darwin.close(descriptor)
            throw MPDClientError.invalidGreeting
        }
    }

    mutating func authenticate(password: String?) throws {
        guard let password, !password.isEmpty else { return }
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = try request("password \"\(escaped)\"")
    }

    mutating func request(_ command: String) throws -> [String: String] {
        try write(command + "\n")
        var lines: [String] = []

        while let line = try reader.readLine() {
            if line == "OK" {
                return MPDResponseParser.fields(from: lines)
            }
            if line.hasPrefix("ACK ") {
                throw MPDClientError.server(line)
            }
            lines.append(line)
        }

        throw MPDClientError.disconnected
    }

    mutating func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    private func write(_ string: String) throws {
        let bytes = Array(string.utf8)
        var sent = 0

        while sent < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.send(descriptor, buffer.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
            }
            guard written > 0 else { throw MPDClientError.writeFailed }
            sent += written
        }
    }

    private static func connect(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let resolution = getaddrinfo(host, String(port), &hints, &result)
        guard resolution == 0, let first = result else {
            throw MPDClientError.resolutionFailed(host)
        }
        defer { freeaddrinfo(first) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        while let address = current {
            let info = address.pointee
            let fd = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if fd >= 0 {
                var noSigPipe: Int32 = 1
                _ = setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    &noSigPipe,
                    socklen_t(MemoryLayout<Int32>.size)
                )
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                withUnsafePointer(to: &timeout) { pointer in
                    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
                    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
                }

                if Darwin.connect(fd, info.ai_addr, info.ai_addrlen) == 0 {
                    return fd
                }
                Darwin.close(fd)
            }
            current = info.ai_next
        }

        throw MPDClientError.connectionFailed(host, port)
    }
}

private struct SocketLineReader {
    let descriptor: Int32

    mutating func readLine() throws -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0

        while true {
            let count = Darwin.recv(descriptor, &byte, 1, 0)
            if count == 0 {
                return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw MPDClientError.disconnected
            }
            if byte == 10 {
                if bytes.last == 13 { bytes.removeLast() }
                return String(decoding: bytes, as: UTF8.self)
            }
            bytes.append(byte)
        }
    }
}
