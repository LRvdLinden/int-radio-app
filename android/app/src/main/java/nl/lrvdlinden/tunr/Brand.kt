package nl.lrvdlinden.tunr

/**
 * De (werk)naam "Tunr" en alles wat ermee samenhangt staat alleen hier (plus de teksten in res/values*).
 * Bij een nieuwe naam volstaat zoek-en-vervang op "Tunr".
 */
object Brand {
    const val NAME = "Tunr"
    const val APP_ID = "nl.lrvdlinden.tunr"

    /** Website (placeholder tot het domein live is) */
    const val WEBSITE = "https://tunr.online"
    /** Privacy en voorwaarden: pagina's uit website/ (privacy/, voorwaarden/) */
    const val PRIVACY = "https://tunr.online/privacy/"
    const val TERMS = "https://tunr.online/voorwaarden/"
    const val RADIO_BROWSER = "https://www.radio-browser.info"

    /**
     * Anonieme gebruiksstatistieken (BeheerTunr, zie tunr-beheer/docs/CONTRACT.md): Supabase-URL
     * (`https://<project-ref>.supabase.co`) en publishable key (`sb_publishable_…`). Openbaar, mag in de repo.
     * Zolang de URL leeg is, stuurt de app geen ping.
     */
    const val STATS_URL = "https://vbhkewgyujzgbukkbtml.supabase.co"
    const val STATS_KEY = "sb_publishable_0Fp86h5uCovv00KReb3Pvg_lTH7TwU6"

    /** Versie zonder buildnummer, zoals in de User-Agent ("Tunr/1.0.0") */
    val version: String get() = BuildConfig.VERSION_NAME

    /** Eigen User-Agent voor Radio Browser, iTunes, de streams en de kaarttegels (verplicht, zie CLAUDE.md) */
    val userAgent: String
        get() = "$NAME/$version ($APP_ID; ${if (Device.isTV) "AndroidTV" else "Android"})"
}
