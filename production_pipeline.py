import os
import json
import subprocess
import base64
import requests

# --- CONFIGURATION ---
API_KEY = os.environ.get("ELEVENLABS_API_KEY", "your_api_key_here")
VOICE_ID = "JBFqnCBsd6RMkjVDRZzb"

BIBLE_JSON_PATH = "assets/Bible.json"
OUTPUT_AUDIO_DIR = "assets/audio"
OUTPUT_SYNC_DIR = "assets/sync"
TEMP_DIR = "production/temp"

def ensure_dirs():
    for d in [OUTPUT_AUDIO_DIR, OUTPUT_SYNC_DIR, TEMP_DIR]:
        os.makedirs(d, exist_ok=True)

def get_chapter_text(book_abbr, chapter):
    if not os.path.exists(BIBLE_JSON_PATH):
        print(f"Error: {BIBLE_JSON_PATH} not found.")
        return None
    with open(BIBLE_JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    chapter_verses = [v for v in data if v.get('BN') == book_abbr and int(v.get('CHAPTER', 0)) == chapter]
    chapter_verses.sort(key=lambda x: int(x.get('VERSE', 0)))

    full_text = []
    for v in chapter_verses:
        word_count = int(v.get('WORDCOUNT', 0))
        verse_text = " ".join([v.get(str(i), "").replace("[", "").replace("]", "") for i in range(1, word_count + 1)])
        full_text.append(verse_text)
    return " ".join(full_text)

def generate_voice_with_timestamps(text, filename, voice_id):
    if API_KEY == "your_api_key_here":
        print("Error: ELEVENLABS_API_KEY environment variable not set.")
        return None, None

    print(f"Generating high-quality voice for {filename}...")
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}/with-timestamps"
    headers = {"Content-Type": "application/json", "xi-api-key": API_KEY}
    data = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}
    }
    response = requests.post(url, json=data, headers=headers)

    if response.status_code != 200:
        print(f"Error from ElevenLabs: {response.text}")
        return None, None

    resp = response.json()
    audio_bytes = base64.b64decode(resp['audio_base64'])
    temp_mp3 = os.path.join(TEMP_DIR, f"{filename}.mp3")
    with open(temp_mp3, "wb") as f:
        f.write(audio_bytes)

    alignment = resp['alignment']
    chars, starts, ends = alignment['characters'], alignment['character_start_times_seconds'], alignment['character_end_times_seconds']
    word_sync, current_word, word_start = [], "", 0.0
    for i, char in enumerate(chars):
        if char.isspace():
            if current_word:
                word_sync.append({"begin": word_start, "end": ends[i-1], "label": current_word})
                current_word = ""
        else:
            if not current_word: word_start = starts[i]
            current_word += char
    if current_word: word_sync.append({"begin": word_start, "end": ends[-1], "label": current_word})
    return temp_mp3, word_sync

def encode_to_ogg(input_audio, output_ogg):
    print(f"Encoding {output_ogg} (High Quality Opus)...")
    try:
        # Resample to 48kHz for libopus compatibility and set bitrate to 64k
        subprocess.run(["ffmpeg", "-i", input_audio, "-ar", "48000", "-c:a", "libopus", "-b:a", "64k", "-vbr", "on", "-y", output_ogg], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        print(f"Error encoding to ogg: {e}")
    except FileNotFoundError:
        print("Error: ffmpeg not found in PATH.")

def process_chapter(book_abbr, chapter):
    ensure_dirs()
    text = get_chapter_text(book_abbr, chapter)
    if not text: return

    temp_mp3, word_sync = generate_voice_with_timestamps(text, f"{book_abbr}{chapter}", VOICE_ID)

    if temp_mp3 and word_sync:
        filename = f"{book_abbr}{chapter}"
        encode_to_ogg(temp_mp3, os.path.join(OUTPUT_AUDIO_DIR, f"{filename}.ogg"))
        with open(os.path.join(OUTPUT_SYNC_DIR, f"{filename}.json"), 'w') as f:
            json.dump(word_sync, f)
        print(f"\nSUCCESS: Produced {filename}.ogg and {filename}.json")

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 2:
        process_chapter(sys.argv[1], int(sys.argv[2]))
    else:
        print("Usage: python production_pipeline.py <BookAbbr> <Chapter>")
