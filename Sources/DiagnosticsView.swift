import SwiftUI

/// Pantalla de diagnóstico: mapa de profundidad en vivo y números del sensor.
struct DiagnosticsView: View {
    let report: LidarReport?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let report {
                ScrollView {
                    content(report)
                }
            } else {
                Spacer()
                ProgressView("Leyendo el sensor…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
            }

            Button(action: onClose) {
                Label("Cerrar diagnóstico", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
            .controlSize(.large)
        }
        .padding()
    }

    private func content(_ r: LidarReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            verdict(r.status)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    if let image = r.image {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Rojo cerca · azul lejos\nOscuro = poca confianza")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 140)

                VStack(alignment: .leading, spacing: 5) {
                    row("Centro (+)", distance(r.centerDistance))
                    row("Rango", "\(distance(r.nearDistance)) a \(distance(r.farDistance))")
                    row("Lecturas/s", String(format: "%.0f", r.depthRate))
                    row("Resolución", r.depthSize)
                    row("Con lectura", percent(r.validPercent))
                    row("Conf. alta", percent(r.highPercent))
                    row("Conf. media", percent(r.mediumPercent))
                    row("Conf. baja", percent(r.lowPercent))
                    row("Seguimiento", r.tracking)
                    row("Luz", r.light.map { String(format: "%.0f", $0) } ?? "—")
                    row("Temperatura", r.thermal)
                }
                .font(.footnote)
            }

            ForEach(r.issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(r.status == .failure ? Color.red : Color.orange)
            }

            Text("Prueba de precisión: apunta el + a una pared mate a 1 m y compara la distancia "
                 + "del centro con una huincha. 1 a 2 cm de diferencia es normal. "
                 + "Un sensor sano muestra más de 70 % de confianza alta frente a una pared.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func verdict(_ status: LidarReport.Status) -> some View {
        let text: String
        let icon: String
        let color: Color
        switch status {
        case .ok:
            text = "Sensor LiDAR funcionando bien"
            icon = "checkmark.seal.fill"
            color = .green
        case .warning:
            text = "Funciona, con observaciones"
            icon = "exclamationmark.circle.fill"
            color = .orange
        case .failure:
            text = "Problema detectado"
            icon = "xmark.octagon.fill"
            color = .red
        }
        return Label(text, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).monospacedDigit()
        }
    }

    private func distance(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f m", value)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f %%", value)
    }
}
