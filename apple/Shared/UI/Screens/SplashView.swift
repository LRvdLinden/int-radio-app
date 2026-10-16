import SwiftUI
import AVFoundation

/// Intro (SPEC §3.1, ±3,4 s, met tune, overslaanbaar):
/// frequentieschaal 88–108 fadet in → naald zoekt met haperingen (0–1,4 s) → op 1,45 s klik/lock met
/// 3 cirkelgolven → T U N R springen omhoog (90 ms uit elkaar), de schaal krimpt tot de balk onder het woordmerk →
/// glanzende veeg (2,1 s) → fade-out (3,1–3,4 s).
struct SplashView: View {
    let onFinished: () -> Void

    @State private var scaleIn = false
    @State private var needle: CGFloat = 0.02
    @State private var locked = false
    @State private var waves = false
    @State private var lettersIn = 0
    @State private var collapse = false
    @State private var shine = false
    @State private var out = false
    @State private var finished = false

    private let letters = Array("TUNR")
    private var size: CGFloat { tvScaled(64) }
    /// Breedte van de grote schaal
    private var dialWidth: CGFloat { tvScaled(DeviceKind.isPhone ? 300 : 440) }
    /// Breedte van de balk onder het woordmerk (zelfde verhouding als TunrLogo)
    private var barWidth: CGFloat { size * 2.75 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // gloed achter het woordmerk
            RadialGradient(colors: [Theme.accent.opacity(locked ? 0.28 : 0), .clear], center: .center,
                           startRadius: 0, endRadius: dialWidth * 0.9)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.6), value: locked)

            // cirkelgolven bij de lock
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: tvScaled(2.5))
                    .frame(width: tvScaled(40), height: tvScaled(40))
                    .scaleEffect(waves ? 9 + CGFloat(i) * 2.5 : 0.4)
                    .opacity(waves ? 0 : (locked ? 0.9 : 0))
                    .animation(.easeOut(duration: 1.25).delay(Double(i) * 0.16), value: waves)
                    .offset(x: needleX - dialWidth / 2)
            }

            VStack(spacing: size * 0.14) {
                // woordmerk
                ZStack {
                    HStack(spacing: size * 0.08) {
                        ForEach(Array(letters.enumerated()), id: \.offset) { i, ch in
                            Text(String(ch))
                                .font(.system(size: size, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .offset(y: lettersIn > i ? 0 : size * 0.8)
                                .opacity(lettersIn > i ? 1 : 0)
                                .scaleEffect(lettersIn > i ? 1 : 0.6, anchor: .bottom)
                        }
                    }
                    // glanzende veeg
                    LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: size * 1.1)
                        .rotationEffect(.degrees(18))
                        .offset(x: shine ? size * 3 : -size * 3)
                        .blendMode(.overlay)
                        .mask {
                            HStack(spacing: size * 0.08) {
                                ForEach(Array(letters.enumerated()), id: \.offset) { _, ch in
                                    Text(String(ch)).font(.system(size: size, weight: .heavy, design: .rounded))
                                }
                            }
                        }
                }
                .frame(height: size * 1.1)
                .opacity(lettersIn > 0 ? 1 : 0)

                // frequentieschaal → krimpt tot de balk onder het woordmerk
                dial
                    .frame(width: collapse ? barWidth : dialWidth, height: collapse ? size * 0.34 : tvScaled(64))
            }
            .offset(y: lettersIn > 0 ? 0 : -size * 0.62)
            .scaleEffect(out ? 1.08 : 1)
            .opacity(out ? 0 : 1)

            skipButton
        }
        .task { await run() }
    }

    private var needleX: CGFloat { (collapse ? barWidth : dialWidth) * needle }

    /// De schaal met getallen 88–108, maatstreepjes, balk en naald
    private var dial: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottomLeading) {
                // getallen (verdwijnen bij het krimpen)
                HStack(spacing: 0) {
                    ForEach([88, 92, 96, 100, 104, 108], id: \.self) { f in
                        Text("\(f)")
                            .font(.system(size: tvScaled(11), weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: w * 1.2)
                .offset(x: -w * 0.1, y: -h * 0.72)
                .opacity(collapse ? 0 : 1)

                // maatstreepjes: 41 op de grote schaal, 9 als balk
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<tickCount, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(isMajorTick(i) ? 0.85 : 0.45))
                            .frame(width: tickWidth(h), height: tickHeight(i, h))
                        if i < tickCount - 1 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: w, height: h * 0.62, alignment: .bottom)
                .offset(y: -h * (collapse ? 0.32 : 0.12))

                // balk in het accentverloop
                Capsule()
                    .fill(Theme.gradient)
                    .frame(width: w, height: max(2, collapse ? h * 0.26 : tvScaled(3)))

                // naald
                Capsule()
                    .fill(Theme.accent2)
                    .frame(width: needleWidth, height: collapse ? h : h * 0.9)
                    .shadow(color: Theme.accent2.opacity(0.9), radius: tvScaled(locked ? 8 : 4))
                    .offset(x: w * needle - tvScaled(1.5))
            }
            .frame(width: w, height: h, alignment: .bottomLeading)
        }
        .opacity(scaleIn ? 1 : 0)
    }

    private var needleWidth: CGFloat { max(2, tvScaled(collapse ? 2.5 : 3)) }

    private var tickCount: Int { collapse ? 9 : 41 }

    private func isMajorTick(_ i: Int) -> Bool { collapse ? (i == 4) : (i % 8 == 0) }

    private func tickWidth(_ h: CGFloat) -> CGFloat {
        collapse ? max(1, h * 0.12) : tvScaled(1.5)
    }

    private func tickHeight(_ i: Int, _ h: CGFloat) -> CGFloat {
        let even = i % 2 == 0
        if collapse { return h * (even ? 0.5 : 0.32) }
        if isMajorTick(i) { return h * 0.42 }
        return h * (even ? 0.28 : 0.18)
    }

    /// Volledig scherm = één knop: tikken (iPhone/iPad/Mac) of Select/Play-Pause (Apple TV) slaat over
    private var skipButton: some View {
        Button(action: finish) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(SplashSkipStyle())
        .ignoresSafeArea()
        .accessibilityLabel(L("splash.skip"))
        #if os(tvOS)
        .onPlayPauseCommand(perform: finish)
        #endif
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        SplashTune.fadeOut()
        onFinished()
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func run() async {
        SplashTune.play()
        withAnimation(.easeOut(duration: 0.35)) { scaleIn = true }

        // naald zoekt van links naar rechts met haperingen (0–1,4 s)
        let stops: [(CGFloat, Double)] = [(0.18, 0.28), (0.15, 0.1), (0.36, 0.26), (0.33, 0.1), (0.52, 0.22), (0.49, 0.1), (0.62, 0.22)]
        await sleep(0.1)
        for (pos, dur) in stops {
            guard !finished else { return }
            withAnimation(.easeInOut(duration: dur)) { needle = pos }
            await sleep(dur)
        }
        // ≈1,38 s → klik/lock op 1,45 s
        await sleep(0.07)
        guard !finished else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { needle = 0.58 }
        locked = true          // golven direct zichtbaar (klein), daarna uitdijen en vervagen
        Haptics.rigid()
        await sleep(0.04)
        waves = true

        // letters één voor één (90 ms), schaal krimpt tot de balk
        await sleep(0.11)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { collapse = true }
        for i in 1...letters.count {
            guard !finished else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.55)) { lettersIn = i }
            if i == letters.count { Haptics.rigid() } else { Haptics.tap() }
            await sleep(0.09)
        }

        // glanzende veeg op 2,1 s
        await sleep(0.14)
        guard !finished else { return }
        withAnimation(.easeInOut(duration: 0.7)) { shine = true }

        // fade-out 3,1–3,4 s
        await sleep(1.0)
        guard !finished else { return }
        withAnimation(.easeIn(duration: 0.3)) { out = true }
        await sleep(0.3)
        finish()
    }
}

/// Onzichtbare knop zonder focusvlak
private struct SplashSkipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// De Tunr-intro-tune (Shared/Resources/tunr_tune.m4a, gemaakt met tools/make_tune.py).
/// `.playback` + `mixWithOthers`. Build 9: speelt altijd (geen instelling meer).
enum SplashTune {
    @MainActor private static var player: AVAudioPlayer?

    static let enabled = true

    @MainActor static func play() {
        guard enabled, let url = Bundle.main.url(forResource: "tunr_tune", withExtension: "m4a") else { return }
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 0.9
        p.prepareToPlay()
        p.play()
        player = p
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if player === p { player = nil }
        }
    }

    /// Bij overslaan zacht uitfaden
    @MainActor static func fadeOut() {
        guard let p = player, p.isPlaying else { return }
        p.setVolume(0, fadeDuration: 0.35)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            p.stop()
            if player === p { player = nil }
        }
    }
}
