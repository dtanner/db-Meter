import AVFoundation
import Combine
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
class AudioManager: ObservableObject {
    @Published var currentDB: Float = -.infinity
    @Published var dbHistory: [Float] = []
    @Published var availableDevices: [AudioDevice] = []
    private let smoothingFactor: Float = 0.3
    private var historyTimer: Timer?
    private let maxHistoryEntries = 60
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
