import subprocess
import sys
import os

def run_aeneas(book_abbr, chapter):
    # Updated to .ogg to match Piper output
    audio_file = os.path.abspath(f"assets/audio/{book_abbr}{chapter}.ogg")
    text_file = os.path.abspath(f"assets/sync/{book_abbr}{chapter}_words.txt")
    output_file = os.path.abspath(f"assets/sync/{book_abbr}{chapter}.json")

    # Check if files exist
    if not os.path.exists(audio_file):
        print(f"ERROR: Audio file not found: {audio_file}")
        return
    if not os.path.exists(text_file):
        print(f"ERROR: Word list not found: {text_file}")
        return

    # Configuration string for Aeneas
    config = "task_language=eng|os_task_file_format=json|is_text_type=plain"

    command = [
        sys.executable,
        "-m", "aeneas.tools.execute_task",
        audio_file,
        text_file,
        config,
        output_file
    ]

    print(f"--- Starting Sync for {book_abbr} {chapter} ---")

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            shell=False
        )

        if result.returncode == 0:
            print(f"SUCCESS: {output_file} created.")
        else:
            print(f"AENEAS ERROR (Return Code {result.returncode}):")
            print(result.stdout)
            print(result.stderr)

    except Exception as e:
        print(f"SYSTEM ERROR: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python run_sync.py [BookAbbr] [Chapter]")
    else:
        abbr = sys.argv[1]
        ch = sys.argv[2]
        run_aeneas(abbr, ch)
