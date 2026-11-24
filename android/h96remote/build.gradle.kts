// H96 Remote: isolated Android TV remote module (docs/architecture/H96_REMOTE.md).
// Pure Java, no third-party dependencies, so it can move to its own app unchanged.
plugins {
    id("com.android.library")
}

android {
    namespace = "app.deterministic.todo.h96remote"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
