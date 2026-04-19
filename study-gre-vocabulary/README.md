# Study GRE Vocabulary

This project helps students learn GRE vocabulary by generating Anki cards with GRE words, definitions, and example sentences.

## Features

- Converts GRE vocabulary CSV files to Anki-compatible format
- Generates example sentences and definitions using AI
- Supports audio generation for pronunciation
- Filters words by difficulty level or category
- Deduplication to avoid processing existing cards

## Getting Started

### Prerequisites
- `mise`

## Environment Setup

1. **Install the configured runtime**:
   ```
   mise install
   ```

2. **Install Python dependencies**:
   ```
   mise run install
   ```

3. **Configure API Keys**:
   Copy the .env.example file to .env and add your API keys:
   ```
   cp .env.example .env
   ```
   Then edit the .env file to add your API keys:
   ```
   OPENAI_API_KEY=your-openai-api-key-here
   GOOGLE_ACCESS_TOKEN=your-google-api-key-here
   ```

## CSV Format

Your GRE vocabulary CSV should have the following columns:
- `Word`: The GRE word
- `Definition`: Basic definition (optional, will be enhanced by AI)
- `Category`: Word category (e.g., "High Frequency", "Math", "Science")
- `Difficulty`: Difficulty level (e.g., 1-5 or "Easy", "Medium", "Hard")

Example CSV format:
```csv
Word,Definition,Category,Difficulty
aberrant,departing from an established course,High Frequency,3
abscond,leave hurriedly and secretly,High Frequency,4
```

## Operation Steps

1. **Place your CSV file** in the project directory (e.g., `gre_vocab.csv`)

2. **Generate Anki Cards**:
   ```
   mise run generate
   ```
   This generates a CSV file (`output/anki_cards.csv`) formatted for Anki import.

3. **Debug Mode**:
   To test with a limited number of words:
   ```
   mise run debug
   ```

4. **Import into Anki**:
   - Open Anki (download from [https://apps.ankiweb.net/](https://apps.ankiweb.net/) if not installed).
   - Go to `File` > `Import`, select `output/anki_cards.csv`, and map fields as needed.
   - Review imported cards in your chosen deck.

## GRE Vocabulary Word List
We are downloading wordlist form github link
https://github.com/Xatta-Trone/gre-words-collection/tree/main/word-list

## Notes
- Output files are saved in the `output/` directory.
- Audio files are saved in `output/audio/` directory.
- The script will skip words that have already been processed.
- Debug mode can be run with `mise run debug`.
- The project venv is managed by mise at `.venv/`; do not recreate the old `gre_env/` or `sgv_env/`.
