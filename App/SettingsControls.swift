import SwiftUI

/// Keeps high-frequency slider state inside the settings row. Persist the
/// value only when the drag ends so the map view and its annotations are not
/// invalidated for every touch-moved event.
struct DeferredSettingsSliderRow: View {
    let title: String
    @Binding private var value: Double
    let range: ClosedRange<Double>
    let lowerLabel: String?
    let upperLabel: String?
    private let formattedValue: (Double) -> String
    private let onCommit: () -> Void

    @State private var draftValue: Double
    @State private var isEditing = false

    init(title: String,
         value: Binding<Double>,
         range: ClosedRange<Double>,
         lowerLabel: String? = nil,
         upperLabel: String? = nil,
         formattedValue: @escaping (Double) -> String,
         onCommit: @escaping () -> Void = {}) {
        self.title = title
        self._value = value
        self.range = range
        self.lowerLabel = lowerLabel
        self.upperLabel = upperLabel
        self.formattedValue = formattedValue
        self.onCommit = onCommit
        self._draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue(draftValue))
                    .font(.caption)
                    .foregroundStyle(adaptiveSecondaryInk)
            }
            HStack(spacing: 8) {
                if let lowerLabel {
                    Text(lowerLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(adaptiveSecondaryInk)
                }
                Slider(value: $draftValue, in: range) { editing in
                    isEditing = editing
                    if !editing {
                        value = draftValue
                        onCommit()
                    }
                }
                if let upperLabel {
                    Text(upperLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(adaptiveSecondaryInk)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { draftValue = value }
        .onChange(of: value) { _, updatedValue in
            if !isEditing { draftValue = updatedValue }
        }
    }
}

/// The map health log changes during recovery; observing it only in this row
/// prevents diagnostic messages from invalidating the entire map/settings tree.
struct MapHealthStatusRow: View {
    @AppStorage("wijhati.health.log") private var healthLog = ""

    var body: some View {
        HStack(alignment: .top) {
            Text("حالة الخريطة".loc)
            Spacer(minLength: 8)
            Text(healthLog.isEmpty ? "—" : healthLog)
                .font(.caption2)
                .foregroundStyle(adaptiveSecondaryInk)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}
