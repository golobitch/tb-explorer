import CTigerBeetle
import Foundation
import Synchronization

public enum TBError: Error, Equatable, LocalizedError, Sendable {
    case invalidClusterID(String)
    case invalidAddress
    case initFailed(String)
    case timeout(Duration)
    case clientClosed
    case evicted
    /// `clientTooOld` is true when the server rejected this client's release as too low.
    case versionMismatch(client: String, clientTooOld: Bool)
    case tooMuchData
    case notFound(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidClusterID(let s): "Invalid cluster id “\(s)”."
        case .invalidAddress: "Invalid replica address."
        case .initFailed(let s): "Could not create client: \(s)."
        case .timeout(let d): "Request timed out after \(d.formatted()). Is the cluster reachable?"
        case .clientClosed: "The client was closed."
        case .evicted: "The client was evicted by the cluster."
        case .versionMismatch(let client, let tooOld):
            tooOld
                ? "Client \(client) is older than the server supports."
                : "Client \(client) is newer than the server release."
        case .tooMuchData: "Too much data was requested in one batch."
        case .notFound(let s): "\(s) not found."
        case .unexpected(let s): s
        }
    }
}

/// Read-only operations the explorer may issue. `create_*` is deliberately absent.
enum ReadOperation: UInt8 {
    case lookupAccounts = 140
    case lookupTransfers = 141
    case getAccountTransfers = 142
    case getAccountBalances = 143
    case queryAccounts = 144
    case queryTransfers = 145

    init?(_ op: TB_OPERATION) { self.init(rawValue: UInt8(op.rawValue)) }
}

/// Thin async wrapper over `tb_client`. Thread-safe; completions arrive on the client's own thread.
public final class TBClient: Sendable {
    /// Release of the vendored `tb_client` library. Keep in sync with `Vendor/tigerbeetle/VERSION`.
    public static let clientVersion = "0.17.9"

    public static let defaultTimeout: Duration = .seconds(30)

    public let clusterID: UInt128
    public let addresses: [String]

    nonisolated(unsafe) private let handle: UnsafeMutablePointer<tb_client_t>
    private let closed = Mutex(false)

    public init(clusterID: UInt128, addresses: [String]) throws(TBError) {
        let joined = addresses.joined(separator: ",")
        guard !joined.isEmpty else { throw .invalidAddress }
        self.clusterID = clusterID
        self.addresses = addresses
        handle = .allocate(capacity: 1)
        handle.initialize(to: tb_client_t())

        var cluster = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: clusterID.littleEndian) { cluster.replaceSubrange(0..<16, with: $0) }

        let status = joined.withCString { ptr in
            tb_client_init(handle, cluster, ptr, UInt32(joined.utf8.count), 0, onCompletion)
        }
        guard status == TB_INIT_SUCCESS else {
            handle.deallocate()
            switch status {
            case TB_INIT_ADDRESS_INVALID: throw .invalidAddress
            case TB_INIT_ADDRESS_LIMIT_EXCEEDED: throw .initFailed("too many addresses")
            case TB_INIT_OUT_OF_MEMORY: throw .initFailed("out of memory")
            case TB_INIT_SYSTEM_RESOURCES: throw .initFailed("out of system resources")
            case TB_INIT_NETWORK_SUBSYSTEM: throw .initFailed("network subsystem error")
            default: throw .initFailed("unexpected init status \(status.rawValue)")
            }
        }
    }

    /// Completes all in-flight requests with `clientClosed` and frees the client.
    public func close() {
        let shouldClose = closed.withLock { c in
            defer { c = true }
            return !c
        }
        guard shouldClose else { return }
        _ = tb_client_deinit(handle)
    }

    deinit {
        close()
        handle.deallocate()
    }

    /// Submits one request. The TB client retries unreachable replicas forever, so every
    /// request races a timeout. A timed-out packet stays owned by its `Request` until the
    /// client completes it (at the latest on `close()`).
    func submit(_ op: ReadOperation, payload: [UInt8], timeout: Duration = defaultTimeout) async throws(TBError) -> [UInt8] {
        if closed.withLock({ $0 }) { throw .clientClosed }
        let request = Request(operation: op.rawValue, payload: payload)
        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
                request.arm(cont)
                let opaque = Unmanaged.passRetained(request).toOpaque()
                request.packet.pointee.user_data = opaque
                if tb_client_submit(handle, request.packet) != TB_CLIENT_OK {
                    Unmanaged<Request>.fromOpaque(opaque).release()
                    request.finish(.failure(TBError.clientClosed))
                    return
                }
                Task.detached {
                    try? await Task.sleep(for: timeout)
                    request.finish(.failure(TBError.timeout(timeout)))
                }
            }
        } catch let e as TBError {
            throw e
        } catch {
            throw .unexpected(error.localizedDescription)
        }
    }
}

/// Owns a pinned packet and its event buffer for the lifetime of one submission.
private final class Request: Sendable {
    nonisolated(unsafe) let packet: UnsafeMutablePointer<tb_packet_t>
    nonisolated(unsafe) private let data: UnsafeMutableRawPointer?
    private let continuation = Mutex<CheckedContinuation<[UInt8], Error>?>(nil)

    init(operation: UInt8, payload: [UInt8]) {
        packet = .allocate(capacity: 1)
        packet.initialize(to: tb_packet_t())
        if payload.isEmpty {
            data = nil
        } else {
            let buf = UnsafeMutableRawPointer.allocate(byteCount: payload.count, alignment: 16)
            payload.withUnsafeBytes { buf.copyMemory(from: $0.baseAddress!, byteCount: payload.count) }
            data = buf
        }
        packet.pointee.data = data
        packet.pointee.data_size = UInt32(payload.count)
        packet.pointee.operation = operation
    }

    deinit {
        packet.deinitialize(count: 1)
        packet.deallocate()
        data?.deallocate()
    }

    func arm(_ cont: CheckedContinuation<[UInt8], Error>) {
        continuation.withLock { $0 = cont }
    }

    /// Resumes the waiting task at most once.
    func finish(_ result: Result<[UInt8], Error>) {
        let cont = continuation.withLock { c -> CheckedContinuation<[UInt8], Error>? in
            defer { c = nil }
            return c
        }
        cont?.resume(with: result)
    }
}

/// `tb_completion_t`: runs on the tb_client thread. `result` is only valid during the call.
private let onCompletion: tb_completion_t = { _, packet, _, result, size in
    guard let packet, let opaque = packet.pointee.user_data else { return }
    let request = Unmanaged<Request>.fromOpaque(opaque).takeRetainedValue()
    let status = TB_PACKET_STATUS(UInt32(packet.pointee.status))
    switch status {
    case TB_PACKET_OK:
        let bytes = (result != nil && size > 0) ? Array(UnsafeBufferPointer(start: result, count: Int(size))) : []
        request.finish(.success(bytes))
    case TB_PACKET_TOO_MUCH_DATA: request.finish(.failure(TBError.tooMuchData))
    case TB_PACKET_CLIENT_EVICTED: request.finish(.failure(TBError.evicted))
    case TB_PACKET_CLIENT_RELEASE_TOO_LOW:
        request.finish(.failure(TBError.versionMismatch(client: TBClient.clientVersion, clientTooOld: true)))
    case TB_PACKET_CLIENT_RELEASE_TOO_HIGH:
        request.finish(.failure(TBError.versionMismatch(client: TBClient.clientVersion, clientTooOld: false)))
    case TB_PACKET_CLIENT_SHUTDOWN: request.finish(.failure(TBError.clientClosed))
    default: request.finish(.failure(TBError.unexpected("packet status \(status.rawValue)")))
    }
}
