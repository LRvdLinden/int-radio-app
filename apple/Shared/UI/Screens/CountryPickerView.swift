import SwiftUI

/// Landkeuze: verplicht bij de eerste start, daarna via Instellingen of de landknop op Ontdek.
/// Zoekveld, "Voorgesteld" (land van het toestel), "Alle landen" alfabetisch. tv: raster van landkaarten.
struct CountryPickerView: View {
    var isFirstRun = false

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<[Country]> = .idle
    @State private var query = ""

    var body: some View {
        content
            .task { if state.value == nil { await load() } }
    }

    @ViewBuilder private var content: some View {
        #if os(tvOS)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    tvContent(for: filtered)
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, 40)
            }
            .searchable(text: $query, prompt: L("country.search"))
            .screenBackground()
        }
        #else
        NavigationStack {
            listContent
                .searchable(text: $query, prompt: L("country.search"))
                .navigationTitle(isFirstRun ? "" : L("country.title"))
                .inlineTitle()
                .toolbar {
                    if !isFirstRun {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("action.close")) { close() }
                        }
                    }
                }
                .screenBackground()
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: tvScaled(6)) {
            if isFirstRun {
                TunrLogo(size: tvScaled(26)).padding(.bottom, tvScaled(12))
            }
            Text(L("country.title")).font(Theme.screenTitle).foregroundStyle(.white)
            Text(L("country.subtitle")).font(Theme.body).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: iPhone / iPad / Mac: lijst

    #if !os(tvOS)
    @ViewBuilder private var listContent: some View {
        List {
            Section {
                header
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            switch state {
            case .idle, .loading:
                Section {
                    ForEach(0..<10, id: \.self) { _ in
                        HStack(spacing: 14) {
                            Circle().fill(Theme.surface).frame(width: 36, height: 36)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: 160, height: 14)
                        }
                        .shimmering()
                        .listRowBackground(Theme.surface.opacity(0.4))
                    }
                }
            case .failed:
                Section {
                    ErrorRetryView { Task { await load() } }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            case .loaded:
                let list = filtered
                if query.isEmpty, let suggested = suggested {
                    Section(L("country.suggested")) { row(suggested) }
                }
                Section(L("country.all")) {
                    ForEach(list) { row($0) }
                }
                if list.isEmpty {
                    Text(L("search.noResults"))
                        .foregroundStyle(Theme.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ c: Country) -> some View {
        Button { choose(c) } label: {
            HStack(spacing: 14) {
                Text(c.flag.isEmpty ? "🏳️" : c.flag).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.localizedName).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(L("stations.count", formattedNumber(c.stationCount)))
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if library.countryCode == c.code {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .accessibilityLabel(c.localizedName + ", " + L("stations.count", formattedNumber(c.stationCount)))
        .accessibilityAddTraits(library.countryCode == c.code ? .isSelected : [])
    }
    #endif

    // MARK: Apple TV: raster

    #if os(tvOS)
    @ViewBuilder private func tvContent(for list: [Country]) -> some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        case .failed:
            ErrorRetryView { Task { await load() } }.frame(maxWidth: .infinity)
        case .loaded:
            VStack(alignment: .leading, spacing: 30) {
                if query.isEmpty, let suggested {
                    Text(L("country.suggested")).font(Theme.rowTitle).foregroundStyle(.white)
                    countryGrid([suggested])
                }
                Text(L("country.all")).font(Theme.rowTitle).foregroundStyle(.white)
                countryGrid(list)
            }
        }
    }

    private func countryGrid(_ list: [Country]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 5), spacing: 40) {
            ForEach(list) { c in
                Button { choose(c) } label: {
                    VStack(spacing: 10) {
                        Text(c.flag.isEmpty ? "🏳️" : c.flag).font(.system(size: 80))
                        Text(c.localizedName).font(.system(size: 26, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Text(L("stations.count", formattedNumber(c.stationCount)))
                            .font(.system(size: 20)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(library.countryCode == c.code ? Theme.elevated : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .focusRing()
                }
                .cardButton()
            }
        }
        .focusSection()
    }
    #endif

    // MARK: Logica

    private var all: [Country] {
        (state.value ?? []).sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    private var filtered: [Country] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.localizedName.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.caseInsensitiveCompare(q) == .orderedSame
        }
    }

    private var suggested: Country? {
        all.first { $0.code == Country.deviceCode }
    }

    private func load() async {
        state = .loading
        do {
            let list = try await RadioBrowser.shared.countries()
            withAnimation(.easeOut(duration: 0.25)) { state = list.isEmpty ? .failed : .loaded(list) }
        } catch {
            state = .failed
        }
    }

    private func choose(_ c: Country) {
        Haptics.success()
        library.setCountry(c)
        if isFirstRun {
            app.countryChosen()
        } else {
            close()
        }
    }

    private func close() {
        app.showCountryPicker = false
        dismiss()
    }
}
