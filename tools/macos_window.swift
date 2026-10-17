// Venster van een draaiende app vinden (voor App Store-schermafbeeldingen op de Mac, workflow *App Store media*).
// Gebruik: swift tools/macos_window.swift Tunr  →  "<windowid> <x> <y> <breedte> <hoogte>" (punten), of exit 1.
// Alleen de eigenaar (kCGWindowOwnerName) is nodig: daarvoor is geen schermopname-toestemming vereist.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tunr"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

var best: (id: Int, rect: CGRect)?
for w in info {
    guard (w[kCGWindowOwnerName as String] as? String) == owner,
          (w[kCGWindowLayer as String] as? Int) == 0,
          let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
    if r.width < 400 || r.height < 300 { continue }
    if best == nil || r.width * r.height > best!.rect.width * best!.rect.height { best = (id, r) }
}

guard let best else {
    FileHandle.standardError.write("geen venster van \(owner)\n".data(using: .utf8)!)
    exit(1)
}
print("\(best.id) \(Int(best.rect.minX)) \(Int(best.rect.minY)) \(Int(best.rect.width)) \(Int(best.rect.height))")
