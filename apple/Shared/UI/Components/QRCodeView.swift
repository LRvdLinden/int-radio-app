import SwiftUI
#if os(tvOS)
import CoreImage.CIFilterBuiltins

/// Apple TV heeft geen browser: een link wordt een QR-code die je met je telefoon scant.
struct QRCodeView: View {
    let url: URL
    var size: CGFloat = 420

    var body: some View {
        if let image = Self.image(for: url) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .padding(28)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private static func image(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 14, y: 14)) else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }
}

/// Een link die op tv als QR-code wordt getoond (Instellingen → Over, zenderpagina)
struct QRLink: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }

    /// Adres zonder https:// en zonder slot-slash, bv. "tunr.online/privacy"
    static func display(_ url: URL) -> String {
        var s = (url.host ?? "") + url.path
        if s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? url.absoluteString : s
    }
}

/// Schermvullend blad met de QR-code, de titel en het adres; Menu sluit
struct QRLinkSheet: View {
    let link: QRLink

    var body: some View {
        VStack(spacing: 36) {
            Text(link.title).font(.rounded(30, .black)).foregroundStyle(.white)
            QRCodeView(url: link.url)
            Text(QRLink.display(link.url)).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.secondary)
            Text(L("qr.scanHint")).font(Theme.body).foregroundStyle(Theme.secondary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

#if os(tvOS)
/// Apple TV: lange tekst (podcast- of afleveringsomschrijving) schermvullend. Elke alinea kan focus krijgen,
/// zodat je met de afstandsbediening tot het einde scrolt; Menu sluit.
struct TVLongTextSheet: View {
    let title: String
    let text: String

    private var paragraphs: [String] {
        text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(title).font(.rounded(34, .black)).foregroundStyle(.white)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                    TVParagraph(text: p)
                }
            }
            .frame(maxWidth: 1300, alignment: .leading)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct TVParagraph: View {
    let text: String
    @FocusState private var focused: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(focused ? 0.08 : 0)))
            .focusable()
            .focused($focused)
    }
}
#endif
