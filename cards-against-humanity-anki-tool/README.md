# Cards Against Humanity Card Cropper

This project contains a Python script to crop a PDF file containing Cards Against Humanity cards into individual card images.

## Environment Setup

To set up the Python environment for running the card cropping script, follow these steps:

### Prerequisites

- **Python 3**: Ensure Python 3 is installed on your system. You can check this by running `python3 --version` in your terminal. If not installed, download it from [python.org](https://www.python.org/downloads/) or use a package manager like Homebrew on macOS (`brew install python3`).

### Steps to Set Up the Virtual Environment

1. **Create a Virtual Environment**:
   Open a terminal and navigate to the project directory. Then, run the following command to create a virtual environment named `cah_env`:
   ```
   python3 -m venv cah_env
   ```

2. **Activate the Virtual Environment**:
   Activate the virtual environment using the following command:
   ```
   source cah_env/bin/activate  # On macOS/Linux
   ```
   or
   ```
   cah_env\Scripts\activate  # On Windows
   ```

   When activated, you should see `(cah_env)` prefixed to your terminal prompt, indicating you are now working inside the virtual environment.

3. **Install Required Packages**:
   Install the necessary Python packages for PDF processing and image manipulation:
   ```
   pip install pdf2image Pillow
   ```

   - `pdf2image`: Converts PDF pages to images.
   - `Pillow`: Handles image cropping and saving.

   **Note**: On macOS, you may also need to install `poppler` for `pdf2image` to work. You can install it using Homebrew:
   ```
   brew install poppler
   ```

## Running the Scripts

### Cropping Card Images

To crop the cards from the PDF file into individual images:

1. Ensure the PDF file `CAH_PrintPlay2022-RegularInk-FINAL-outlined.pdf` is in the project directory.
2. Run the script:
   ```
   python3 crop_cards.py
   ```

   The script will process the PDF, crop each page into individual card images based on a 5x4 grid with specified margins, and save them in the `cards_output` directory.

### Creating Anki CSV with OpenAI API

To process the card images and generate an Anki CSV file with extracted text, pronunciation, translation, and audio:

1. Set your OpenAI API key as an environment variable to prevent leaking sensitive information:
   ```
   export OPENAI_API_KEY='your-api-key-here'  # On macOS/Linux
   ```
   or
   ```
   set OPENAI_API_KEY=your-api-key-here  # On Windows Command Prompt
   ```
   or
   ```
   $env:OPENAI_API_KEY='your-api-key-here'  # On Windows PowerShell
   ```

2. Run the script:
   ```
   python3 create_anki_cards.py
   ```

   The script will filter card images (currently set to process cards 41 to 45 for testing), use the OpenAI API for text extraction, pronunciation, translation, and audio generation, and create an Anki CSV file at `anki_cards.csv`. Ensure you have activated the virtual environment (`source cah_env/bin/activate` on macOS/Linux or `cah_env\Scripts\activate` on Windows) before running the script.

### Importing into Anki

To import the generated CSV file and associated media (images and audio) into Anki, follow these steps:

1. **Prepare the Files**:
   - Ensure that the `anki_cards.csv` file and the `anki_cards_output` directory (containing the card images and audio files) are in the same location. The CSV file references the media files by name, so they must be accessible to Anki during import.

2. **Open Anki**:
   - Launch the Anki application on your computer. If you don't have Anki installed, download it from [https://apps.ankiweb.net/](https://apps.ankiweb.net/) and install it.

3. **Create or Open a Deck**:
   - Create a new deck or open an existing deck in Anki where you want to import the cards. You can create a new deck by clicking "Create Deck" at the bottom of the Anki main window and naming it (e.g., "Cards Against Humanity").

4. **Import the CSV File**:
   - Go to `File` > `Import` in the Anki menu, or click the "Import File" button at the bottom of the main window.
   - Browse to and select the `anki_cards.csv` file.
   - In the import dialog, ensure the field mapping is correct. Anki should automatically map the CSV columns to fields in a note type. If not, manually map:
     - `Card_Number` to a field (or ignore if not needed).
     - `Image` to a field for media (this will embed the image).
     - `English` to the front of the card or a text field.
     - `Pronunciation` to a field for pronunciation.
     - `Translation` to a field for translation.
     - `Audio` to a field for audio (this will embed the audio file).
   - Choose the appropriate note type if prompted (a "Basic" note type with extra fields or a custom note type may be needed for media).
   - Click "Import" to start the process.

5. **Handle Media Files**:
   - During import, Anki will look for media files referenced in the CSV (images like `card_041.png` and audio like `audio_041.mp3`) in the same directory as the CSV file or in the specified paths. Ensure the `anki_cards_output` directory is in the same location as `anki_cards.csv`, or manually copy the media files to Anki's media folder if needed (located in `~/Library/Application Support/Anki2/User 1/collection.media/` on macOS, or similar paths on other systems).
   - If Anki does not automatically import the media, you may need to manually add the files to the media folder after import and ensure the references in the CSV match the filenames.

6. **Review Imported Cards**:
   - After import, review the cards in your deck to ensure that images, audio, and text fields are correctly displayed. Edit any cards if necessary to adjust formatting or content.

7. **Optional - Create a Package for Sharing**:
   - If you want to share the deck with others, go to `File` > `Export`, select your deck, and choose to include media. This will create an `.apkg` file that includes all images and audio, which can be imported into another Anki instance.

**Note**: If you encounter issues with media not displaying, ensure the file paths in the CSV match the actual filenames and that the files are accessible to Anki. You may need to adjust the CSV content or move files to the correct location.

## Adjusting Margins

If the cropping does not align perfectly with the card boundaries, you can adjust the margin values in the `crop_cards.py` script. Open the script in a text editor and modify the following lines:

```python
margin_top = 20
margin_bottom = 20
margin_left = 20
margin_right = 20
```

Increase or decrease these values (in pixels) to adjust the cropping area, then rerun the script to see the updated results.

## Git Ignore

A `.gitignore` file is included to exclude the virtual environment (`cah_env/`), output directory (`cards_output/`), and other unnecessary files from version control.

## License

This project is for personal use and adheres to the licensing and copyright of the original Cards Against Humanity content.
