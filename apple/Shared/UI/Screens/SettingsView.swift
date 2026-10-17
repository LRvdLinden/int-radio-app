import SwiftUI

/// Instellingen: Land, Taal, Intromuziek, Slaaptimer standaard, Automatisch verder spelen,
/// Recent/Favorieten wissen (met bevestiging), Anonieme gebruiksstatistieken, Over.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.defaultSleep) private var defaultSleep = 0
    @AppStorage(SettingsKey.autoplayLast) private var autoplayLast = false
    @AppStorage(SettingsKey.shareStats) private var shareStats = true
    @AppStorage(SettingsKey.liveActivity) private var liveActivity = true
    @State private var confirmRecents = false
    @State private var confirmFavorites = false
    @State private var showCountry = false

    var body: some View {
        form
            .navigationTitle(L("tab.settings"))
            .inlineTitle()
            .confirmationDialog(L("settings.clearRecentConfirm"), isPresented: $confirmRecents, titleVisibility: .visible) {
                Button(L("action.clear"), role: .destructive) { library.clearRecents() }
                Button(L("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L("settings.clearFavoritesConfirm"), isPresented: $confirmFavorites, titleVisibility: .visible) {
                Button(L("action.clear"), role: .destructive) { library.clearFavorites() }
                Button(L("action.cancel"), role: .cancel) {}
            }
            #if os(tvOS)
            // Apple TV: schermvullende landkeuze (Menu sluit)
            .fullScreenCover(isPresented: $showCountry) { CountryPickerView() }
            #else
            // eigen blad (Instellingen kan zelf al een blad zijn, of op de Mac een apart venster)
            .sheet(isPresented: $showCountry) { CountryPickerView() }
            #endif
    }

    private var form: some View {
        Form {
            Section {
                Button { showCountry = true } label: {
                    HStack {
                        settingLabel(L("settings.country"), symbol: "globe")
                        Spacer()
                        if let code = library.countryCode {
                            Text(Country.flag(for: code) + " " + Country.localizedName(code: code, fallback: library.countryName))
                                .modifier(SecondaryText())
                        }
                        Image(systemName: "chevron.right").font(.system(size: tvScaled(12), weight: .semibold)).modifier(SecondaryText())
                    }
                    .contentShape(Rectangle())
                }
                #if os(tvOS)
                // systeemstijl: dezelfde focus als de keuzelijsten en schakelaars eronder
                .buttonStyle(.automatic)
                #else
                .buttonStyle(.plain)
                #endif

                Picker(selection: $localizer.override) {
                    Text(L("settings.languageSystem")).tag("")
                    Text("Nederlands").tag("nl")
                    Text("English").tag("en")
                } label: {
                    settingLabel(L("settings.language"), symbol: "character.bubble")
                }
            } header: {
                Text(L("settings.general"))
            }

            Section {
                Picker(selection: $defaultSleep) {
                    Text(L("sleep.off")).tag(0)
                    ForEach([15, 30, 60], id: \.self) { m in Text(L("sleep.minutes", m)).tag(m) }
                } label: {
                    settingLabel(L("settings.defaultSleep"), symbol: "moon.zzz")
                }
                Toggle(isOn: $autoplayLast) {
                    settingLabel(L("settings.autoplay"), symbol: "play.circle")
                }
                #if os(iOS) && canImport(ActivityKit)
                // Live Activity (Dynamic Island, vergrendelscherm): alleen iPhone, per apparaat
                if DeviceKind.isPhone {
                    Toggle(isOn: $liveActivity) {
                        settingLabel(L("settings.liveActivity"), symbol: "iphone.radiowaves.left.and.right")
                    }
                    .onChange(of: liveActivity) { _, _ in
                        LiveActivityController.shared.sync()
                    }
                }
                #endif
            } header: {
                Text(L("settings.playback"))
            } footer: {
                // alleen iPhone (Live Activity); elders blijft de voettekst leeg
                if DeviceKind.isPhone {
                    Text(L("settings.liveActivityFooter"))
                }
            }

            Section {
                Button(role: .destructive) { confirmRecents = true } label: {
                    settingLabel(L("settings.clearRecent"), symbol: "clock.arrow.circlepath", tint: Theme.live)
                }
                .disabled(library.recents.isEmpty)
                Button(role: .destructive) { confirmFavorites = true } label: {
                    settingLabel(L("settings.clearFavorites"), symbol: "heart.slash", tint: Theme.live)
                }
                .disabled(library.favorites.isEmpty)
            } header: {
                Text(L("settings.data"))
            } footer: {
                Text(L("settings.icloudFooter"))
            }

            Section {
                Toggle(isOn: $shareStats) {
                    settingLabel(L("settings.shareStats"), symbol: "chart.bar")
                }
                .onChange(of: shareStats) { _, on in
                    if on { StatsPing.shared.pingIfDue() }
                }
            } header: {
                Text(L("settings.privacySection"))
            } footer: {
                Text(L("settings.shareStatsFooter"))
            }

            Section {
                tvFocusableRow {
                    HStack {
                        settingLabel(L("settings.version"), symbol: "info.circle")
                        Spacer()
                        Text(Brand.versionText).modifier(SecondaryText()).monospacedDigit()
                    }
                }
                linkRow(L("settings.website"), symbol: "safari", url: Brand.website)
                linkRow(L("settings.privacy"), symbol: "hand.raised", url: Brand.privacy)
                linkRow(L("settings.terms"), symbol: "doc.text", url: Brand.terms)
                linkRow(L("about.source"), symbol: "antenna.radiowaves.left.and.right", url: Brand.radioBrowser)
            } header: {
                Text(L("settings.about"))
            } footer: {
                VStack(spacing: tvScaled(10)) {
                    TunrLogo(size: tvScaled(18))
                    Text(L("settings.madeWith")).font(Theme.caption).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, tvScaled(20))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .hiddenListBackground()
        .screenBackground()
    }

    private func settingLabel(_ title: String, symbol: String, tint: Color? = nil) -> some View {
        HStack(spacing: tvScaled(12)) {
            Image(systemName: symbol)
                .font(.system(size: tvScaled(14), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: tvScaled(28), height: tvScaled(28))
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: tvScaled(7), style: .continuous))
            settingTitle(title, tint: tint)
        }
    }

    /// Titel: wit (iPhone/iPad/Mac). Apple TV: systeemkleur, zodat de tekst op het witte focusvlak donker wordt.
    @ViewBuilder private func settingTitle(_ title: String, tint: Color?) -> some View {
        #if os(tvOS)
        if let tint { Text(title).foregroundStyle(tint) } else { Text(title) }
        #else
        Text(title).foregroundStyle(tint ?? .white)
        #endif
    }

    /// Apple TV: rijen zonder actie toch focusbaar maken, zodat je met de afstandsbediening tot onderaan kunt scrollen
    @ViewBuilder private func tvFocusableRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(tvOS)
        Button {} label: { content() }
        #else
        content()
        #endif
    }

    @ViewBuilder private func linkRow(_ title: String, symbol: String, url: URL) -> some View {
        #if os(tvOS)
        // geen browser op Apple TV: alleen het adres tonen (wel focusbaar, anders kun je er niet naartoe scrollen)
        tvFocusableRow {
            HStack {
                settingLabel(title, symbol: symbol)
                Spacer()
                Text(url.host ?? url.absoluteString).modifier(SecondaryText())
            }
        }
        #else
        Button { openURL(url) } label: {
            HStack {
                settingLabel(title, symbol: symbol)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #endif
    }
}

/// Grijze bijtekst: Theme.secondary; Apple TV: hiërarchische systeemkleur (leesbaar op het witte focusvlak)
private struct SecondaryText: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.foregroundStyle(.secondary)
        #else
        content.foregroundStyle(Theme.secondary)
        #endif
    }
}
