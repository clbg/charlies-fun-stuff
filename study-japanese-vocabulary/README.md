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
   Install necessary packages using the requirements.txt file:
   ```
   pip install -r requirements.txt
   ```

4. **Configure API Keys**:
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

### Manage Environment Variables with direnv

`direnv` is a tool that loads/unloads environment variables automatically per directory. This is useful for managing project-specific configurations like `PYTHONPATH`.

**Installation:**

*   **macOS (using Homebrew):**
    ```bash
    brew install direnv
    ```
*   **Other Systems:** Refer to the official `direnv` installation guide: [https://direnv.net/docs/installation.html](https://direnv.net/docs/installation.html)

**Enable direnv:**

After installing `direnv`, you need to hook it into your shell. Add the following line to your shell's configuration file (e.g., `~/.zshrc` for zsh, `~/.bashrc` for bash):

```bash
eval "$(direnv hook zsh)" # Or 'eval "$(direnv hook bash)"' for bash
```
Then, restart your shell or source your configuration file (e.g., `source ~/.zshrc`).

**Usage:**

Create a `.envrc` file in your project's root directory and add your environment variables. For example, to set `PYTHONPATH` to include `common_modules`:

```bash
export PYTHONPATH=$PYTHONPATH:./common_modules
```
After creating or modifying `.envrc`, run `direnv allow` in the terminal within that directory to load the variables.
