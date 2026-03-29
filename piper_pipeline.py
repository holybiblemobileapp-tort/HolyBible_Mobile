import os
import json
import subprocess
import sys

# --- CONFIGURATION ---
BIBLE_JSON = "assets/Bible.json"
AUDIO_DIR = "assets/audio"
SYNC_DIR = "assets/sync"
MODELS_DIR = "models"

# Quality mapping to your local ONNX files
QUALITY_MODELS = {
    "high": "en_US-lessac-high.onnx",
    "medium": "en_US-lessac-medium.onnx",
    "low": "en_US-lessac-low.onnx"
}

def get_piper_path():
    # Assumes piper is in PATH. If not, provide absolute path here.
    return "piper"

def process_bible(quality="high"):
    if quality not in QUALITY_MODELS:
        print(f"Invalid quality. Choose from: {list(QUALITY_MODELS.keys())}")
        return

    model_path = os.path.join(MODELS_DIR, QUALITY_MODELS[quality])
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found at {model_path}")
        return

    print(f"--- Initiating Full Bible Audio Build ({quality.upper()}) ---")

    with open(BIBLE_JSON, 'r', encoding='utf-8') as f:
        bible_data = json.load(f)

    # Group by Book and Chapter
    chapters = {}
    for entry in bible_data:
        key = (entry['BN'], int(entry['CHAPTER']))
        if key not in chapters:
            chapters[key] = []
        chapters[key].append(entry)

    sorted_keys = sorted(chapters.keys(), key=lambda x: (x[0], x[1]))

    for book_abbr, ch in sorted_keys:
        filename = f"{book_abbr}{ch}"
        audio_out = os.path.join(AUDIO_DIR, f"{filename}.ogg")
        sync_out = os.path.join(SYNC_DIR, f"{filename}.json")
        words_txt = os.path.join(SYNC_DIR, f"{filename}_words.txt")

        # Skip if already exists to allow resuming
        if os.path.exists(audio_out) and os.path.exists(sync_out):
            continue

        print(f"Processing {book_abbr} Chapter {ch}...")

        # 1. Prepare Text
        chapter_verses = sorted(chapters[(book_abbr, ch)], key=lambda x: int(x['VERSE']))
        full_text = ""
        word_list = []
        for v in chapter_verses:
            count = int(v['WORDCOUNT'])
            for i in range(1, count + 1):
                word = v.get(str(i), "").replace("[", "").replace("]", "").replace("¶", "").strip()
                if word:
                    full_text += word + " "
                    word_list.append(word)

        # 2. Run Piper
        try:
            # Piper typically outputs WAV, we pipe to ffmpeg for OGG/Opus (smaller files)
            command = f'echo "{full_text}" | {get_piper_path()} --model {model_path} --output_raw | ffmpeg -f s16le -ar 22050 -ac 1 -i - -c:a libopus -b:a 32k -y {audio_out}'
            subprocess.run(command, shell=True, check=True, capture_output=True)
        except Exception as e:
            print(f"FAILED Piper for {filename}: {e}")
            continue

        # 3. Create Word List for Aeneas
        with open(words_txt, 'w', encoding='utf-8') as f:
            f.write("\n".join(word_list))

        # 4. Run Aeneas Sync (using your existing run_sync.py logic)
        try:
            subprocess.run([sys.executable, "run_sync.py", book_abbr, str(ch)], capture_output=True)
            # Clean up temp word file
            if os.path.exists(words_txt):
                os.remove(words_txt)
        except Exception as e:
            print(f"FAILED Sync for {filename}: {e}")

    print("--- ALL FILES PROCESSED ---")

if __name__ == "__main__":
    quality = sys.argv[1] if len(sys.argv) > 1 else "high"
    process_bible(quality)
