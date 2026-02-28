# Authorized King James Version 1611 Pure Cambridge Edition (circa 1900)

A high-precision Bible application built with Flutter, designed for scholarly study, mathematical linguistic analysis, and local-first neural audio synchronization.

**Authors**: Carrille Dione and Charles Eyum Sama  
**Contact**: [holybiblemobileapp@gmail.com](mailto:holybiblemobileapp@gmail.com)  
**License**: © No Rights Reserved

## Features

### Precision Bible Rendering
- **Multiple Views (5 Versions)**: 
  - **AKJV 1611 PCE**: The standard text with original italics preservation.
  - **Superscript KJV**: Each word is indexed for precise reference, useful for word-level study.
  - **Mathematics KJV 1**: Presents the KJV in the Tongue of the Mathematicians using 3 signs: {=,↦,()}.  
  - **Mathematics KJV 2**: Targets isolated function words and the second occurrence in sequences.
  - **Mathematics KJV UNCONSTRAINT**: Replaces all recognized function words and applies recursive "of" mapping.
- **Radiant Rendering**: Mathematical views are engineered to **simulate text radiating light physically from a black background**. This is achieved through a multi-layered neon glow engine utilizing sharp-core intensity and broad-spectrum emanation.
- **Interactive Audio Activator**: Synchronized local audio playback with word-level highlighting. Tapping any word activates the audio stream from that exact temporal coordinate.

### Hierarchical Navigation Grid
- **Book to Chapter**: Selecting a **BOOK** transitions to the **CHAPTER GRID**.
- **Chapter to Verse**: Selecting a **CHAPTER** transitions to the **VERSE GRID**.
- **Instant Verse Access**: Selecting a verse number jumps directly to the reader view.

## Scalability Roadmap (Implemented)

As the project expands from 2 books (Genesis/Preface) to all 66 books, the following architecture is now in place:

### 1. On-Demand Asset Management
- **Status**: **ACTIVE**. Audio and Sync files are excluded from the APK bundle to ensure a lean, fast install.
- **Logic**: `AudioService` checks `getApplicationDocumentsDirectory()` for files first.
- **Next Step**: Implement the `DownloadService` using `dio` to fetch books from the remote repository as needed.

### 2. Database Optimization
- **Goal**: Move Lesson Notes and Courses into a **SQLite database**.

## Git & Version Control

### Initial Setup
```powershell
git init
git lfs install
git lfs track "assets/audio/*.ogg"
git lfs track "models/*.onnx"
git lfs track "assets/Bible.json"
git add .
git commit -m "Initial commit: Holy Bible Mobile with LFS optimization"
git remote add origin https://github.com/holybiblemobileapp-tort/HolyBible_Mobile
git push -u origin main --force
```

## Production & Troubleshooting

### Standard APK Generation
```powershell
flutter build apk --release --no-shrink --android-skip-build-dependency-validation
```

### Direct Gradle Build (Recommended if standard fails)
```powershell
cd android
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat assembleRelease
cd ..
# Output: android/app/build/outputs/apk/release/app-release.apk
```

### Installation to Device
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s de5427d7 install -r "android/app/build/outputs/apk/release/app-arm64-v8a-release.apk"
```

### Deep Clean
```powershell
Stop-Process -Name "java" -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android/.gradle
flutter clean
flutter pub get
```
