import os
import json
import subprocess
import sys
import shutil

# --- CONFIGURATION ---
PIPER_EXE_PATH = r"C:\piper\piper\piper.exe"

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

def find_executable(name, manual_path=None):
    if manual_path and os.path.exists(manual_path):
        return manual_path
    path = shutil.which(name)
    if not path and os.name == 'nt':
        path = shutil.which(f"{name}.exe")
    return path

def process_bible(quality="medium"):
    if quality not in QUALITY_MODELS:
        print(f"Invalid quality. Choose from: {list(QUALITY_MODELS.keys())}")
        return

    model_path = os.path.abspath(os.path.join(MODELS_DIR, QUALITY_MODELS[quality]))
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found at {model_path}")
        return

    piper_exe = find_executable("piper", PIPER_EXE_PATH)
    ffmpeg_exe = find_executable("ffmpeg")

    if not piper_exe:
        print("ERROR: 'piper' executable not found.")
        return
    if not ffmpeg_exe:
        print("ERROR: 'ffmpeg' executable not found.")
        return

    print(f"--- Initiating Full Bible Audio Build ({quality.upper()}) ---")

    if not os.path.exists(AUDIO_DIR): os.makedirs(AUDIO_DIR)
    if not os.path.exists(SYNC_DIR): os.makedirs(SYNC_DIR)

    with open(BIBLE_JSON, 'r', encoding='utf-8') as f:
        bible_data = json.load(f)

    chapters = {}
    for entry in bible_data:
        book_abbr = entry.get('BN', '')
        ch_raw = entry.get('CHAPTER', '0')
        try: ch_num = int(ch_raw)
        except: ch_num = 0
        key = (book_abbr, ch_num)
        if key not in chapters: chapters[key] = []
        chapters[key].append(entry)

    sorted_keys = sorted(chapters.keys(), key=lambda x: (int(chapters[x][0].get('BKORDER', 0)), x[1]))

    for book_abbr, ch in sorted_keys:
        filename = f"{book_abbr}{ch}"
        audio_out = os.path.abspath(os.path.join(AUDIO_DIR, f"{filename}.ogg"))
        sync_out = os.path.abspath(os.path.join(SYNC_DIR, f"{filename}.json"))
        words_txt = os.path.abspath(os.path.join(SYNC_DIR, f"{filename}_words.txt"))

        if os.path.exists(audio_out) and os.path.exists(sync_out):
            continue

        print(f"Processing {book_abbr} Chapter {ch}...")

        chapter_verses = sorted(chapters[(book_abbr, ch)], key=lambda x: int(x.get('VERSE', 0)))
        full_text = ""
        word_list = []
        for v in chapter_verses:
            count_raw = v.get('WORDCOUNT', '0')
            try: count = int(count_raw)
            except: count = 0
            for i in range(1, count + 1):
                word = v.get(str(i), "").replace("[", "").replace("]", "").replace("¶", "").strip()
                if word:
                    full_text += word + " "
                    word_list.append(word)

        if not full_text.strip(): continue

        try:
            # FIX: Use shell=True or direct piping without .communicate() reading the stdout
            # Piper outputs raw 22050Hz mono s16le
            piper_cmd = f'"{piper_exe}" --model "{model_path}" --output_raw'
            # FFmpeg: resample to 48k (Opus standard) and use higher bitrate (64k) for crystal clear Opus
            # Note: libopus does not support 44100Hz.
            ffmpeg_cmd = f'"{ffmpeg_exe}" -f s16le -ar 22050 -ac 1 -i - -ar 48000 -c:a libopus -b:a 64k -y "{audio_out}"'

            # Combine them into a single shell pipe to avoid Python stream corruption
            full_cmd = f'{piper_cmd} | {ffmpeg_cmd}'

            process = subprocess.Popen(full_cmd, shell=True, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
            _, stderr = process.communicate(input=full_text.encode('utf-8'))

            if process.returncode != 0:
                print(f"FAILED {filename}: {stderr.decode()}")
                continue

        except Exception as e:
            print(f"SYSTEM ERROR for {filename}: {e}")
            continue

        # Run Aeneas Sync
        with open(words_txt, 'w', encoding='utf-8') as f:
            f.write("\n".join(word_list))

        try:
            subprocess.run([sys.executable, "run_sync.py", book_abbr, str(ch)], capture_output=True)
            if os.path.exists(words_txt): os.remove(words_txt)
        except:
            print(f"Sync FAILED for {filename}")

    print("--- ALL FILES PROCESSED ---")

if __name__ == "__main__":
    quality = sys.argv[1] if len(sys.argv) > 1 else "medium"
    process_bible(quality)
