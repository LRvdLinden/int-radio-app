package nl.lrvdlinden.tunr

/**
 * De (werk)naam "Tunr" en alles wat ermee samenhangt staat alleen hier (plus de teksten in res/values*).
 * Bij een nieuwe naam volstaat zoek-en-vervang op "Tunr".
 */
object Brand {
    const val NAME = "Tunr"
    const val APP_ID = "nl.lrvdlinden.tunr"

    /** Website (placeholder tot het domein live is) */
    const val WEBSITE = "https://github.com/LRvdLinden/int-radio-app"
    /** Privacy en voorwaarden: pagina's uit website/ (privacy/, voorwaarden/) */
    const val PRIVACY = "https://tunr.app/privacy/"
    const val TERMS = "https://tunr.app/voorwaarden/"
    const val RADIO_BROWSER = "https://www.radio-browser.info"

    /** Versie zonder buildnummer, zoals in de User-Agent ("Tunr/1.0.0") */
    val version: String get() = BuildConfig.VERSION_NAME

    /** Eigen User-Agent voor Radio Browser, iTunes, de streams en de kaarttegels (verplicht, zie CLAUDE.md) */
    val userAgent: String
        get() = "$NAME/$version ($APP_ID; ${if (Device.isTV) "AndroidTV" else "Android"})"
}
