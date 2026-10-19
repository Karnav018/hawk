import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key. Play re-signs every release with its own app signing key,
// so this one only proves an upload came from us, and Play Console can reset
// it if it is ever lost. Made by android/make_upload_key.sh, which writes
// android/key.properties. Neither file belongs anywhere but this machine and
// its backup. A CI job points HAWK_KEY_PROPERTIES at its own copy instead.
val uploadKey =
    Properties().apply {
        val file =
            System.getenv("HAWK_KEY_PROPERTIES")?.let(::File)
                ?: rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
val hasUploadKey = uploadKey.getProperty("storeFile") != null

android {
    // Where the R and BuildConfig classes and MainActivity live. Kept equal
    // to applicationId so the project has one name throughout.
    namespace = "in.hawkapp.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The package name Play knows Hawk by: permanent once the first
        // bundle is uploaded. The Firebase Android app and the backend's
        // ANDROID_PACKAGE (subscriptions.py) are registered under it. The
        // manifest's OAuth callback scheme is a separate string and did not
        // have to change with it.
        applicationId = "in.hawkapp.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without the upload key, a release APK still builds for trying
            // on a phone. A Play bundle does not: see the guard below.
            signingConfig =
                signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
            // Ships the native symbol tables inside the bundle, so Play
            // Console can symbolicate native crashes and does not warn that
            // debug symbols are missing.
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
        }
    }
}

flutter {
    source = "../.."
}

// Play refuses a debug-signed bundle, but only once it has been uploaded.
// Stop here instead, with the fix in the message.
gradle.taskGraph.whenReady {
    val bundlingRelease = allTasks.any { it.name == "bundleRelease" }
    if (bundlingRelease && !hasUploadKey) {
        throw GradleException(
            "No upload key: android/key.properties is missing. " +
                "Run android/make_upload_key.sh once, then build again.",
        )
    }
}
