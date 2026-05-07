import java.io.FileOutputStream
import java.net.URL
import java.security.MessageDigest

group = "com.alesdrnz.mpv_audio_kit"
version = "0.0.8"

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.alesdrnz.mpv_audio_kit"

    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags("")
                arguments("-DANDROID_STL=c++_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}

val MPV_RELEASE_VERSION = "libmpv-r4"
val MPV_BASE_URL = "https://github.com/ales-drnz/mpv_audio_kit/releases/download/${MPV_RELEASE_VERSION}"

val downloadMpvTask = tasks.register("downloadMpvLibraries") {
    val abis = mapOf(
        "arm64-v8a" to mapOf(
            "file" to "libmpv_android-arm64-v8a.so",
            "sha256" to "9a7af86a272c2980e613528b18b96c1d803a1907731f1da07117facedb4063ee"
        ),
        "x86_64" to mapOf(
            "file" to "libmpv_android-x86_64.so",
            "sha256" to "ad2ca3c99bf4f4f7b1cdd21c1f81b2ce2df3279dc62c50b18a31fa84fe9cdfbc"
        )
    )

    doLast {
        val jniLibsDir = file("src/main/jniLibs")
        val abiFilters = android.defaultConfig.ndk.abiFilters.ifEmpty { abis.keys }
        abis.filter { it.key in abiFilters }.forEach { (abi, info) ->
            val filename = info["file"]!!
            val expectedHash = info["sha256"]!!
            val abiDir = file("${jniLibsDir}/${abi}")
            if (!abiDir.exists()) abiDir.mkdirs()

            val targetFile = file("${abiDir}/libmpv.so")
            var isValid = false

            if (targetFile.exists()) {
                val bytes = targetFile.readBytes()
                val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
                val calculatedHash = digest.joinToString("") { "%02x".format(it) }
                if (calculatedHash == expectedHash) {
                    isValid = true
                } else {
                    println("SHA-256 mismatch for ${abi}. Expected: ${expectedHash}, Got: ${calculatedHash}")
                    targetFile.delete()
                }
            }

            if (!isValid) {
                val url = "${MPV_BASE_URL}/${filename}"
                println("Downloading libmpv.so for ${abi} from ${url}")
                try {
                    URL(url).openStream().use { input ->
                        FileOutputStream(targetFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    val bytes = targetFile.readBytes()
                    val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
                    val calculatedHash = digest.joinToString("") { "%02x".format(it) }

                    if (calculatedHash != expectedHash) {
                        targetFile.delete()
                        throw GradleException("SHA-256 verification failed for downloaded ${filename}!")
                    }
                } catch (e: Exception) {
                    println("Failed to download libmpv.so for ${abi}: ${e.message}")
                    if (targetFile.exists()) targetFile.delete()
                }
            }
        }
    }
}

tasks.configureEach {
    if (name.contains("preBuild") || name.contains("externalNativeBuild")) {
        dependsOn(downloadMpvTask)
    }
}
