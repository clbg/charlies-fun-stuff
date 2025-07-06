# Study Japanese Vocabulary

This project helps beginners learn Japanese vocabulary by generating Anki cards with Japanese terms, Chinese translations, and example sentences.

## Getting Started

### Prerequisites
- **Python 3**: Ensure Python 3 is installed. Check with `python3 --version`. If not installed, download from [python.org](https://www.python.org/downloads/) or use a package manager like Homebrew on macOS (`brew install python3`).

## Environment Setup

1. **Create a Virtual Environment**:
   Navigate to the project directory and run:
   ```
   python3 -m venv sjv_env
   ```

2. **Activate the Virtual Environment**:
   Activate it with:
   ```
   source sjv_env/bin/activate  # On macOS/Linux
   ```
   or
   ```
   sjv_env\Scripts\activate  # On Windows
   ```

3. **Install Required Packages**:
   Install necessary packages:
   ```
   pip install requests beautifulsoup4 pandas
   ```

## Operation Steps

1. **Generate Anki Cards**:
   Ensure the virtual environment is activated, then run:
   ```
   python3 generate_anki_cards.py
   ```
   This generates a CSV file (`output/anki_cards.csv`) formatted for Anki import.

2. **Import into Anki**:
   - Open Anki (download from [https://apps.ankiweb.net/](https://apps.ankiweb.net/) if not installed).
   - Go to `File` > `Import`, select `output/anki_cards.csv`, and map fields as needed.
   - Review imported cards in your chosen deck.

## Notes
- Output files are saved in the `output/` directory.
- Debug mode can be enabled with the `--debug` flag to limit output to 5 rows.
