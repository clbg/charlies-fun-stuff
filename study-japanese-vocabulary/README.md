# Study Japanese Vocabulary

This project helps beginners learn Japanese vocabulary by generating Anki cards with Japanese terms, Chinese translations, and example sentences.

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
   ANTHROPIC_API_KEY=your-anthropic-api-key-here
   GOOGLE_ACCESS_TOKEN=your-google-api-key-here
   ```

## Operation Steps

1. **Generate Anki Cards**:
   ```
   mise run generate
   ```
   This generates a CSV file (`output/anki_cards.csv`) formatted for Anki import.

2. **Import into Anki**:
   - Open Anki (download from [https://apps.ankiweb.net/](https://apps.ankiweb.net/) if not installed).
   - Go to `File` > `Import`, select `output/anki_cards.csv`, and map fields as needed.
   - Review imported cards in your chosen deck.

## Notes
- Output files are saved in the `output/` directory.
- Debug mode can be run with `mise run debug`.
- The project venv is managed by mise at `.venv/`; do not recreate the old `sjv_env/`.
