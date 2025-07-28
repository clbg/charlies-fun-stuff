import base64
import csv
from dataclasses import dataclass
import json
from typing import List, Optional
import os
import argparse
import glob
from dotenv import load_dotenv
import requests
from common_modules.llm_providers import LLMProvider, create_llm_provider
from common_modules.audio_providers import AudioProvider, create_audio_provider, Language

# Load environment variables from .env file
load_dotenv()

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

class ContentEnhancer(VocabularyProcessor):
    """Enhance vocabulary content using a common LLM provider"""
    def __init__(self, llm_provider: LLMProvider):
        self.llm_provider = llm_provider

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        total_items = len(items)
        for i, item in enumerate(items, 1):
            # Only enhance if example_sentence is missing or indicates a previous failure
            if not item.example_sentence or item.example_sentence.startswith(("Failed", "Error", "API error")):
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
                try:
                    # Use the common LLM provider
                    response_content = self.llm_provider.generate_completion(prompt, max_tokens=600)
                    print(f"Received response for '{item.word}': {response_content[:100]}...")
                    
                    # Parse the JSON response
                    json_data = json.loads(response_content)
                    
                    # Map the response to VocabularyItem fields
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
                except Exception as e:
                    item.example_sentence = f"Error enhancing content for {item.word}: {str(e)}"
                    print(f"Exception for '{item.word}': {str(e)}")
            else:
                print(f"Skipping item {i}/{total_items}: Content already exists for '{item.word}'")
        return items

class AudioGenerator(VocabularyProcessor):
    """Generate audio files using a chosen AudioProvider"""
    def __init__(self, audio_provider: AudioProvider, source_csv_path: str):
        self.audio_provider = audio_provider
        self.source_csv_name = os.path.splitext(os.path.basename(source_csv_path))[0]

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        os.makedirs(AUDIO_DIR, exist_ok=True)
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.audio_path:
                print(f"Processing audio {i}/{total_items}: Generating audio for '{item.word}'")
                # Use the example sentence if available, otherwise just the word
                text_to_speak = item.example_sentence if item.example_sentence and not item.example_sentence.startswith("Failed") and not item.example_sentence.startswith("API error") and not item.example_sentence.startswith("Error") else item.word
                
                # Incorporate source CSV name into the audio filename for deduplication
                audio_filename = f"gre_word_{self.source_csv_name}_{item.word.replace(' ', '_')}.mp3"
                audio_path = os.path.join(AUDIO_DIR, audio_filename)
                
                try:
                    self.audio_provider.generate_audio(text_to_speak, audio_path)
                    item.audio_path = f"[sound:{audio_filename}]"
                    print(f"Audio file generated for '{item.word}': {audio_path}")
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

def select_vocabulary_file() -> Optional[str]:
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
    
    print(f"Loading vocabulary from {csv_path}")
    with open(csv_path, newline='', encoding='utf-8') as csvfile:
        # Peek at the first row to determine if it's a single-column word list or a structured CSV
        # Reset file pointer after peeking
        first_line = csvfile.readline().strip()
        csvfile.seek(0) 
        
        # Check if the first line contains a comma, indicating multiple columns
        if ',' in first_line:
            reader = csv.DictReader(csvfile)
            for row in reader:
                word = row.get('Word') or row.get('word') or row.get('WORD', '')
                definition = row.get('Definition') or row.get('definition') or row.get('DEFINITION', '')
                category = row.get('Category') or row.get('category') or row.get('CATEGORY', '')
                difficulty = row.get('Difficulty') or row.get('difficulty') or row.get('DIFFICULTY', '')
                
                if word:
                    items.append(VocabularyItem(
                        word=word,
                        definition=definition,
                        category=category,
                        difficulty=difficulty
                    ))
        else:
            # Assume single column of words
            reader = csv.reader(csvfile)
            for row in reader:
                if row and row[0].strip():  # Ensure row is not empty and word is not empty
                    word = row[0].strip()
                    items.append(VocabularyItem(
                        word=word,
                        definition="",  # Definition will be enhanced by LLM
                        category="Unknown",
                        difficulty="Unknown"
                    ))
    
    print(f"{len(items)} words loaded from {csv_path}")
    
    return items

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug', type=int, default=0, help='Enable debug mode with a limit on number of rows to process (0 for no limit)')
    parser.add_argument('--csv', type=str, default=None, help='Path to input CSV file (if not provided, interactive selection will be used)')
    parser.add_argument('--llm-provider', type=str, default='openai', choices=['openai', 'anthropic', 'bedrock'], help='LLM provider to use (default: openai)')
    parser.add_argument('--model', type=str, help='Model name to use (overrides default for provider)')
    parser.add_argument('--api-key', type=str, help='API key to use (overrides environment variable)')
    parser.add_argument('--endpoint', type=str, help='API endpoint to use (overrides default for provider)')
    parser.add_argument('--audio-provider', type=str, default='google_tts', choices=['google_tts'], help='Audio provider to use (default: google_tts)')
    args = parser.parse_args()
    
    # Determine input file
    selected_file = None
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
    
    if not selected_file: # Handle case where user exits or no files are found
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
    
    # Create LLM provider based on arguments
    llm_kwargs = {}
    if args.api_key:
        llm_kwargs['api_key'] = args.api_key
    if args.model:
        llm_kwargs['model'] = args.model
    if args.endpoint:
        llm_kwargs['endpoint'] = args.endpoint
    
    try:
        print(f"LLM Provider kwargs: {llm_kwargs}") # Added print statement
        llm_provider = create_llm_provider(args.llm_provider, **llm_kwargs)
        print(f"Using {args.llm_provider} provider with model: {getattr(llm_provider, 'model', 'default')}")
    except Exception as e:
        print(f"Error creating LLM provider: {e}")
        return

    # Create Audio provider based on arguments
    audio_provider = create_audio_provider(language=Language.EN, provider_type=args.audio_provider)
    if not audio_provider:
        print("Failed to initialize Audio provider. Exiting.")
        return

    # Create processing pipeline
    processors = [
        ContentEnhancer(llm_provider),
        AudioGenerator(audio_provider, selected_file),
        CSVExporter(output_path)
    ]
    
    # Process vocabulary through each step
    for processor in processors:
        vocab_items = processor.process(vocab_items)

if __name__ == "__main__":
    main()
