import SwiftUI

/// Huisstijl van de ontwikkelaar (lrvdlinden.app), zelfde als de kaart in Homey Store
/// (Homey-Store-ios: Views/Components/MoreAppsCard.swift). Tunr is altijd donker: de donkere waarden.
/// Ook gebruikt door de Apple Watch-app (project.yml: TunrWatch neemt dit bestand mee).
enum DeveloperBrand {
    static let url = URL(string: "https://lrvdlinden.app")!
    static let accent = Color(red: 0x8A / 255, green: 0x9D / 255, blue: 0xFF / 255)
    static let onAccent = Color(red: 0x0D / 255, green: 0x10 / 255, blue: 0x18 / 255)
    static let muted = Color(red: 0x98 / 255, green: 0xA0 / 255, blue: 0xB3 / 255)
    static let surface = Color(red: 0x16 / 255, green: 0x1B / 255, blue: 0x27 / 255)
    static let line = Color(red: 0x26 / 255, green: 0x2D / 255, blue: 0x3D / 255)
    /// De logotegel is altijd donkerblauw-zwart met de blauwe stip
    static let logoTile = Color(red: 0x12 / 255, green: 0x17 / 255, blue: 0x26 / 255)
    static let logoDot = Color(red: 0x4C / 255, green: 0x6B / 255, blue: 0xFF / 255)
}

/// Het "LR"-merk van lrvdlinden.app, getekend (ontwerpraster 512 × 512)
struct LRLogo: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 512
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 116 * s, style: .continuous),
                     with: .color(DeveloperBrand.logoTile))

            var letters = Path()
            // L
            letters.move(to: p(132, 146)); letters.addLine(to: p(132, 370)); letters.addLine(to: p(232, 370))
            // R: stam + boog
            letters.move(to: p(292, 370)); letters.addLine(to: p(292, 146)); letters.addLine(to: p(340, 146))
            letters.addArc(center: p(340, 208), radius: 62 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            letters.addLine(to: p(292, 270))
            // R: poot
            letters.move(to: p(338, 270)); letters.addLine(to: p(390, 370))
            ctx.stroke(letters, with: .color(.white),
                       style: StrokeStyle(lineWidth: 46 * s, lineCap: .round, lineJoin: .round))

            let dot = Path(ellipseIn: CGRect(x: (404 - 34) * s, y: (126 - 34) * s, width: 68 * s, height: 68 * s))
            ctx.fill(dot, with: .color(DeveloperBrand.logoDot))
            ctx.stroke(dot, with: .color(DeveloperBrand.logoTile), lineWidth: 14 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Kaart "Meer apps van de ontwikkelaar" onder in Instellingen; opent lrvdlinden.app.
/// Teksten komen van de app (Tunr: Localizable.strings nl/en). Met `action` (Apple TV: QR-code) een knop in plaats
/// van een link. `compact` = Apple Watch (kleiner, zonder knop rechts).
struct MoreAppsCard: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    var compact = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { card }
                #if os(tvOS)
                .buttonStyle(.card)
                #else
                .buttonStyle(.plain)
                #endif
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title). \(subtitle)")
                .accessibilityHint("lrvdlinden.app")
        } else {
            Link(destination: DeveloperBrand.url) { card }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title). \(subtitle)")
                .accessibilityHint("lrvdlinden.app")
                .accessibilityAddTraits(.isLink)
        }
    }

    private var logoSize: CGFloat {
        #if os(tvOS)
        return 96
        #else
        return compact ? 40 : 60
        #endif
    }

    private var radius: CGFloat {
        #if os(tvOS)
        return 30
        #else
        return compact ? 16 : 22
        #endif
    }

    private var card: some View {
        HStack(spacing: compact ? 10 : 14) {
            LRLogo(size: logoSize)
                .overlay(RoundedRectangle(cornerRadius: logoSize * 116 / 512, style: .continuous)
                    .strokeBorder(DeveloperBrand.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(compact ? .system(size: 14, weight: .semibold) : .headline)
                    .foregroundStyle(DeveloperBrand.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(compact ? .system(size: 12) : .subheadline)
                    .foregroundStyle(DeveloperBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !compact {
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DeveloperBrand.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(DeveloperBrand.accent, in: Capsule())
                    Text("lrvdlinden.app")
                        .font(.caption2)
                        .foregroundStyle(DeveloperBrand.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(compact ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeveloperBrand.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DeveloperBrand.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
