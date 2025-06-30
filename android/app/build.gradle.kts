import java.io.FileInputStream
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

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.sparta.colortrip"
    compileSdk = flutter.compileSdkVersion

    // 1. NDK 버전 불일치 문제 해결:
    // 플러그인들이 요구하는 NDK 버전(27.0.12077973)으로 명시적으로 설정합니다.
    ndkVersion = "27.0.12077973" // flutter.ndkVersion 대신 명시적인 버전으로 변경

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_colortrip_app"
        // 2. minSdkVersion 불일치 문제 해결:
        // Firebase 등 플러그인들이 요구하는 최소 SDK 버전 23으로 설정합니다.
        minSdk = 23 // flutter.minSdkVersion 대신 23으로 명시
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // keystoreProperties에서 값을 가져올 때 null 안전하게 처리하고,
            // 없는 경우를 대비하여 환경 변수를 폴백으로 사용하도록 개선합니다.
            // 또한, String으로 캐스팅하는 부분에서 발생할 수 있는 잠재적 오류를 방지하기 위해 getProperty를 사용합니다.

            keyAlias = keystoreProperties.getProperty("keyAlias") ?: System.getenv("FLUTTER_BUILD_KEY_ALIAS")
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: System.getenv("FLUTTER_BUILD_KEY_PASSWORD")
            
            storeFile = if (keystoreProperties.containsKey("storeFile")) {
                file(keystoreProperties.getProperty("storeFile"))
            } else {
                // 환경 변수에서 가져올 수도 있습니다.
                System.getenv("FLUTTER_BUILD_STORE_FILE")?.let { file(it) }
            }
            storePassword = keystoreProperties.getProperty("storePassword") ?: System.getenv("FLUTTER_BUILD_STORE_PASSWORD")

            // 선택 사항: 필수 서명 정보가 없는 경우 빌드 실패 처리
            if (keyAlias == null) throw GradleException("keyAlias not found for release signing. Check key.properties or FLUTTER_BUILD_KEY_ALIAS env var.")
            if (keyPassword == null) throw GradleException("keyPassword not found for release signing. Check key.properties or FLUTTER_BUILD_KEY_PASSWORD env var.")
            if (storeFile == null) throw GradleException("storeFile not found for release signing. Check key.properties or FLUTTER_BUILD_STORE_FILE env var.")
            if (storePassword == null) throw GradleException("storePassword not found for release signing. Check key.properties or FLUTTER_BUILD_STORE_PASSWORD env var.")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // 릴리스 빌드에 일반적으로 추가하는 옵션들 (선택 사항)
            isShrinkResources = true // 사용하지 않는 리소스 제거
            isMinifyEnabled = true   // 코드 난독화 및 최적화
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), // 최적화된 프로가드 기본 파일
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}