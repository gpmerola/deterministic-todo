plugins {
    id("com.android.library")
}

android {
    namespace = "app.deterministic.todo.runtracker"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.room:room-runtime:2.7.2")
    implementation("androidx.work:work-runtime:2.10.2")
    implementation("com.google.android.gms:play-services-fitness:21.2.0")
    annotationProcessor("androidx.room:room-compiler:2.7.2")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
