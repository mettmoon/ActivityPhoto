import GeoshopCore
import SwiftUI

/// 시간대 직접 선택. 검색 가능한 목록.
struct TimeZonePickerSheet: View {
    let current: TimeZone
    /// 오프셋 표기에 쓸 기준 시각 (트랙 시작 시각). 서머타임 반영용.
    let referenceDate: Date
    var onSelect: (TimeZone) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { id in
            id.localizedCaseInsensitiveContains(query)
                || (TimeZone(identifier: id)?.localizedName(for: .generic, locale: .current) ?? "")
                    .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(identifiers, id: \.self, selection: $selection) { id in
                let zone = TimeZone(identifier: id)
                HStack {
                    VStack(alignment: .leading) {
                        Text(id)
                        if let name = zone?.localizedName(for: .generic, locale: .current) {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let zone {
                        Text("GMT\(zone.offsetString(at: referenceDate))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "도시 또는 시간대 검색")

            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("선택") {
                    if let selection, let zone = TimeZone(identifier: selection) { onSelect(zone) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
        .onAppear { selection = current.identifier }
    }
}
