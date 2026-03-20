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
git commit -m "Sync: Progress on Your Strong Reasons and MathKJV stability"

:: 5. Ensure branch is main
git branch -M main

:: 6. Pull and Push (Safer Sync)
echo Pulling latest changes from GitHub...
git pull origin main --rebase

echo Uploading to GitHub... This may take time for LFS objects...
git push origin main

echo --- PROCESS COMPLETE ---
pause
