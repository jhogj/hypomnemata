import HypomnemataData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Dependências") {
                ForEach(model.dependencyStatuses) { status in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.isInstalled ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(status.requirement.executable)
                                .font(.headline)
                            Text(status.requirement.purpose)
                                .foregroundStyle(.secondary)
                            if let path = status.path {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(status.requirement.installCommand)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Reverificar") {
                    model.refreshDependencies()
                }
            }
        }
        .padding()
        .frame(width: 560, height: 420)
    }
}
