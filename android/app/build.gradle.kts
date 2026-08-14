import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details, kept out of the repository.
//
// android/key.properties holds the path to the keystore and its passwords. It is
// git-ignored and must never be committed: the keystore, with its password, is
// the app's identity. Android installs an update over an existing app only when
// the new package carries the same signing certificate — lose the key and every
// installed copy has to be uninstalled, taking its data with it. See
// key.properties.example for the shape of the file.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKey) load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.stamsofer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Still Flutter's default, and it has to change before the app is
        // published anywhere: after a first store release an applicationId can
        // never be changed again, because it is what makes it the same app.
        // Change it in the same breath as the signing key — both break upgrades
        // of existing installs, so together they cost one uninstall rather than
        // two.
        applicationId = "com.example.stamsofer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Written out rather than taken from flutter.minSdkVersion, which is
        // whatever the installed Flutter happens to say. Left as a reference it
        // rises on its own with every Flutter upgrade, and the writers it locks
        // out are not told: an existing install simply stops being offered
        // updates, silently, because somebody upgraded a toolchain. Android 7.0
        // is the floor this app has shipped on, and moving it should be a
        // decision rather than a side effect.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The real key when it is there, the debug key when it is not, so
            // test builds keep working before the key exists. Which of the two
            // was used is stated at the end of every release build: a build that
            // quietly falls back is exactly how a debug-signed release reaches
            // somebody.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A store artifact is never produced without the real key.
//
// An APK signed with the debug key is fine for testing on a device you control.
// An App Bundle is what goes to Google Play, and Play rejects a debug signature
// anyway — better to fail here, with a sentence saying what to do, than at the
// upload.
project.gradle.taskGraph.whenReady {
    if (!hasReleaseKey) {
        // The exact task, in this module only. Matching by pattern refused
        // every test APK as well: an ordinary assembleRelease drags in
        // bundleReleaseResources here and bundleLibResRelease in each plugin
        // module, and all of them look like "bundle … Release".
        val storeTask = allTasks.firstOrNull {
            it.name == "bundleRelease" && it.project.path == project.path
        }
        if (storeTask != null) {
            throw GradleException(
                "\n" +
                    "Refusing to build a release bundle without a signing key.\n" +
                    "\n" +
                    "android/key.properties is missing, so this build would be signed with\n" +
                    "the debug key. Google Play rejects that, and any device that installed\n" +
                    "a debug-signed build cannot be updated by a properly signed one without\n" +
                    "uninstalling first, which deletes the user's data.\n" +
                    "\n" +
                    "Create the keystore, then copy android/key.properties.example to\n" +
                    "android/key.properties and fill it in.\n" +
                    "See DOCUMENTATION.md, section 11 — before a release build.\n"
            )
        }
    }
}

// Says which key signed the build, every time, so it is never a surprise.
tasks.matching { it.name.startsWith("assembleRelease") }.configureEach {
    doLast {
        if (hasReleaseKey) {
            logger.lifecycle(
                "Signed with the release key from android/key.properties."
            )
        } else {
            // error rather than warn: `flutter build` filters Gradle's output
            // and a warning does not reach the terminal.
            logger.error(
                "\n*** This release APK is signed with the DEBUG key. Fine for testing on\n" +
                    "*** a device you control; not fit to publish, and it cannot later be\n" +
                    "*** replaced by a properly signed build without uninstalling first.\n"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
