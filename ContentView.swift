import SwiftUI
import AVFoundation
import Combine
import UIKit

struct ContentView: View {

    // MARK: - Auto-Capture / Export
    @State private var autoCaptureOn = false
    @State private var autoReady = false
    @State private var captureInterval: Double = 5.0
    @State private var captureTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    @State private var showShareSheet = false
    @State private var exportedCSV: URL?

    // MARK: - Bildzustände (aus dem ViewModel)
    @State private var liveImage: UIImage? = nil
    @State private var oxyHbImageLocal: UIImage? = nil
    @State private var deoxyHbImageLocal: UIImage? = nil

    // MARK: - Steuerung
    @State private var isMeasuring = true
    @State private var deltaOxy: Double = .nan
    @State private var deltaDeoxy: Double = .nan
    @State private var results: [MeasurementResult] = []

    // ROI – normiert (0…1)
    @State private var roi: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    // Sheets
    @State private var showResults = false
    @State private var showInfo = false
    @State private var showReferenceUpdate = false
    @State private var showScaleSettings = false

    // FPS
    @State private var fps: Double = 0.0

    // MARK: - Countdown
    @State private var countdown: Int? = nil
    @State private var countdownTask: Task<Void, Never>? = nil

    // MARK: - VM / Camera
    @StateObject private var vm: MeasurementViewModel
    @StateObject private var camera = CameraController()

    // Colormap/Skalen-Manager
    @ObservedObject private var scale = FarbskalenManager.shared

    init() {
        _vm = StateObject(wrappedValue: MeasurementViewModel())
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {

                        // Hinweis Referenz
                        referenceHintSection

                        // Live + Thumbnails
                        liveAndThumbsSection

                        // Statuswerte
                        statusRow

                        // Controls
                        controlSection
                    }
                    .padding()
                }

                // Countdown Overlay
                if let c = countdown {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    Text("\(c)")
                        .font(.system(size: 110, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: countdown)
            .navigationTitle("Hämoglobin-Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }

            .sheet(isPresented: $showResults) {
                ResultsView(results: results, onDeleteAll: { results.removeAll() })
            }
            .sheet(isPresented: $showInfo) { InfoView() }
            .sheet(isPresented: $showScaleSettings) { FarbskalenEingabeView() }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedCSV { ShareSheet(items: [url]) }
            }

            .onAppear { setupCamera() }
            .onDisappear {
                countdownTask?.cancel()
                camera.setTorch(on: false)
                camera.stop()
            }

            // VM → UI
            .onReceive(vm.$liveImage)     { liveImage = $0 }
            .onReceive(vm.$oxyHbImage)    { oxyHbImageLocal = $0 }
            .onReceive(vm.$deoxyHbImage)  { deoxyHbImageLocal = $0 }
            .onReceive(vm.$deltaOxy)      { deltaOxy = $0 }
            .onReceive(vm.$deltaDeoxy)    { deltaDeoxy = $0 }
            .onReceive(vm.$fps)           { fps = $0 }

            // ROI → VM
            .onChange(of: roi) { _, newValue in vm.roiRect = newValue }

            // Auto Toggle: erst Countdown -> dann AutoReady
            .onChange(of: autoCaptureOn) { _, newVal in
                if newVal {
                    startAutoModeWithCountdown(seconds: 3)
                } else {
                    stopAutoMode()
                }
            }

            // Auto-Capture Timer (nur wenn autoReady==true)
            .onReceive(captureTimer) { _ in
                guard autoCaptureOn, autoReady, isMeasuring else { return }
                Task { await captureOnce() }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var referenceHintSection: some View {
        if showReferenceUpdate {
            Text("🔄 Referenz aktualisiert")
                .foregroundColor(.green)
                .font(.subheadline)
                .transition(.opacity)
        }
    }

    // Livebild groß + oxy/deoxy klein
    @ViewBuilder
    private var liveAndThumbsSection: some View {
        VStack(spacing: 12) {

            // LIVE
            GeometryReader { geo in
                ZStack {
                    if let img = liveImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.15))
                            .overlay(Text("Kein Kamerabild").foregroundColor(.secondary))
                    }

                    // ROI Overlay (normiert, interaktiv)
                    ROIOverlayNormalized(normROI: $roi, containerSize: geo.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
            }
            .frame(height: 260)

            // THUMBNAILS (oxy / deoxy klein) + ✅ Skalen-Säule passend zur Colormap
            HStack(spacing: 12) {
                thumbCard(title: "oxyHb", image: oxyHbImageLocal, map: scale.oxyColormap)
                thumbCard(title: "deoxyHb", image: deoxyHbImageLocal, map: scale.deoxyColormap)
            }
        }
    }

    private func thumbCard(title: String, image: UIImage?, map: ColormapType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))

                HStack(spacing: 8) {

                    // Bild
                    Group {
                        if let img = image {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Text("…")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // ✅ Skalen-Säule rechts
                    ColorScaleBar(map: map)
                        .frame(width: 12)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Text("FPS: \(fps, specifier: "%.1f")")
            Spacer()
            Text("Δoxy: \(deltaOxy, specifier: "%.4f")")
            Spacer()
            Text("Δdeoxy: \(deltaDeoxy, specifier: "%.4f")")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var controlSection: some View {
        VStack(spacing: 12) {

            HStack(spacing: 10) {
                Button("ROI zurücksetzen") { resetROIAndReference() }
                    .buttonStyle(.bordered)

                Toggle("Auto", isOn: $autoCaptureOn)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 160)
                    .disabled(countdown != nil)
            }

            HStack(spacing: 10) {
                Button("Messung beenden") {
                    autoCaptureOn = false
                    isMeasuring = false
                    camera.setTorch(on: false)
                }
                .buttonStyle(.bordered)

                Button("Messen") {
                    isMeasuring = true
                    camera.ensureRunning()
                }
                .buttonStyle(.bordered)

                Button("Aufnehmen") {
                    startManualCaptureWithCountdown(seconds: 3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(countdown != nil)
            }

            HStack(spacing: 10) {
                Text("Intervall")
                    .foregroundColor(.secondary)
                Picker("", selection: $captureInterval) {
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                    Text("20 s").tag(20.0)
                }
                .pickerStyle(.segmented)
            }
            .onChange(of: captureInterval) { _, newVal in
                captureTimer = Timer.publish(every: newVal, on: .main, in: .common).autoconnect()
            }
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button {
                    Task.detached(priority: .utility) {
                        do {
                            let url = try CSVExporter.export(results: results)
                            await MainActor.run {
                                exportedCSV = url
                                showShareSheet = true
                            }
                        } catch {
                            print("CSV Export Fehler:", error)
                        }
                    }
                } label: {
                    Label("CSV exportieren", systemImage: "tablecells")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Button("Info") { showInfo = true }
        }

        ToolbarItem(placement: .principal) {
            Button("Ergebnisse") { showResults = true }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showScaleSettings = true } label: {
                Label("Farbskala", systemImage: "slider.vertical.3")
            }
        }
    }

    // MARK: - Logik

    private func setupCamera() {
        vm.attachCamera(camera)
        camera.configureAndStart()
        vm.roiRect = roi
        isMeasuring = true
    }

    private func resetROIAndReference() {
        roi = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        vm.roiRect = roi

        vm.referenceManager.referenceRGB = nil
        vm.referenceManager.lastUpdated = nil

        withAnimation { showReferenceUpdate = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showReferenceUpdate = false }
        }
    }

    // Auto Mode
    private func startAutoModeWithCountdown(seconds: Int = 3) {
        guard isMeasuring else {
            autoCaptureOn = false
            return
        }

        autoReady = false
        countdownTask?.cancel()

        countdownTask = Task {
            for i in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                await MainActor.run { countdown = i }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if Task.isCancelled { return }
            await MainActor.run { countdown = nil }

            await captureOnce()

            await MainActor.run {
                autoReady = true
                captureTimer = Timer.publish(every: captureInterval, on: .main, in: .common).autoconnect()
            }
        }
    }

    private func stopAutoMode() {
        autoReady = false
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    // Manuelle Aufnahme mit Countdown
    private func startManualCaptureWithCountdown(seconds: Int = 3) {
        guard isMeasuring else { return }

        countdownTask?.cancel()
        countdownTask = Task {
            for i in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                await MainActor.run { countdown = i }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if Task.isCancelled { return }
            await MainActor.run { countdown = nil }

            await captureOnce()
        }
    }

    // Aufnahme
    private func captureOnce() async {
        guard isMeasuring else { return }

        camera.ensureRunning()
        camera.setTorch(on: true)

        try? await Task.sleep(nanoseconds: 300_000_000)

        let snapDeltaOxy = vm.deltaOxy
        let snapDeltaDeoxy = vm.deltaDeoxy
        let snapLive = liveImage
        let snapOxy = oxyHbImageLocal
        let snapDeoxy = deoxyHbImageLocal

        let newResult = MeasurementResult(
            timestamp: Date(),
            deltaOxy: snapDeltaOxy,
            deltaDeoxy: snapDeltaDeoxy,
            liveImage: snapLive,
            oxyHbImage: snapOxy,
            deoxyHbImage: snapDeoxy,
            minOxy: Double(scale.minValue ?? -15.0),
            maxOxy: Double(scale.maxValue ??  15.0),
            minDeoxy: Double(scale.minValue ?? -15.0),
            maxDeoxy: Double(scale.maxValue ??  15.0),
            oxyMap: scale.oxyColormap,
            deoxyMap: scale.deoxyColormap
        )

        await MainActor.run {
            results.append(newResult)
        }

        camera.setTorch(on: false)
        print("✅ Capture gespeichert | oxyImg:", snapOxy != nil, "deoxyImg:", snapDeoxy != nil)
    }
}

// MARK: - ✅ Skalen-Säule (passt sich an hot/blau an)
private struct ColorScaleBar: View {
    let map: ColormapType
    private let steps = 60

    var body: some View {
        Canvas { ctx, size in
            let h = max(1, size.height)
            let w = max(1, size.width)
            let stepH = h / CGFloat(steps)

            for i in 0..<steps {
                // t: unten=0, oben=1  (oben = "hoch")
                let t = Double(i) / Double(max(1, steps - 1))
                let tTop = 1.0 - t

                let c = colorFromColormap(tTop, map: map)
                let y = CGFloat(i) * stepH
                let rect = CGRect(x: 0, y: y, width: w, height: stepH + 1)

                ctx.fill(Path(rect), with: .color(c))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
    }

    private func colorFromColormap(_ t: Double, map: ColormapType) -> Color {
        switch map {
        case .hot:
            return hotColor(t)
        case .blue:
            return blueColor(t)
        }
    }

    private func clamp01(_ v: Double) -> Double { v < 0 ? 0 : (v > 1 ? 1 : v) }

    // Gleiche Logik wie deine hotColormap(...)
    private func hotColor(_ t0: Double) -> Color {
        let t = clamp01(t0)
        var r = 0.0, g = 0.0, b = 0.0
        if t < 0.4 {
            r = t / 0.4
        } else if t < 0.75 {
            r = 1
            g = (t - 0.4) / 0.35
        } else {
            r = 1
            g = 1
            b = (t - 0.75) / 0.25
        }
        return Color(red: r, green: g, blue: b)
    }

    // Gleiche Logik wie deine blueColormap(...)
    private func blueColor(_ t0: Double) -> Color {
        let t = clamp01(t0)
        var r = 0.0, g = 0.0, b = 0.0
        if t < 0.45 {
            b = t / 0.45 * 0.5
        } else if t < 0.8 {
            g = (t - 0.45) / 0.35
            b = 0.5 + (t - 0.45) / 0.35 * 0.5
        } else {
            r = (t - 0.8) / 0.2
            g = 1
            b = 1
        }
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - ROI Overlay (normiert → Pixel und zurück)
private struct ROIOverlayNormalized: View {
    @Binding var normROI: CGRect
    let containerSize: CGSize

    var body: some View {
        let pixROI = CGRect(
            x: normROI.minX * containerSize.width,
            y: normROI.minY * containerSize.height,
            width: normROI.width * containerSize.width,
            height: normROI.height * containerSize.height
        )

        ROISelectorView(roi: Binding(
            get: { pixROI },
            set: { newPix in
                let nx = max(0, min(1, newPix.minX / max(1, containerSize.width)))
                let ny = max(0, min(1, newPix.minY / max(1, containerSize.height)))
                let nw = max(0, min(1 - nx, newPix.width / max(1, containerSize.width)))
                let nh = max(0, min(1 - ny, newPix.height / max(1, containerSize.height)))
                normROI = CGRect(x: nx, y: ny, width: nw, height: nh)
            }
        ))
        .allowsHitTesting(true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
