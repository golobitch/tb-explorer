import CTigerBeetle
import Foundation

/// Minimal synchronous tb_client for seeding. Lives outside main.swift so the C completion
/// callback is nonisolated; top-level code in main.swift is main-actor isolated in Swift 6,
/// and a callback inferred as main-actor would trap when invoked on the tb_client thread.
final class SeedClient {
    private let handle: UnsafeMutablePointer<tb_client_t>

    init(addresses: String) {
        handle = .allocate(capacity: 1)
        handle.initialize(to: tb_client_t())
        let cluster = [UInt8](repeating: 0, count: 16)
        let status = addresses.withCString {
            tb_client_init(handle, cluster, $0, UInt32(addresses.utf8.count), 0, seedCompletion)
        }
        guard status == TB_INIT_SUCCESS else { fatalError("tb_client_init: status \(status.rawValue)") }
    }

    func submit(_ op: TB_OPERATION, _ events: [UInt8]) -> [UInt8] {
        let completion = Completion()
        let data = UnsafeMutableRawPointer.allocate(byteCount: max(events.count, 1), alignment: 16)
        defer { data.deallocate() }
        events.withUnsafeBytes { if let base = $0.baseAddress { data.copyMemory(from: base, byteCount: events.count) } }
        let packet = UnsafeMutablePointer<tb_packet_t>.allocate(capacity: 1)
        defer { packet.deallocate() }
        packet.initialize(to: tb_packet_t())
        packet.pointee.user_data = Unmanaged.passUnretained(completion).toOpaque()
        packet.pointee.data = data
        packet.pointee.data_size = UInt32(events.count)
        packet.pointee.operation = UInt8(op.rawValue)
        precondition(tb_client_submit(handle, packet) == TB_CLIENT_OK, "tb_client_submit failed")
        completion.done.wait()
        guard completion.status == 0 else { fatalError("packet status \(completion.status)") }
        return completion.bytes
    }

    func close() {
        _ = tb_client_deinit(handle)
    }
}

private final class Completion: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var status: UInt8 = 0
    var bytes: [UInt8] = []
}

private let seedCompletion: tb_completion_t = { _, packet, _, result, size in
    guard let packet, let opaque = packet.pointee.user_data else { return }
    let c = Unmanaged<Completion>.fromOpaque(opaque).takeUnretainedValue()
    c.status = packet.pointee.status
    if let result, size > 0 { c.bytes = Array(UnsafeBufferPointer(start: result, count: Int(size))) }
    c.done.signal()
}
