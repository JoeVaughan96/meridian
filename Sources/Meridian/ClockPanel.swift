import SwiftUI

struct ClockPanel: View {
    @ObservedObject var store: ClockStore
    @State private var editing = false
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.clocks.isEmpty {
                Text("No clocks yet — click Edit to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            if editing {
                ForEach($store.clocks) { $clock in
                    EditRow(clock: $clock, store: store)
                }
                if adding {
                    TimeZonePicker { id in
                        store.add(timeZoneID: id)
                        adding = false
                    }
                } else {
                    Button {
                        adding = true
                    } label: {
                        Label("Add clock", systemImage: "plus")
                    }
                }
            } else {
                ForEach(store.clocks) { clock in
                    ClockRow(clock: clock, store: store)
                }
            }

            Divider()

            HStack {
                Toggle("24-hour", isOn: $store.use24Hour)
                Toggle("Open at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }
                ))
            }
            .toggleStyle(.checkbox)
            .font(.callout)

            Picker("Date in menu bar", selection: $store.menuBarDate) {
                ForEach(ClockStore.MenuBarDate.allCases, id: \.self) { Text($0.title) }
            }
            .pickerStyle(.segmented)
            .font(.callout)

            HStack {
                Button(editing ? "Done" : "Edit") {
                    editing.toggle()
                    adding = false
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { store.refresh() }
    }
}

private struct ClockRow: View {
    let clock: WorldClock
    @ObservedObject var store: ClockStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(ClockStore.cityName(for: clock.timeZoneID))
                    .font(.headline)
                Text("\(store.relativeDay(for: clock)), \(store.date(for: clock)) · \(store.offsetFromLocal(for: clock))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.time(for: clock))
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var statusDot: some View {
        let (color, help): (Color, String) = switch store.workState(for: clock) {
        case .working: (.green, "Working hours")
        case .edge: (.orange, "Early / late")
        case .offHours: (.gray, "Out of hours")
        }
        return Circle().fill(color).frame(width: 8, height: 8).help(help)
    }
}

private struct EditRow: View {
    @Binding var clock: WorldClock
    @ObservedObject var store: ClockStore

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: $clock.label)
                    .textFieldStyle(.roundedBorder)
                Text(clock.timeZoneID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: $clock.showInMenuBar) {
                Image(systemName: "menubar.rectangle")
            }
            .toggleStyle(.button)
            .help("Show in menu bar")
            Button { store.move(clock, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(store.clocks.first == clock)
            Button { store.move(clock, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(store.clocks.last == clock)
            Button(role: .destructive) { store.remove(clock) } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
    }
}

private struct TimeZonePicker: View {
    let onPick: (String) -> Void
    @State private var query = ""

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        let q = query.replacingOccurrences(of: " ", with: "_")
        return all.filter {
            $0.localizedCaseInsensitiveContains(q)
                || (TimeZone(identifier: $0)?.abbreviation()?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search city or zone (e.g. Tokyo, PST)", text: $query)
                .textFieldStyle(.roundedBorder)
            List(matches, id: \.self) { id in
                Button {
                    onPick(id)
                } label: {
                    HStack {
                        Text(id.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        Text(TimeZone(identifier: id)?.abbreviation() ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 180)
        }
    }
}
