import csv
from dataclasses import dataclass
from typing import List, Optional
import os
import argparse
import requests
import json
import base64
import glob

# Constants
OUTPUT_DIR = "output"
AUDIO_DIR = os.path.join(OUTPUT_DIR, "audio")
DEFAULT_CSV_PATH = os.path.join(OUTPUT_DIR, "anki_cards.csv")
DEBUG_CSV_PATH = os.path.join(OUTPUT_DIR, "anki_cards_debug.csv")
CSV_HEADERS = [
    "Word", "Definition", "Example_Sentence", "Etymology", "Synonyms", 
    "Antonyms", "Memory_Tips", "Audio_Path"
]
INPUT_CSV_PATH = "gre_vocab.csv"
CATEGORY_INPUT_PROMPT = "Enter categories to filter (comma-separated, e.g., High Frequency,Math): "
DIFFICULTY_INPUT_PROMPT = "Enter difficulty levels to filter (comma-separated, e.g., 3,4,5): "

@dataclass
class VocabularyItem:
    """Common schema for vocabulary items that will be processed through all steps"""
    word: str
    definition: str
    category: str
    difficulty: str
    example_sentence: Optional[str] = None
    etymology: Optional[str] = None
    synonyms: Optional[str] = None
    antonyms: Optional[str] = None
    memory_tips: Optional[str] = None
    audio_path: Optional[str] = None

class VocabularyProcessor:
    """Base class for all processing steps"""
    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        raise NotImplementedError

class CategoryFilter(VocabularyProcessor):
    """Filter vocabulary by category"""
    def __init__(self, categories: List[str]):
        self.categories = [cat.strip() for cat in categories]

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        if not self.categories:
            return items
        return [item for item in items if item.category in self.categories]

class DifficultyFilter(VocabularyProcessor):
    """Filter vocabulary by difficulty level"""
    def __init__(self, difficulties: List[str]):
        self.difficulties = [str(diff).strip() for diff in difficulties]

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        if not self.difficulties:
            return items
        return [item for item in items if str(item.difficulty) in self.difficulties]

class ContentEnhancer(VocabularyProcessor):
    """Enhance vocabulary content using OpenAI API"""
    def __init__(self):
        self.api_key = os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set. Please set it before running the script.")
        self.endpoint = "https://api.openai.com/v1/chat/completions"
        self.model = "gpt-4"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.example_sentence:
                print(f"Processing item {i}/{total_items}: Enhancing content for '{item.word}'")
                prompt = f"""
You are a GRE vocabulary tutor. Please return ONLY valid JSON without any extra text or markdown code blocks.
Return content that satisfies the following schema and constraints:

### JSON Schema
{{
  "enhanced_definition": string,    // Clear, comprehensive definition (20-40 words)
  "example_sentence": string,       // Natural sentence using the word (15-25 words)
  "etymology": string,              // Word origin and root meaning (10-20 words)
  "synonyms": string,               // 3-5 synonyms, comma-separated
  "antonyms": string,               // 3-5 antonyms, comma-separated
  "memory_tips": string             // Mnemonic or memory aid (15-30 words)
}}

### Constraints
1. **enhanced_definition**: Must be clearer and more comprehensive than the basic definition
2. **example_sentence**: Must use the target word naturally and show its meaning in context
3. **etymology**: Include root words, language origin, and how meaning developed
4. **synonyms/antonyms**: Provide words of similar difficulty level, comma-separated
5. **memory_tips**: Create memorable associations, wordplay, or visual imagery
6. **All fields**: Must be complete, accurate, and appropriate for GRE level

### Self-check (execute immediately after generation)
- [ ] Confirm only one top-level JSON object
- [ ] All fields are non-empty strings
- [ ] JSON can be parsed by json.loads()
- [ ] Content is appropriate for GRE vocabulary study

### Task Input
Target word: "{item.word}"
Basic definition: "{item.definition}"
Category: "{item.category}"
"""

                payload = {
                    "model": self.model,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "max_tokens": 600
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        response_data = response.json()
                        content = response_data['choices'][0]['message']['content'].strip()
                        print(f"Received response for '{item.word}': {content[:100]}...")
                        try:
                            json_data = json.loads(content)
                            item.definition = json_data.get('enhanced_definition', item.definition)
                            item.example_sentence = json_data.get('example_sentence', f"Failed to generate example for {item.word}")
                            item.etymology = json_data.get('etymology', f"Failed to generate etymology for {item.word}")
                            item.synonyms = json_data.get('synonyms', f"Failed to generate synonyms for {item.word}")
                            item.antonyms = json_data.get('antonyms', f"Failed to generate antonyms for {item.word}")
                            item.memory_tips = json_data.get('memory_tips', f"Failed to generate memory tips for {item.word}")
                            
                            print(f"Enhanced content for '{item.word}': Definition updated, example generated")
                        except json.JSONDecodeError as jde:
                            item.example_sentence = f"Failed to parse JSON for {item.word}"
                            item.etymology = f"Failed to parse etymology for {item.word}"
                            item.synonyms = f"Failed to parse synonyms for {item.word}"
                            item.antonyms = f"Failed to parse antonyms for {item.word}"
                            item.memory_tips = f"Failed to parse memory tips for {item.word}"
                            print(f"JSON parsing error for '{item.word}': {str(jde)}")
                    else:
                        item.example_sentence = f"API error for {item.word} (status {response.status_code})"
                        print(f"API error for '{item.word}': Status code {response.status_code}")
                except Exception as e:
                    item.example_sentence = f"Error enhancing content for {item.word}: {str(e)}"
                    print(f"Exception for '{item.word}': {str(e)}")
            else:
                print(f"Skipping item {i}/{total_items}: Content already exists for '{item.word}'")
        return items

class AudioGenerator(VocabularyProcessor):
    """Generate audio files using Google Text-to-Speech API"""
    def __init__(self):
        self.access_token = os.getenv("GOOGLE_ACCESS_TOKEN")
        if not self.access_token:
            print("Warning: GOOGLE_ACCESS_TOKEN not set. Audio generation will be skipped.")
            self.access_token = None
            return
        self.endpoint = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={self.access_token}"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        if not self.access_token:
            print("Skipping audio generation - no API key provided")
            return items
            
        headers = {
            "Content-Type": "application/json"
        }
        os.makedirs(AUDIO_DIR, exist_ok=True)
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.audio_path:
                print(f"Processing audio {i}/{total_items}: Generating audio for '{item.word}'")
                # Use the example sentence if available, otherwise just the word
                text_to_speak = item.example_sentence if item.example_sentence and not item.example_sentence.startswith("Failed") and not item.example_sentence.startswith("API error") and not item.example_sentence.startswith("Error") else item.word
                payload = {
                    "input": {
                        "text": text_to_speak
                    },
                    "voice": {
                        "languageCode": "en-US",
                        "name": "en-US-Wavenet-D",
                        "ssmlGender": "MALE"
                    },
                    "audioConfig": {
                        "audioEncoding": "MP3",
                        "speakingRate": 0.9
                    }
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        response_data = response.json()
                        audio_content = response_data.get("audioContent", "")
                        if audio_content:
                            audio_filename = f"gre_word_{item.word.replace(' ', '_')}.mp3"
                            audio_path = os.path.join(AUDIO_DIR, audio_filename)
                            with open(audio_path, "wb") as audio_file:
                                audio_file.write(base64.b64decode(audio_content))
                            # Set relative path for Anki CSV with [sound:] format
                            item.audio_path = f"[sound:{audio_filename}]"
                            print(f"Audio file generated for '{item.word}': {audio_path}")
                        else:
                            item.audio_path = f"No audio content returned for {item.word}"
                            print(f"No audio content returned for '{item.word}'")
                    else:
                        item.audio_path = f"API error for audio of {item.word} (status {response.status_code})"
                        print(f"API error generating audio for '{item.word}': Status code {response.status_code}")
                except Exception as e:
                    item.audio_path = f"Error generating audio for {item.word}: {str(e)}"
                    print(f"Exception generating audio for '{item.word}': {str(e)}")
            else:
                print(f"Skipping audio {i}/{total_items}: Audio path already exists for '{item.word}'")
        return items

class CSVExporter(VocabularyProcessor):
    """Export vocabulary to Anki-compatible CSV"""
    def __init__(self, output_path: str = DEFAULT_CSV_PATH):
        self.output_path = output_path

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = CSV_HEADERS
        
        output_dir = os.path.dirname(self.output_path)
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
            
        # Check if file exists to determine if headers are needed
        file_exists = os.path.exists(self.output_path)
        
        # Append items to CSV
        with open(self.output_path, 'a', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            if not file_exists:  # Write headers only if file is new
                writer.writerow(headers)
            for item in items:
                writer.writerow([
                    item.word,
                    item.definition if item.definition else "",
                    item.example_sentence if item.example_sentence else "",
                    item.etymology if item.etymology else "",
                    item.synonyms if item.synonyms else "",
                    item.antonyms if item.antonyms else "",
                    item.memory_tips if item.memory_tips else "",
                    item.audio_path if item.audio_path else ""
                ])
        print(f"Exported {len(items)} new cards to {self.output_path}")
        return items

def select_vocabulary_file() -> str:
    """Interactive file selection from vocabulary directory"""
    vocabulary_dir = "vocabulary"
    
    # Check if vocabulary directory exists
    if not os.path.exists(vocabulary_dir):
        print(f"Error: '{vocabulary_dir}' directory not found.")
        return None
    
    # Get all CSV files in vocabulary directory
    csv_files = glob.glob(os.path.join(vocabulary_dir, "*.csv"))
    
    if not csv_files:
        print(f"No CSV files found in '{vocabulary_dir}' directory.")
        return None
    
    # Sort files for consistent ordering
    csv_files.sort()
    
    print("\n=== Available Vocabulary Files ===")
    print("Please select a file to process:")
    
    for i, file_path in enumerate(csv_files, 1):
        filename = os.path.basename(file_path)
        # Try to get file size for additional info
        try:
            file_size = os.path.getsize(file_path)
            size_kb = file_size / 1024
            print(f"{i:2d}. {filename} ({size_kb:.1f} KB)")
        except:
            print(f"{i:2d}. {filename}")
    
    print(f"{len(csv_files) + 1:2d}. Process ALL files (combine all vocabulary)")
    print(" 0. Exit")
    
    while True:
        try:
            choice = input(f"\nEnter your choice (0-{len(csv_files) + 1}): ").strip()
            
            if choice == "0":
                print("Exiting...")
                return None
            
            choice_num = int(choice)
            
            if choice_num == len(csv_files) + 1:
                # Process all files
                return "ALL"
            elif 1 <= choice_num <= len(csv_files):
                selected_file = csv_files[choice_num - 1]
                print(f"Selected: {os.path.basename(selected_file)}")
                return selected_file
            else:
                print(f"Invalid choice. Please enter a number between 0 and {len(csv_files) + 1}.")
        
        except ValueError:
            print("Invalid input. Please enter a number.")
        except KeyboardInterrupt:
            print("\nExiting...")
            return None

def load_vocabulary(csv_path: str) -> List[VocabularyItem]:
    """Load vocabulary from CSV file or multiple files"""
    items = []
    
    if csv_path == "ALL":
        # Load from all CSV files in vocabulary directory
        vocabulary_dir = "vocabulary"
        csv_files = glob.glob(os.path.join(vocabulary_dir, "*.csv"))
        csv_files.sort()
        
        print(f"Loading vocabulary from {len(csv_files)} files...")
        
        for file_path in csv_files:
            filename = os.path.basename(file_path)
            print(f"Loading from {filename}...")
            
            try:
                with open(file_path, newline='', encoding='utf-8') as csvfile:
                    reader = csv.DictReader(csvfile)
                    file_items = []
                    for row in reader:
                        # Handle different possible column names
                        word = row.get('Word') or row.get('word') or row.get('WORD', '')
                        definition = row.get('Definition') or row.get('definition') or row.get('DEFINITION', '')
                        category = row.get('Category') or row.get('category') or row.get('CATEGORY', '')
                        difficulty = row.get('Difficulty') or row.get('difficulty') or row.get('DIFFICULTY', '')
                        
                        if word:  # Only add if word is not empty
                            file_items.append(VocabularyItem(
                                word=word,
                                definition=definition,
                                category=category,
                                difficulty=difficulty
                            ))
                    
                    items.extend(file_items)
                    print(f"  -> {len(file_items)} words loaded from {filename}")
            
            except Exception as e:
                print(f"  -> Error loading {filename}: {str(e)}")
        
        print(f"Total: {len(items)} words loaded from all files")
    
    else:
        # Load from single file
        with open(csv_path, newline='', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                # Handle different possible column names
                word = row.get('Word') or row.get('word') or row.get('WORD', '')
                definition = row.get('Definition') or row.get('definition') or row.get('DEFINITION', '')
                category = row.get('Category') or row.get('category') or row.get('CATEGORY', '')
                difficulty = row.get('Difficulty') or row.get('difficulty') or row.get('DIFFICULTY', '')
                
                if word:  # Only add if word is not empty
                    items.append(VocabularyItem(
                        word=word,
                        definition=definition,
                        category=category,
                        difficulty=difficulty
                    ))
        
        print(f"{len(items)} words loaded from {csv_path}")
    
    return items

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug', type=int, default=0, help='Enable debug mode with a limit on number of rows to process (0 for no limit)')
    parser.add_argument('--csv', type=str, default=None, help='Path to input CSV file (if not provided, interactive selection will be used)')
    args = parser.parse_args()
    
    # Determine input file
    if args.csv:
        # Use provided CSV file
        if not os.path.exists(args.csv):
            print(f"Error: Input CSV file '{args.csv}' not found.")
            print("Please check the file path and try again.")
            return
        selected_file = args.csv
    else:
        # Use interactive file selection
        selected_file = select_vocabulary_file()
        if not selected_file:
            return
    
    # Load vocabulary
    vocab_items = load_vocabulary(selected_file)
    
    # Determine output path
    output_path = DEFAULT_CSV_PATH if not args.debug else DEBUG_CSV_PATH
    
    # Check for existing entries in the output CSV to skip processing
    existing_items = set()
    if os.path.exists(output_path):
        try:
            with open(output_path, 'r', newline='', encoding='utf-8') as f:
                reader = csv.reader(f)
                next(reader, None)  # Skip header
                for row in reader:
                    if row and len(row) > 0:
                        existing_items.add(row[0])  # Word is the key
        except Exception as e:
            print(f"Error reading existing CSV: {str(e)}")
    
    # Filter out items that already exist
    initial_count = len(vocab_items)
    vocab_items = [item for item in vocab_items if item.word not in existing_items]
    print(f"{len(vocab_items)} items after deduplication")
    skipped_count = initial_count - len(vocab_items)
    if skipped_count > 0:
        print(f"Skipped {skipped_count} items already in {output_path}")
    
    # Get categories to filter
    category_input = input(CATEGORY_INPUT_PROMPT)
    categories = [cat.strip() for cat in category_input.split(',')] if category_input else []
    
    # Get difficulty levels to filter
    difficulty_input = input(DIFFICULTY_INPUT_PROMPT)
    difficulties = [diff.strip() for diff in difficulty_input.split(',')] if difficulty_input else []
    
    # Apply filters
    if categories:
        initial_category_count = len(vocab_items)
        category_filter = CategoryFilter(categories)
        vocab_items = category_filter.process(vocab_items)
        filtered_count = initial_category_count - len(vocab_items)
        if filtered_count > 0:
            print(f"Filtered out {filtered_count} items not in categories {categories}")
    
    if difficulties:
        initial_difficulty_count = len(vocab_items)
        difficulty_filter = DifficultyFilter(difficulties)
        vocab_items = difficulty_filter.process(vocab_items)
        filtered_count = initial_difficulty_count - len(vocab_items)
        if filtered_count > 0:
            print(f"Filtered out {filtered_count} items not in difficulty levels {difficulties}")
    
    # Apply debug limit
    if args.debug:
        initial_debug_count = len(vocab_items)
        vocab_items = vocab_items[:args.debug]
        debug_skipped_count = initial_debug_count - len(vocab_items)
        if debug_skipped_count > 0:
            print(f"Limited processing to {args.debug} items, skipped {debug_skipped_count} items due to debug mode")
    
    if not vocab_items:
        print("No items to process after filtering.")
        return
    
    # Create processing pipeline
    processors = [
        ContentEnhancer(),
        AudioGenerator(),
        CSVExporter(output_path)
    ]
    
    # Process vocabulary through each step
    for processor in processors:
        vocab_items = processor.process(vocab_items)

if __name__ == "__main__":
    main()
