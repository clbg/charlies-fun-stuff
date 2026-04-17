import Foundation
import Network

// MARK: - Delegate protocol

/// Receives decoded, resampled audio from the RTP listener.
protocol RTPAudioDelegate: AnyObject, Sendable {
    /// Called when a buffer of resampled audio is ready.
    ///
    /// - Parameters:
    ///   - samples: 16 kHz float32 PCM samples in the range [-1, 1].
    ///   - sampleRate: Always 16000.
    func didReceiveAudio(samples: [Float], sampleRate: Int)
}

// MARK: - RTPListener

/// Receives RTP/UDP packets carrying μ-law audio, decodes them to PCM16,
/// resamples from 8 kHz to 16 kHz, and delivers float32 buffers to a delegate.
///
/// Uses `NWListener` from the Network framework (no external dependencies).
actor RTPListener {

    // MARK: - Configuration

    /// Minimum RTP packet size: 12-byte header + at least 1 payload byte.
    private static let rtpHeaderSize = 12

    /// Number of 16 kHz float32 samples to accumulate before delivering.
    /// 3200 samples = 200 ms at 16 kHz — a good chunk for speech recognition.
    private let bufferThreshold: Int

    // MARK: - State

    private let port: UInt16
    private var listener: NWListener?
    private var buffer: [Float] = []
    weak var delegate: RTPAudioDelegate?

    // MARK: - Init

    /// Creates an RTP listener.
    ///
    /// - Parameters:
    ///   - port: UDP port to bind (default 7078).
    ///   - bufferThreshold: Deliver audio after this many 16 kHz samples
    ///     (default 3200 = 200 ms).
    init(port: UInt16 = 7078, bufferThreshold: Int = 3200) {
        self.port = port
        self.bufferThreshold = bufferThreshold
    }

    // MARK: - Lifecycle

    /// Start listening for RTP packets on the configured UDP port.
    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let nwListener = try NWListener(using: params, on: nwPort)

        nwListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[RTPListener] Listening on UDP port \(self.port)")
            case .failed(let error):
                print("[RTPListener] Listener failed: \(error)")
            default:
                break
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    print("[RTPListener] New UDP connection ready")
                }
            }
            connection.start(queue: .global(qos: .userInteractive))
            Task { await self.receiveLoop(on: connection) }
        }

        nwListener.start(queue: .global(qos: .userInteractive))
        self.listener = nwListener
        print("[RTPListener] Starting on port \(port)...")
    }

    /// Stop the listener and release resources.
    func stop() {
        listener?.cancel()
        listener = nil
        buffer.removeAll()
        print("[RTPListener] Stopped")
    }

    // MARK: - Receive loop

    /// Continuously receive datagrams on a single NWConnection.
    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                Task { await self.handlePacket(data) }
            }

            if let error {
                print("[RTPListener] Receive error: \(error)")
                return
            }

            // Schedule next receive (must re-enter actor context).
            Task { await self.receiveLoop(on: connection) }
        }
    }

    // MARK: - Packet processing

    /// Process a single RTP packet: strip header, decode μ-law, resample,
    /// buffer, and deliver when the threshold is reached.
    private func handlePacket(_ data: Data) {
        guard data.count > Self.rtpHeaderSize else { return }

        // Strip the 12-byte RTP header; the rest is μ-law payload.
        let payload = Array(data[Self.rtpHeaderSize...])

        // Decode μ-law → PCM16
        let pcm16 = ULawCodec.decode(payload)

        // Resample 8 kHz → 16 kHz via linear interpolation, then
        // convert Int16 → Float32.
        let resampled = resample8to16(pcm16)

        buffer.append(contentsOf: resampled)

        // Deliver complete chunks.
        while buffer.count >= bufferThreshold {
            let chunk = Array(buffer.prefix(bufferThreshold))
            buffer.removeFirst(bufferThreshold)
            delegate?.didReceiveAudio(samples: chunk, sampleRate: 16_000)
        }
    }

    // MARK: - Resampling

    /// Resample 8 kHz Int16 samples to 16 kHz Float32 using linear
    /// interpolation. Each input sample produces two output samples:
    /// the original and a linearly interpolated midpoint.
    private func resample8to16(_ samples: [Int16]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        var output = [Float]()
        output.reserveCapacity(samples.count * 2)

        for i in 0 ..< samples.count {
            let current = Float(samples[i]) / 32768.0

            // Original sample.
            output.append(current)

            // Interpolated sample (midpoint to next, or duplicate last).
            if i + 1 < samples.count {
                let next = Float(samples[i + 1]) / 32768.0
                output.append((current + next) * 0.5)
            } else {
                // Last sample — just duplicate.
                output.append(current)
            }
        }

        return output
    }
}
