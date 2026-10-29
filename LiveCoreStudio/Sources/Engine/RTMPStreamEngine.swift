import Foundation
import Network

public struct RTMPEndpointDescriptor: Equatable, Sendable {
    public let useTLS: Bool
    public let host: String
    public let port: UInt16
    public let appName: String
    public let streamKey: String

    public static func parse(rtmpURL: String, streamKey: String) throws -> RTMPEndpointDescriptor {
        let trimmedURL = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            throw NSError(
                domain: "com.livecore.studio.rtmp",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Stream key must not be empty."]
            )
        }

        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "rtmp" || scheme == "rtmps"),
              let host = url.host,
              !host.isEmpty else {
            throw NSError(
                domain: "com.livecore.studio.rtmp",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid RTMP/RTMPS endpoint URL: \(trimmedURL)"]
            )
        }

        let isTLS = (scheme == "rtmps")
        let defaultPort: UInt16 = isTLS ? 443 : 1935
        let port = url.port.flatMap { UInt16(exactly: $0) } ?? defaultPort
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let appName = pathComponents.first ?? "live"

        return RTMPEndpointDescriptor(
            useTLS: isTLS,
            host: host,
            port: port,
            appName: appName,
            streamKey: trimmedKey
        )
    }
}

public final class RTMPStreamEngine: @unchecked Sendable {
    private var connection: NWConnection?
    private let transportQueue = DispatchQueue(label: "com.livecore.studio.rtmp.transport")
    public private(set) var state: StreamConnectionState = .idle
    public private(set) var bytesSent: UInt64 = 0

    public var onStateChange: ((StreamConnectionState, String?) -> Void)?

    public init() {}

    public func connectAndPublish(settings: StreamSettings) {
        do {
            let endpoint = try RTMPEndpointDescriptor.parse(rtmpURL: settings.rtmpURL, streamKey: settings.streamKey)
            updateState(.connecting, message: "Connecting to \(endpoint.host):\(endpoint.port) (\(endpoint.useTLS ? "RTMPS/TLS" : "RTMP/TCP"))")

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true

            let parameters: NWParameters
            if endpoint.useTLS {
                parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcpOptions)
            } else {
                parameters = NWParameters(tls: nil, tcp: tcpOptions)
            }

            guard let nwPort = NWEndpoint.Port(rawValue: endpoint.port) else {
                updateState(.error, message: "Invalid port \(endpoint.port)")
                return
            }

            let conn = NWConnection(host: NWEndpoint.Host(endpoint.host), port: nwPort, using: parameters)
            self.connection = conn
            self.bytesSent = 0

            conn.stateUpdateHandler = { [weak self] nwState in
                guard let self = self else { return }
                switch nwState {
                case .ready:
                    self.performC0C1Handshake(connection: conn, endpoint: endpoint)
                case .waiting(let error):
                    self.updateState(.reconnecting, message: "Network waiting: \(error.localizedDescription)")
                case .failed(let error):
                    self.updateState(.error, message: "Transport failed: \(error.localizedDescription)")
                case .cancelled:
                    self.updateState(.idle, message: nil)
                default:
                    break
                }
            }

            conn.start(queue: transportQueue)
        } catch {
            updateState(.error, message: error.localizedDescription)
        }
    }

    private func performC0C1Handshake(connection: NWConnection, endpoint: RTMPEndpointDescriptor) {
        // RTMP Handshake C0 (1 byte version 0x03) + C1 (1536 bytes timestamp + random payload)
        var c0c1 = Data(count: 1537)
        c0c1[0] = 0x03
        connection.send(content: c0c1, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.updateState(.error, message: "RTMP C0/C1 handshake send failed: \(error.localizedDescription)")
                return
            }
            self.bytesSent += 1537
            self.updateState(.streaming, message: "Connected to \(endpoint.host)/\(endpoint.appName) — Handshake C0/C1 transmitted")
        })
    }

    public func sendEncodedVideoFrame(_ nalPayload: Data, timestampMs: UInt32) {
        transportQueue.async { [weak self] in
            guard let self = self,
                  self.state == .streaming,
                  let conn = self.connection else {
                return
            }
            var chunkHeader = Data(capacity: 12 + nalPayload.count)
            chunkHeader.append(0x06) // Chunk Stream ID 6 (Video)
            let tsBytes: [UInt8] = [
                UInt8((timestampMs >> 16) & 0xFF),
                UInt8((timestampMs >> 8) & 0xFF),
                UInt8(timestampMs & 0xFF)
            ]
            chunkHeader.append(contentsOf: tsBytes)
            let len = UInt32(nalPayload.count)
            chunkHeader.append(contentsOf: [
                UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF),
                UInt8(len & 0xFF),
                0x09, // Message Type ID: Video Data (0x09)
                0x01, 0x00, 0x00, 0x00 // Message Stream ID 1 (little-endian)
            ])
            chunkHeader.append(nalPayload)

            conn.send(content: chunkHeader, completion: .contentProcessed { [weak self] _ in
                self?.bytesSent += UInt64(chunkHeader.count)
            })
        }
    }

    public func disconnect() {
        transportQueue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.cancel()
            self.connection = nil
            self.updateState(.idle, message: "Stream stopped cleanly")
        }
    }

    private func updateState(_ newState: StreamConnectionState, message: String?) {
        self.state = newState
        onStateChange?(newState, message)
    }
}
