@echo off
echo --- STARTING GIT SYNC PROCESS ---

:: 1. Set Identity
git config --global user.email "holybiblemobileapp@gmail.com"
git config --global user.name "Charles Eyum Sama"

:: 2. Initialize LFS (Large File Storage)
call git lfs install
git lfs track "assets/audio/*.ogg"
git lfs track "models/*.onnx"

:: 3. Prepare Files
git add .gitattributes
git add .

:: 4. Commit Changes
git commit -m "Final sync: On-Demand architecture and LFS"

:: 5. Ensure branch is main
git branch -M main

:: 6. Force Push to GitHub
echo Uploading to GitHub... This may take time for LFS objects...
git push origin main --force

echo --- PROCESS COMPLETE ---
pause
