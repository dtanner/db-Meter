import SwiftUI
import CoreAudio

struct DevicePicker: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        if audioManager.availableDevices.count > 1 {
            Picker("Input", selection: $audioManager.selectedDeviceID) {
                ForEach(audioManager.availableDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
