import SwiftUI

struct HistoryChartView: View {
    @ObservedObject var audioManager: AudioManager

    private let minDB: Float = 0
    private let maxDB: Float = 130
    private let gridLines: [Float] = [0, 30, 60, 85, 100, 130]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Grid lines and labels
                ForEach(gridLines, id: \.self) { db in
                    let y = yPosition(for: db, in: height)
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

                    Text("\(Int(db))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .position(x: 14, y: y)
                }

                // Line chart
                if audioManager.dbHistory.count >= 2 {
                    chartPath(in: CGSize(width: width - 30, height: height))
                        .offset(x: 30)
                }
            }
        }
    }

    private func yPosition(for db: Float, in height: CGFloat) -> CGFloat {
        let normalized = CGFloat((db - minDB) / (maxDB - minDB))
        return height * (1 - normalized)
    }

    private func chartPath(in size: CGSize) -> some View {
        let history = audioManager.dbHistory

        return Path { path in
            for (index, db) in history.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(history.count - 1, 1))
                let clampedDB = max(min(db, maxDB), minDB)
                let normalized = CGFloat((clampedDB - minDB) / (maxDB - minDB))
                let y = size.height * (1 - normalized)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(lineGradient(for: history, in: size), lineWidth: 2)
    }

    private func lineGradient(for history: [Float], in size: CGSize) -> LinearGradient {
        var stops: [Gradient.Stop] = []

        for (index, db) in history.enumerated() {
            let position = Double(index) / Double(max(history.count - 1, 1))
            stops.append(Gradient.Stop(color: colorForDB(db), location: position))
        }

        if stops.isEmpty {
            stops = [Gradient.Stop(color: .green, location: 0)]
        }

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func colorForDB(_ db: Float) -> Color {
        if db > 85 { return .red }
        if db > 70 { return .yellow }
        return .green
    }
}
