import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Versie/build: in gradle.properties (versie via tools/set_version.py, TUNR_BUILD per build omhoog)
val buildNumber = (findProperty("TUNR_BUILD") as String?)?.toIntOrNull() ?: 1
val marketing = (findProperty("TUNR_VERSION") as String?) ?: "1.0.0"

// Release-sleutel: uit omgevingsvariabelen (CI) of local.properties; nooit in de repo
val localProps = Properties().apply {
    val f = File(rootDir, "local.properties"); if (f.exists()) f.inputStream().use { load(it) }
}
fun key(name: String): String = (System.getenv(name) ?: localProps.getProperty(name) ?: "").trim().replace("\"", "")

android {
    namespace = "nl.lrvdlinden.tunr"
    compileSdk = 35

    defaultConfig {
        applicationId = "nl.lrvdlinden.tunr"
        minSdk = 24
        targetSdk = 35
        versionCode = buildNumber
        versionName = marketing
        vectorDrawables { useSupportLibrary = true }
    }

    // Eigen release-sleutel: TUNR_KEYSTORE (pad), TUNR_KEYSTORE_PASSWORD, TUNR_KEY_ALIAS, TUNR_KEY_PASSWORD.
    // Zonder sleutel wordt de release met de debug-sleutel getekend (zodat CI altijd een installeerbare APK maakt).
    val keystorePath = key("TUNR_KEYSTORE")
    val hasKeystore = keystorePath.isNotEmpty() && file(keystorePath).exists()
    signingConfigs {
        if (hasKeystore) create("tunr") {
            storeFile = file(keystorePath)
            storePassword = key("TUNR_KEYSTORE_PASSWORD")
            keyAlias = key("TUNR_KEY_ALIAS").ifEmpty { "tunr" }
            keyPassword = key("TUNR_KEY_PASSWORD").ifEmpty { key("TUNR_KEYSTORE_PASSWORD") }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hasKeystore) signingConfigs.getByName("tunr") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Lint: alleen ter info, blokkeert de build nooit
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        resources { excludes += listOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES") }
    }
}

// Release-APK heet Tunr-<versie>-build<N>.apk (legacy variant-API, werkt nog in AGP 8.x; CI hernoemt ook zelf)
android.applicationVariants.configureEach {
    val variant = this
    outputs.configureEach {
        if (variant.buildType.name == "release") {
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl).outputFileName =
                "Tunr-${variant.versionName}-build${variant.versionCode}.apk"
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Afspelen: Media3 (ExoPlayer + HLS + OkHttp) en MediaLibraryService (melding, vergrendelscherm, Android Auto)
    val media3 = "1.5.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-session:$media3")

    // Wereldkaart (OpenStreetMap-tegels van CARTO, geen sleutel)
    implementation("org.osmdroid:osmdroid-android:6.1.20")
}
