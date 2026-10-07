import SwiftUI
import Combine
import RealityKit
import UIKit

@MainActor
struct ContentView: View {
    @StateObject private var scan = ScanManager()
    private let ticker = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ARViewContainer(arView: scan.arView)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                statusBar
                Spacer()
                if !scan.message.isEmpty {
                    Text(scan.message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                controls
            }
            .padding()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            scan.startPreview()
        }
        .onReceive(ticker) { _ in
            scan.tick()
        }
        .sheet(isPresented: $scan.showShare) {
            ActivityView(items: scan.exportedFiles)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            stat(title: "Malla", value: scan.meshVertices, unit: "vértices")
            Divider().frame(height: 34)
            stat(title: "Nube a color", value: scan.cloudPoints, unit: "puntos")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(title: String, value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.headline.monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 96)
    }

    @ViewBuilder
    private var controls: some View {
        switch scan.phase {
        case .idle:
            bigButton("Iniciar escaneo", systemImage: "viewfinder", tint: .blue) {
                scan.startScan()
            }
            .disabled(!scan.lidarAvailable)
        case .scanning:
            bigButton("Detener", systemImage: "stop.fill", tint: .red) {
                scan.stopScan()
            }
        case .finished:
            HStack(spacing: 12) {
                bigButton("Nuevo", systemImage: "arrow.counterclockwise", tint: .gray) {
                    scan.newScan()
                }
                .disabled(scan.isExporting)
                bigButton(scan.isExporting ? "Exportando…" : "Exportar",
                          systemImage: "square.and.arrow.up", tint: .green) {
                    scan.export()
                }
                .disabled(scan.isExporting)
            }
        }
    }

    private func bigButton(_ title: String, systemImage: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
    }
}

/// Muestra la vista de cámara + malla de RealityKit dentro de SwiftUI.
struct ARViewContainer: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView {
        arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Hoja estándar de iOS para compartir o guardar los archivos exportados.
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
