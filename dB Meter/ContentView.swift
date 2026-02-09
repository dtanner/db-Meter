import SwiftUI

enum MeterTab: String, CaseIterable {
    case meter = "Meter"
    case history = "History"
}

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var selectedTab: MeterTab = .meter

    var body: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $selectedTab) {
                ForEach(MeterTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedTab {
            case .meter:
                meterView
            case .history:
                HistoryChartView(audioManager: audioManager)
            }

            DevicePicker(audioManager: audioManager)
        }
        .padding()
    }

    private var meterView: some View {
        VStack(spacing: 12) {
            // dB Reading
            Text(formattedDB)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(dbColor)

            Text("dB SPL")
                .font(.caption)
                .foregroundColor(.secondary)

            // Level meter bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterGradient)
                        .frame(width: meterWidth(in: geometry.size.width))
                        .animation(.easeOut(duration: 0.1), value: audioManager.currentDB)
                }
            }
            .frame(height: 12)
        }
    }

    private var formattedDB: String {
        let db = audioManager.currentDB
        if db.isFinite && db > -96 {
            return String(format: "%.0f", db)
        }
        return "--"
    }

    private var dbColor: Color {
        let db = audioManager.currentDB
        if db > -6 { return .red }
        if db > -20 { return .yellow }
        return .green
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func meterWidth(in totalWidth: CGFloat) -> CGFloat {
        let db = audioManager.currentDB
        guard db.isFinite else { return 0 }
        // Map -96...0 dB to 0...1
        let normalized = CGFloat((db + 96) / 96)
        return max(0, min(1, normalized)) * totalWidth
    }
}
