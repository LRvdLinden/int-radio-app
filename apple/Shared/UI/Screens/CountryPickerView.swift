import SwiftUI

/// Landkeuze: verplicht bij de eerste start, daarna via Instellingen of de landknop op Ontdek.
/// Zoekveld, "Voorgesteld" (land van het toestel), "Alle landen" alfabetisch. tv: schermvullend raster van landrijen.
struct CountryPickerView: View {
    var isFirstRun = false

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<[Country]> = .idle
    @State private var query = ""
    #if os(tvOS)
    @FocusState private var focusedKey: String?
    #endif

    var body: some View {
        content
            .task { if state.value == nil { await load() } }
    }

    @ViewBuilder private var content: some View {
        #if os(tvOS)
        // Apple TV: schermvullend (fullScreenCover), raster van landrijen dat met de focus meescrolt;
        // het huidige land is gemarkeerd en krijgt de focus; Menu sluit het scherm (systeemgedrag).
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        header
                        tvContent(for: filtered)
                    }
                    .padding(.horizontal, Theme.edge)
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
                .searchable(text: $query, prompt: L("country.search"))
                .screenBackground()
                .onChange(of: state.value?.count ?? 0) { _, count in
                    guard count > 0 else { return }
                    focusCurrent(proxy)
                }
                .onAppear { if state.value != nil { focusCurrent(proxy) } }
            }
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
        .hiddenListBackground()
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
                    countryGrid([suggested], prefix: "sug-")
                }
                Text(L("country.all")).font(Theme.rowTitle).foregroundStyle(.white)
                if list.isEmpty {
                    Text(L("search.noResults")).font(Theme.body).foregroundStyle(Theme.secondary)
                } else {
                    countryGrid(list, prefix: "all-")
                }
            }
        }
    }

    private func countryGrid(_ list: [Country], prefix: String) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 12) {
            ForEach(list) { c in
                let key = prefix + c.code
                Button { choose(c) } label: {
                    TVCountryRow(country: c, isCurrent: library.countryCode == c.code)
                }
                .buttonStyle(TVRowButtonStyle())
                .focused($focusedKey, equals: key)
                .id(key)
                .accessibilityLabel(c.localizedName + ", " + L("stations.count", formattedNumber(c.stationCount)))
                .accessibilityAddTraits(library.countryCode == c.code ? .isSelected : [])
            }
        }
        .focusSection()
    }

    /// Huidig land in beeld scrollen en de focus erop zetten
    private func focusCurrent(_ proxy: ScrollViewProxy) {
        guard query.isEmpty, let code = library.countryCode, all.contains(where: { $0.code == code }) else { return }
        let key = "all-" + code
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            proxy.scrollTo(key, anchor: .center)
            try? await Task.sleep(nanoseconds: 150_000_000)
            focusedKey = key
        }
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

#if os(tvOS)
/// Apple TV: één landrij (vlag, naam, aantal zenders, ✓ bij het huidige land)
private struct TVCountryRow: View {
    let country: Country
    let isCurrent: Bool
    @Environment(\.tvFocused) private var focused

    var body: some View {
        HStack(spacing: 18) {
            Text(country.flag.isEmpty ? "🏳️" : country.flag).font(.system(size: 50))
            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(isCurrent ? Theme.accent : .white)
                    .lineLimit(1)
                Text(L("stations.count", formattedNumber(country.stationCount)))
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent && !focused ? Theme.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}
#endif
