import AVFoundation
import Combine
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

// MARK: - A-Weighting Filter

/// A-weighting filter per IEC 61672, implemented as cascaded biquad sections.
/// The analog A-weighting transfer function:
///   H(s) = K_A * s^4 / ((s+ω1)² * (s+ω2) * (s+ω3) * (s+ω4)²)
/// is decomposed into 3 second-order sections and digitized via bilinear transform.
class AWeightingFilter {
    private var sections: [BiquadState]
    private var gain: Double

    struct BiquadState {
        let b0, b1, b2, a1, a2: Double
        var w1: Double = 0  // transposed direct form II state
        var w2: Double = 0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + w1
            w1 = b1 * x - a1 * y + w2
            w2 = b2 * x - a2 * y
            return y
        }
    }

    init(sampleRate: Double) {
        let f1 = 20.598997
        let f2 = 107.65265
        let f3 = 737.86223
        let f4 = 12194.217

        let w1 = 2.0 * .pi * f1
        let w2 = 2.0 * .pi * f2
        let w3 = 2.0 * .pi * f3
        let w4 = 2.0 * .pi * f4

        let c = 2.0 * sampleRate  // bilinear transform constant

        // Section 1: H1(s) = s² / (s + ω1)²
        let s1a0 = c * c + 2.0 * w1 * c + w1 * w1
        let s1 = BiquadState(
            b0: c * c / s1a0,
            b1: -2.0 * c * c / s1a0,
            b2: c * c / s1a0,
            a1: (-2.0 * c * c + 2.0 * w1 * w1) / s1a0,
            a2: (c * c - 2.0 * w1 * c + w1 * w1) / s1a0
        )

        // Section 2: H2(s) = s² / ((s + ω2)(s + ω3))
        let alpha = w2 + w3
        let beta = w2 * w3
        let s2a0 = c * c + alpha * c + beta
        let s2 = BiquadState(
            b0: c * c / s2a0,
            b1: -2.0 * c * c / s2a0,
            b2: c * c / s2a0,
            a1: (-2.0 * c * c + 2.0 * beta) / s2a0,
            a2: (c * c - alpha * c + beta) / s2a0
        )

        // Section 3: H3(s) = 1 / (s + ω4)²
        let s3a0 = c * c + 2.0 * w4 * c + w4 * w4
        let s3 = BiquadState(
            b0: 1.0 / s3a0,
            b1: 2.0 / s3a0,
            b2: 1.0 / s3a0,
            a1: (-2.0 * c * c + 2.0 * w4 * w4) / s3a0,
            a2: (c * c - 2.0 * w4 * c + w4 * w4) / s3a0
        )

        sections = [s1, s2, s3]

        // Compute gain normalization so that response at 1 kHz = 0 dB
        let omega = 2.0 * .pi * 1000.0 / sampleRate
        var totalGain = 1.0
        for section in sections {
            let cosW = cos(omega)
            let cos2W = cos(2.0 * omega)
            let sinW = sin(omega)
            let sin2W = sin(2.0 * omega)

            let numReal = section.b0 + section.b1 * cosW + section.b2 * cos2W
            let numImag = -(section.b1 * sinW + section.b2 * sin2W)
            let denReal = 1.0 + section.a1 * cosW + section.a2 * cos2W
            let denImag = -(section.a1 * sinW + section.a2 * sin2W)

            let numMag = sqrt(numReal * numReal + numImag * numImag)
            let denMag = sqrt(denReal * denReal + denImag * denImag)
            totalGain *= numMag / denMag
        }

        gain = 1.0 / totalGain
    }

    func reset() {
        for i in sections.indices {
            sections[i].w1 = 0
            sections[i].w2 = 0
        }
    }

    func process(_ input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count {
            var sample = Double(input[i]) * gain
            for s in sections.indices {
                sample = sections[s].process(sample)
            }
            output[i] = Float(sample)
        }
    }
}

@MainActor
class AudioManager: ObservableObject {
    @Published var currentDB: Float = -.infinity
    @Published var dbHistory: [Float] = []
    @Published var availableDevices: [AudioDevice] = []
    private let smoothingFactor: Float = 0.3
    private var historyTimer: Timer?
    private let maxHistoryEntries = 60

    static let defaultCalibrationOffset: Float = 100
    private static let calibrationKey = "calibrationOffset"

    @Published var calibrationOffset: Float {
        didSet {
            UserDefaults.standard.set(calibrationOffset, forKey: Self.calibrationKey)
        }
    }

    @Published var selectedDeviceID: AudioDeviceID? {
        didSet {
            if oldValue != selectedDeviceID {
                restartCapture()
            }
        }
    }

    private var audioEngine = AVAudioEngine()
    private var isRunning = false
    private var aWeightingFilter: AWeightingFilter?

    init() {
        if UserDefaults.standard.object(forKey: Self.calibrationKey) != nil {
            calibrationOffset = UserDefaults.standard.float(forKey: Self.calibrationKey)
        } else {
            calibrationOffset = Self.defaultCalibrationOffset
        }
        loadAvailableDevices()
        selectedDeviceID = defaultInputDeviceID()
        startCapture()
    }

    deinit {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    // MARK: - Device Enumeration

    func loadAvailableDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        availableDevices = deviceIDs.compactMap { deviceID -> AudioDevice? in
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var bufferListSize: UInt32 = 0
            let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &bufferListSize)
            guard sizeStatus == noErr, bufferListSize > 0 else { return nil }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }

            AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &bufferListSize, bufferListPointer)

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { return nil }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

            return AudioDevice(id: deviceID, name: name as String)
        }
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    // MARK: - Audio Capture

    func startCapture() {
        guard !isRunning else { return }

        if let deviceID = selectedDeviceID {
            if !setAudioEngineInputDevice(deviceID) {
                print("Failed to set input device \(deviceID), falling back to default")
                if let fallback = defaultInputDeviceID(), fallback != deviceID {
                    if !setAudioEngineInputDevice(fallback) {
                        print("Failed to set fallback device, cannot capture audio")
                        return
                    }
                    selectedDeviceID = fallback
                } else {
                    return
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Invalid audio format (sampleRate=\(format.sampleRate), channels=\(format.channelCount))")
            return
        }

        aWeightingFilter = AWeightingFilter(sampleRate: format.sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let dbFS = self?.calculateDBA(buffer: buffer) ?? -.infinity
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dbSPL = dbFS + self.calibrationOffset
                if self.currentDB.isFinite {
                    self.currentDB = self.currentDB + self.smoothingFactor * (dbSPL - self.currentDB)
                } else {
                    self.currentDB = dbSPL
                }
            }
        }

        do {
            try audioEngine.start()
            isRunning = true
            startHistoryTimer()
        } catch {
            print("Failed to start audio engine: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopCapture() {
        guard isRunning else { return }
        stopHistoryTimer()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }

    private func restartCapture() {
        stopCapture()
        audioEngine.reset()
        aWeightingFilter?.reset()
        currentDB = -.infinity
        startCapture()
    }

    @discardableResult
    private func setAudioEngineInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            print("No audio unit available on input node")
            return false
        }

        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            print("AudioUnitSetProperty failed with status \(status) for device \(deviceID)")
            return false
        }
        return true
    }

    // MARK: - History Timer

    private func startHistoryTimer() {
        historyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dbHistory.append(self.currentDB)
                if self.dbHistory.count > self.maxHistoryEntries {
                    self.dbHistory.removeFirst(self.dbHistory.count - self.maxHistoryEntries)
                }
            }
        }
    }

    private func stopHistoryTimer() {
        historyTimer?.invalidate()
        historyTimer = nil
    }

    // MARK: - dB(A) Calculation

    private func calculateDBA(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -.infinity }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -.infinity }

        var sumOfSquares: Float = 0
        let filtered = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
        defer { filtered.deallocate() }

        for channel in 0..<channelCount {
            let data = channelData[channel]
            aWeightingFilter?.process(data, output: filtered, count: frameLength)

            for frame in 0..<frameLength {
                let sample = filtered[frame]
                sumOfSquares += sample * sample
            }
        }

        let rms = sqrt(sumOfSquares / Float(frameLength * channelCount))

        // Convert to dB(A) (reference: 1.0 = 0 dBFS)
        let db = 20 * log10(rms)

        // Clamp to a reasonable range
        return max(db, -96)
    }
}
