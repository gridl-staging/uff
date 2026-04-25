import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // processes google-services.json for Firebase
    id("com.google.gms.google-services")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.exists()) {
    FileInputStream(releaseSigningPropertiesFile).use(releaseSigningProperties::load)
}

fun resolveSigningValue(propertyKey: String, environmentKey: String): String? {
    val propertyValue = releaseSigningProperties.getProperty(propertyKey)?.trim()
    if (!propertyValue.isNullOrEmpty()) {
        return propertyValue
    }

    val environmentValue = System.getenv(environmentKey)?.trim()
    if (!environmentValue.isNullOrEmpty()) {
        return environmentValue
    }

    return null
}

val releaseStorePath = resolveSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = resolveSigningValue("storePassword", "ANDROID_STORE_PASSWORD")
val releaseKeyAlias = resolveSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = resolveSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
val hasReleaseSigningConfig = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrEmpty() }

fun isReleaseTaskRequested(): Boolean {
    return gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("release", ignoreCase = true)
    }
}

if (isReleaseTaskRequested() && !hasReleaseSigningConfig) {
    throw GradleException(
        "Release signing config missing. Set key.properties or " +
            "ANDROID_KEYSTORE_PATH, ANDROID_STORE_PASSWORD, " +
            "ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD before running release tasks.",
    )
}

android {
    namespace = "com.gridl.uff"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gridl.uff"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigningConfig) {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    androidTestUtil("androidx.test:orchestrator:1.5.1")
}
