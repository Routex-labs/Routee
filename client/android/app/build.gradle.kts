plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.navigation.navigation_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.navigation.navigation_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // AGP 9는 release에서 R8을 기본으로 돌린다. ONNX Runtime은 JNI로
            // 클래스를 이름으로 찾으므로 keep 규칙 없이는 추론 첫 호출에서
            // 죽는다. 자세한 근거는 proguard-rules.pro 주석 참고.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Android 전용 RoNIN 비교 경로의 온디바이스 추론 런타임.
    // iOS/Flutter 의존성에는 포함하지 않아 실험 범위를 Android로 제한한다.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.27.0")
    // FusedOrientationProvider(21.1.0+). 벤더 TYPE_ROTATION_VECTOR 대신 구글이
    // 원시 센서에서 다시 융합한 자세를 heading에만 쓴다. 실측 근거는
    // docs/pdr/pdr-dev-integration.md "Android 방향 소스를 FOP로 옮긴 근거".
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
