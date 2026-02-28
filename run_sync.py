import subprocess
import sys
import os

def run_aeneas(book_abbr, chapter):
    # Ensure paths are absolute and quoted
    audio_file = os.path.abspath(f"assets/audio/{book_abbr}{chapter}.mp3")
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

    # Build the command list.
    # On Windows, using subprocess without shell=True and with a list
    # is the safest way to avoid pipe character issues.
    command = [
        sys.executable,
        "-m", "aeneas.tools.execute_task",
        audio_file,
        text_file,
        config,
        output_file
    ]

    print(f"--- Starting Sync for {book_abbr} {chapter} ---")
    print(f"Audio: {audio_file}")
    print(f"Text:  {text_file}")

    try:
        # Run without shell=True to prevent cmd.exe from misinterpreting '|'
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
    # Get arguments from command line
    if len(sys.argv) < 3:
        print("Usage: python run_sync.py [BookAbbr] [Chapter]")
        print("Example: python run_sync.py Gen 1")
    else:
        abbr = sys.argv[1]
        ch = sys.argv[2]
        run_aeneas(abbr, ch)
