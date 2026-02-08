import AVFoundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
class AudioManager: ObservableObject {
    @Published var currentDB: Float = -.infinity
    @Published var availableDevices: [AudioDevice] = []
    private let smoothingFactor: Float = 0.3
    @Published var selectedDeviceID: AudioDeviceID? {
        didSet {
            if oldValue != selectedDeviceID {
                restartCapture()
            }
        }
    }

    private var audioEngine = AVAudioEngine()
    private var isRunning = false

    init() {
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
            setAudioEngineInputDevice(deviceID)
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let db = self?.calculateDB(buffer: buffer) ?? -.infinity
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.currentDB.isFinite {
                    self.currentDB = self.currentDB + self.smoothingFactor * (db - self.currentDB)
                } else {
                    self.currentDB = db
                }
            }
        }

        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopCapture() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }

    private func restartCapture() {
        stopCapture()
        audioEngine = AVAudioEngine()
        startCapture()
    }

    private func setAudioEngineInputDevice(_ deviceID: AudioDeviceID) {
        let inputNode = audioEngine.inputNode
        let audioUnit = inputNode.audioUnit!

        var id = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    // MARK: - dB Calculation

    private func calculateDB(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -.infinity }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -.infinity }

        var sumOfSquares: Float = 0

        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sumOfSquares += sample * sample
            }
        }

        let rms = sqrt(sumOfSquares / Float(frameLength * channelCount))

        // Convert to dB (reference: 1.0 = 0 dBFS)
        let db = 20 * log10(rms)

        // Clamp to a reasonable range
        return max(db, -96)
    }
}
