//
//  MetricsWebsocketServer.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import Network

/// Broadcasts pre-encoded JSON text frames to all connected WebSocket clients.
///
/// - Binds to 127.0.0.1 only, so nothing on the LAN can connect.
/// - Rejects browser connections whose Origin header is not in `allowedOrigins`.
///   Clients that send no Origin header (Java, websocat, curl) are accepted.
/// - A new client immediately receives the latest snapshot, then one per tick.
/// - A client that cannot keep up simply misses snapshots instead of building a backlog.
///
/// All mutable state is confined to `queue`, hence @unchecked Sendable.
/// The class is `nonisolated` so it is not pulled onto the main actor when the
/// project uses "Default Actor Isolation = MainActor".
nonisolated final class MetricsWebSocketServer: @unchecked Sendable {
    /// Only ever touched on `queue` (all NWConnection callbacks run there), so it is safe
    /// to declare @unchecked Sendable. That silences the capture warning in the
    /// @Sendable completion handlers without changing behaviour.
    private final class Client: @unchecked Sendable {
        let connection : NWConnection
        var isSending  : Bool = false

        
        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private let port           : NWEndpoint.Port
    private let allowedOrigins : Set<String>
    private let queue = DispatchQueue(label: "SystemMonitor.WebSocketServer")

    // Confined to `queue`.
    private var listener : NWListener?
    private var clients  : [ObjectIdentifier: Client] = [:]
    private var latest   : Data?

    
    init(port: UInt16 = 8787, allowedOrigins: Set<String> = []) {
        self.port           = NWEndpoint.Port(rawValue: port) ?? 8787
        self.allowedOrigins = allowedOrigins
    }

    
    func start() {
        queue.async { [self] in
            guard listener == nil else { return }

            let webSocketOptions = NWProtocolWebSocket.Options()
            webSocketOptions.autoReplyPing = true

            let allowed = allowedOrigins
            webSocketOptions.setClientRequestHandler(queue) { _, headers in
                let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value
                if let origin, !allowed.contains(origin) {
                    print("WebSocket: rejected connection with Origin \(origin)")
                    return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil)
                }
                return NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
            }

            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)

            do {
                let newListener = try NWListener(using: parameters)
                newListener.stateUpdateHandler = { state in
                    print("WebSocket listener: \(state)")
                }
                newListener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                newListener.start(queue: queue)
                listener = newListener
            } catch {
                print("WebSocket listener could not be created: \(error)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            for client in clients.values { client.connection.cancel() }
            clients.removeAll()
        }
    }

    // Sends one JSON document (UTF-8) as a text frame to every connected client.
    func broadcast(_ json: Data) {
        queue.async { [self] in
            latest = json
            for client in clients.values {
                send(json, to: client)
            }
        }
    }

    // MARK: - Connection handling (always on `queue`)

    private func accept(_ connection: NWConnection) {
        let client = Client(connection)
        let id     = ObjectIdentifier(client)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                clients[id] = client
                print("WebSocket: client connected (\(clients.count) total)")
                if let latest { send(latest, to: client) }
                receiveLoop(client)
            case .failed:
                connection.cancel()
            case .cancelled:
                if clients.removeValue(forKey: id) != nil {
                    print("WebSocket: client disconnected (\(clients.count) total)")
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // Clients are not expected to send anything, but reading keeps control frames
    // (close, ping) flowing and tells us when the client goes away.
    private func receiveLoop(_ client: Client) {
        client.connection.receiveMessage { [weak self] _, context, _, error in
            guard let self else { return }
            if error != nil {
                client.connection.cancel()
                return
            }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                client.connection.cancel()
                return
            }
            receiveLoop(client)
        }
    }

    private func send(_ data: Data, to client: Client) {
        // Slow consumer: drop this snapshot rather than queueing up a backlog.
        guard !client.isSending else { return }
        client.isSending = true

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context  = NWConnection.ContentContext(identifier: "snapshot", metadata: [metadata])
        client.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                client.isSending = false
                if error != nil { client.connection.cancel() }
            }
        )
    }
}
