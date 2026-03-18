# Authorized King James Version 1611 Pure Cambridge Edition (circa 1900)
### Prevailing KJVersion

A high-precision Bible application built with Flutter, designed for scholarly study, mathematical linguistic analysis, and local-first neural audio synchronization.

**Authors**: Carrille Dione and Charles Eyum Sama  
**Contact**: [holybiblemobileapp@gmail.com](mailto:holybiblemobileapp@gmail.com)  
**License**: © No Rights Reserved

## Philosophy
"Knowing this first, that no prophecy of the scripture is of any private interpretation." (2 Peter 1:20:1-14)

This project is built on the principle that the Scriptures are open to all: "freely ye have received, freely give."(Mat10:8:13-18) The 4-Vector space and mathematical transformations are intended to serve the Word, not to gatekeep it. Knowing Christ is premium.

## Features

### Precision Bible Rendering
- **Multiple Views (5 Versions)**: 
  - **AKJV 1611 PCE**: The standard text with original italics preservation.
  - **Superscript KJV**: Each word is indexed for precise reference, useful for word-level study.
  - **Mathematics KJV 1**: Coming from below(↦), presents the KJV in the Tongue of the Mathematicians using 3 signs: {=,↦,()}.  
  - **Mathematics KJV 2**: Targets isolated function words and the second occurrence in sequences.
  - **Mathematics KJV UNCONSTRAINT**: Replaces all recognized function words and applies recursive "of" mapping.
- **Versification**: Follows BookChapter:Verse:Breadth to present a 4-Vector Space Bible Frame of Reference; used to observe light.
The Versification is the Generalized Coordinate of every word in the Holy Bible. The Breadth is a polynomial parametrization of the 3-D Bible Vector Space (Book, Chapter, Verse). 
- **Dictionary for the Word of God**: Text of Application which gives the Use of Words in the Holy Bible.
- **Radiant Rendering**: Mathematical views are engineered to **simulate text radiating light physically from a black background**. This is achieved through a multi-layered neon glow engine utilizing sharp-core intensity and broad-spectrum emanation.
- **Interactive Audio Activator**: Synchronized local audio playback with word-level highlighting. Tapping any word activates the audio stream from that exact temporal coordinate.
- **Neon Visualizer**: A synchronized waveform display that pulses with the audio signal, rendered with high-intensity light bleed effects to maintain thematic consistency.

### Hierarchical Navigation Grid
- **Book to Chapter**: Selecting a **BOOK** transitions to the **CHAPTER GRID**.
- **Chapter to Verse**: Selecting a **CHAPTER** transitions to the **VERSE GRID**.
- **Instant Verse Access**: Selecting a verse number jumps directly to the reader view.

## Security & Integrity
To protect against app corruption or malicious tampering:
- **Source of Truth**: Always obtain the application from the official repository or trusted distributors.
- **Verification**: If you are distributing the universal APK to others, we recommend sharing the SHA-256 hash of the build to ensure the recipient receives an uncorrupted version of the Word.

## Scalability Roadmap (Implemented)

### 1. High-Fidelity Infrastructure
- **Status**: **COMPLETE**. Performed a repository reset with Git LFS optimization for heavy audio/model assets.
- **Download Service**: Integrated `dio` for on-demand fetching of high/medium quality audio and sync data from GitHub.

### 2. Radiant Rendering Engine
- **Status**: **ACTIVE**. Triple-layered shadow engine (2.0, 12.0, 25.0 blur) for physical light simulation.
- **Pulse Glow**: Active audio fragments trigger a 40.0 blur intensity "pulse" for easier visual tracking.

### 3. Study Hub & Dynamic Constants
- **Status**: **ACTIVE**. Created a persistent gallery for "Mathematical Constants."
- **Search Integration**: Users can discover phrases via **Inverse Relation** search and instantly save them to the gallery with a single tap.

### 4. Audio Engine Refinements
- **Smooth Start**: Implemented a 300ms volume ramp (fade-in) to eliminate start-up audio artifacts.
- **Precision Sync**: Tightened synchronization window to 30ms for closer alignment between voice and highlight.
- **Signature Logic**: Restored authorial signatures (Verse 0) to appear exclusively at the conclusion of Pauline Epistles.

## Production & Installation

### 1. Generate Universal APK (For All Phones)
This command creates a single APK that works on Samsung, Google, and older Android devices.
```powershell
flutter build apk --release --no-shrink --android-skip-build-dependency-validation
# Output location: build/app/outputs/flutter-apk/app-release.apk
```

### 2. Sharing the Application
The universal APK generated above can be shared directly with friends and family:
- **Location**: `build/app/outputs/flutter-apk/app-release.apk`
- **Method**: You can send this file through **WhatsApp**, Email, or Telegram.
- **Installation**: The recipient just needs to open the file on their Android phone to install the app.

### 3. General Installation (To any connected phone via ADB)
If only one phone is plugged in, use this simple command:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r "build/app/outputs/flutter-apk/app-release.apk"
```

### 4. Installation to Specific Device (e.g., Samsung)
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s de5427d7 install -r "build/app/outputs/flutter-apk/app-release.apk"
```

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

## Troubleshooting

### Deep Clean
```powershell
Stop-Process -Name "java" -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android/.gradle
flutter clean
flutter pub get
```
