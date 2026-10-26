import AVFoundation

/// Polyphonic additive synth rendered directly in the audio callback.
///
/// UI -> audio communication is lock-free: the UI thread writes a velocity and
/// bumps a per-note counter (odd = pressed, even = released); the audio thread
/// compares the counter with the last value it saw. No allocation, locks or
/// ARC traffic happens on the audio thread.
final class PianoSynth {
    static let firstNote = 21   // A0
    static let lastNote = 108   // C8

    private static let maxVoices = 16
    private static let harmonics = 6

    // UI -> audio state (indexed by MIDI note, 0..<128)
    private let gate: UnsafeMutablePointer<UInt32>
    private let velocity: UnsafeMutablePointer<Float>
    // Audio-thread-only state
    private let seen: UnsafeMutablePointer<UInt32>
    private let vNote: UnsafeMutablePointer<Int32>
    private let vState: UnsafeMutablePointer<UInt8>   // 0 free, 1 attack, 2 decay, 3 release
    private let vLevel: UnsafeMutablePointer<Float>
    private let vBright: UnsafeMutablePointer<Float>
    private let vPhase: UnsafeMutablePointer<Double>
    private let vInc: UnsafeMutablePointer<Double>
    private let vVel: UnsafeMutablePointer<Float>
    private let vDecay: UnsafeMutablePointer<Float>
    private let vBrightDecay: UnsafeMutablePointer<Float>

    private var sampleRate: Float = 48000
    private var attackStep: Float = 0.1
    private var releaseMul: Float = 0.999

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []
    private let setupQueue = DispatchQueue(label: "piano.synth.setup", qos: .userInteractive)

    init() {
        func alloc<T>(_ count: Int, _ value: T) -> UnsafeMutablePointer<T> {
            let p = UnsafeMutablePointer<T>.allocate(capacity: count)
            p.initialize(repeating: value, count: count)
            return p
        }
        let v = PianoSynth.maxVoices
        gate = alloc(128, 0)
        velocity = alloc(128, 0.8)
        seen = alloc(128, 0)
        vNote = alloc(v, -1)
        vState = alloc(v, 0)
        vLevel = alloc(v, 0)
        vBright = alloc(v, 0)
        vPhase = alloc(v, 0)
        vInc = alloc(v, 0)
        vVel = alloc(v, 0)
        vDecay = alloc(v, 1)
        vBrightDecay = alloc(v, 1)
    }

    // MARK: - UI thread API

    func noteOn(_ note: Int, velocity vel: Float) {
        guard note >= 0, note < 128 else { return }
        velocity[note] = vel
        if gate[note] & 1 == 0 { gate[note] = gate[note] &+ 1 }
    }

    func noteOff(_ note: Int) {
        guard note >= 0, note < 128 else { return }
        if gate[note] & 1 == 1 { gate[note] = gate[note] &+ 1 }
    }

    // MARK: - Engine lifecycle

    /// Configures the audio session and starts the engine off the main thread.
    func start() {
        setupQueue.async { [weak self] in self?.startOnQueue() }

        let nc = NotificationCenter.default
        let names: [(Notification.Name, AnyObject?)] = [
            (AVAudioSession.interruptionNotification, nil),
            (AVAudioSession.mediaServicesWereResetNotification, nil),
            (.AVAudioEngineConfigurationChange, engine),
        ]
        for (name, object) in names {
            observers.append(nc.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                self?.recover()
            })
        }
    }

    func recover() {
        setupQueue.async { [weak self] in self?.startOnQueue() }
    }

    private func startOnQueue() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            return
        }

        if !isConfigured {
            sampleRate = Float(session.sampleRate)
            attackStep = 1 / (0.003 * sampleRate)
            releaseMul = expf(-1 / (0.15 * sampleRate))

            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2) else { return }
            let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
                self.render(frameCount: Int(frameCount), bufferList: audioBufferList)
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
            isConfigured = true
        }

        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    // MARK: - Audio thread

    private func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let first = buffers.first, let raw = first.mData else { return }
        let out = raw.assumingMemoryBound(to: Float.self)

        processEvents()

        for i in 0..<frameCount { out[i] = 0 }
        for v in 0..<PianoSynth.maxVoices where vState[v] != 0 {
            renderVoice(v, into: out, frames: frameCount)
        }
        for i in 0..<frameCount { out[i] = tanhf(out[i] * 0.3) }

        var b = 1
        while b < buffers.count {
            if let dst = buffers[b].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<frameCount { dst[i] = out[i] }
            }
            b += 1
        }
    }

    private func processEvents() {
        for n in PianoSynth.firstNote...PianoSynth.lastNote {
            let g = gate[n]
            let s = seen[n]
            if g == s { continue }
            seen[n] = g
            let pressed = g & 1 == 1
            if pressed || g &- s >= 2 { startVoice(note: n) }
            if !pressed { releaseVoice(note: n) }
        }
    }

    private func startVoice(note n: Int) {
        var slot = -1
        for v in 0..<PianoSynth.maxVoices where vState[v] != 0 && Int(vNote[v]) == n {
            slot = v
            break
        }
        let reuse = slot >= 0
        if slot < 0 {
            for v in 0..<PianoSynth.maxVoices where vState[v] == 0 {
                slot = v
                break
            }
        }
        if slot < 0 {
            // Steal the quietest voice.
            var best = 0
            var bestLevel = Float.greatestFiniteMagnitude
            for v in 0..<PianoSynth.maxVoices where vLevel[v] < bestLevel {
                best = v
                bestLevel = vLevel[v]
            }
            slot = best
        }

        let t = Float(n - PianoSynth.firstNote) / Float(PianoSynth.lastNote - PianoSynth.firstNote)
        let tau = 6.0 - 4.5 * t
        let brightTau = 0.8 - 0.5 * t
        let freq = 440.0 * pow(2.0, Double(n - 69) / 12.0)

        vNote[slot] = Int32(n)
        vState[slot] = 1
        vInc[slot] = freq / Double(sampleRate)
        vVel[slot] = velocity[n]
        vDecay[slot] = expf(-1 / (tau * sampleRate))
        vBrightDecay[slot] = expf(-1 / (brightTau * sampleRate))
        vBright[slot] = 1
        if !reuse {
            vLevel[slot] = 0
            vPhase[slot] = 0
        }
    }

    private func releaseVoice(note n: Int) {
        for v in 0..<PianoSynth.maxVoices where vState[v] != 0 && vState[v] != 3 && Int(vNote[v]) == n {
            vState[v] = 3
        }
    }

    private func renderVoice(_ v: Int, into out: UnsafeMutablePointer<Float>, frames: Int) {
        var state = vState[v]
        var level = vLevel[v]
        var bright = vBright[v]
        var phase = vPhase[v]
        let inc = vInc[v]
        let vel = vVel[v]
        let decay = vDecay[v]
        let brightDecay = vBrightDecay[v]
        let atk = attackStep
        let rel = releaseMul
        let twoPi = Float.pi * 2

        for i in 0..<frames {
            switch state {
            case 1:
                level += atk
                if level >= 1 { level = 1; state = 2 }
            case 2:
                level *= decay
            default:
                level *= rel
            }
            if level < 0.0003 && state != 1 { state = 0; break }
            bright *= brightDecay

            let x = twoPi * Float(phase)
            let c2 = 2 * cosf(x)
            let s1 = sinf(x)
            let s2 = c2 * s1
            let s3 = c2 * s2 - s1
            let s4 = c2 * s3 - s2
            let s5 = c2 * s4 - s3
            let s6 = c2 * s5 - s4
            let upper = 0.5 * s2 + 0.3 * s3 + 0.18 * s4 + 0.1 * s5 + 0.06 * s6
            out[i] += (s1 + bright * upper) * level * vel

            phase += inc
            if phase >= 1 { phase -= 1 }
        }

        vState[v] = state
        vLevel[v] = level
        vBright[v] = bright
        vPhase[v] = phase
    }
}
