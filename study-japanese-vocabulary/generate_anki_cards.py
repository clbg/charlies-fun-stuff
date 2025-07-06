import csv
from dataclasses import dataclass
from typing import List, Optional
import os
import argparse
import requests
import json

# Constants
OUTPUT_DIR = "output"
AUDIO_DIR = os.path.join(OUTPUT_DIR, "audio")
DEFAULT_CSV_PATH = os.path.join(OUTPUT_DIR, "anki_cards.csv")
DEBUG_CSV_PATH = os.path.join(OUTPUT_DIR, "anki_cards_debug.csv")
CSV_HEADERS = [
    "Japanese", "Chinese", "Example_JP", "Example_CN", "Example_Furigana",
    "Grammar_Notes", "Audio_Path"
]
INPUT_CSV_PATH = "jlpt_vocab.csv"
JLPT_INPUT_PROMPT = "输入要筛选的JLPT等级(用逗号分隔，例如4,5): "
CHINESE_COMMA = '，'

@dataclass
class VocabularyItem:
    """Common schema for vocabulary items that will be processed through all steps"""
    japanese: str
    chinese: str  # Changed from english to chinese
    jlpt_level: str
    example_sentence_jp: Optional[str] = None
    example_sentence_cn: Optional[str] = None
    example_furigana: Optional[str] = None
    grammar_notes: Optional[str] = None
    audio_path: Optional[str] = None

class VocabularyProcessor:
    """Base class for all processing steps"""
    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        raise NotImplementedError

class JLPTFilter(VocabularyProcessor):
    """Filter vocabulary by JLPT level"""
    def __init__(self, levels: List[int]):
        self.levels = [f'N{level}' for level in levels]

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        return [item for item in items if item.jlpt_level in self.levels]

class ExampleGenerator(VocabularyProcessor):
    """Generate example sentences using OpenAI API"""
    def __init__(self):
        self.api_key = os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set. Please set it before running the script.")
        self.endpoint = "https://api.openai.com/v1/chat/completions"
        self.model = "gpt-4.1-nano"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.example_sentence_jp:
                print(f"Processing item {i}/{total_items}: Generating example for '{item.japanese}'")
                prompt = f"Create a short, commonly used Japanese sentence using the word '{item.japanese}' that a beginner learner would encounter in everyday conversation. The sentence should be vivid and relatable, reflecting a real-life situation. Then provide a Chinese translation of this sentence, and finally provide the furigana (readings) for the Japanese sentence in HTML <ruby> tag format. Output ONLY the Japanese sentence on the first line, the Chinese translation on the second line, and the furigana version on the third line, with NO labels, prefixes, or additional text."
                payload = {
                    "model": self.model,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "max_tokens": 200
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        response_data = response.json()
                        content = response_data['choices'][0]['message']['content'].strip()
                        print(f"Received response for '{item.japanese}': {content}")
                        lines = content.split('\n')
                        if len(lines) >= 3:
                            item.example_sentence_jp = lines[0].strip()
                            item.example_sentence_cn = lines[1].strip()
                            item.example_furigana = lines[2].strip()
                            print(f"Set example for '{item.japanese}': JP: {item.example_sentence_jp}")
                            print(f"Set translation for '{item.japanese}': CN: {item.example_sentence_cn}")
                            print(f"Set furigana for '{item.japanese}': {item.example_furigana}")
                        else:
                            item.example_sentence_jp = f"Failed to parse example for {item.japanese}"
                            item.example_sentence_cn = f"Failed to parse translation for {item.chinese}"
                            item.example_furigana = f"Failed to parse furigana for {item.japanese}"
                            print(f"Failed to parse response for '{item.japanese}'")
                    else:
                        item.example_sentence_jp = f"API error for {item.japanese} (status {response.status_code})"
                        item.example_sentence_cn = f"API error for {item.chinese} (status {response.status_code})"
                        print(f"API error for '{item.japanese}': Status code {response.status_code}")
                except Exception as e:
                    item.example_sentence_jp = f"Error generating example for {item.japanese}: {str(e)}"
                    item.example_sentence_cn = f"Error generating translation for {item.chinese}: {str(e)}"
                    print(f"Exception for '{item.japanese}': {str(e)}")
            else:
                print(f"Skipping item {i}/{total_items}: Example already exists for '{item.japanese}'")
        return items

class GrammarNotesGenerator(VocabularyProcessor):
    """Generate grammar notes for example sentences using OpenAI API"""
    def __init__(self):
        self.api_key = os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set. Please set it before running the script.")
        self.endpoint = "https://api.openai.com/v1/chat/completions"
        self.model = "gpt-4.1-mini"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.grammar_notes and item.example_sentence_jp and not item.example_sentence_jp.startswith("Failed") and not item.example_sentence_jp.startswith("API error") and not item.example_sentence_jp.startswith("Error generating"):
                print(f"Processing grammar notes {i}/{total_items}: Generating notes for '{item.japanese}'")
                prompt = f"Provide a simple grammar explanation for the Japanese sentence '{item.example_sentence_jp}', tailored for beginner learners. Focus on one or two key grammar points used in the sentence, explaining them in a clear and concise way. Additionally, include readings (furigana) and brief Chinese explanations for any other unfamiliar words in the sentence. Use Chinese for all explanations. Output the result in pure HTML format for Anki, with grammar points in ordered lists (<ol><li>) and furigana in <ruby> tags. Do not include any markdown code block indicators (like ```html) or introductory/concluding phrases outside the core content."
                payload = {
                    "model": self.model,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "max_tokens": 500
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        response_data = response.json()
                        content = response_data['choices'][0]['message']['content'].strip()
                        print(f"Received grammar notes for '{item.japanese}': {content}")
                        item.grammar_notes = content
                    else:
                        item.grammar_notes = f"API error for grammar notes of {item.japanese} (status {response.status_code})"
                        print(f"API error for grammar notes of '{item.japanese}': Status code {response.status_code}")
                except Exception as e:
                    item.grammar_notes = f"Error generating grammar notes for {item.japanese}: {str(e)}"
                    print(f"Exception for grammar notes of '{item.japanese}': {str(e)}")
            else:
                print(f"Skipping grammar notes {i}/{total_items}: Notes already exist or no valid sentence for '{item.japanese}'")
        return items

class AudioGenerator(VocabularyProcessor):
    """Generate audio files using OpenAI TTS API"""
    def __init__(self):
        self.api_key = os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set. Please set it before running the script.")
        self.endpoint = "https://api.openai.com/v1/audio/speech"
        self.model = "tts-1"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        os.makedirs(AUDIO_DIR, exist_ok=True)
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.audio_path:
                print(f"Processing audio {i}/{total_items}: Generating audio for '{item.japanese}'")
                # Use the Japanese word or sentence for audio generation
                text_to_speak = item.example_sentence_jp if item.example_sentence_jp and not item.example_sentence_jp.startswith("Failed") and not item.example_sentence_jp.startswith("API error") and not item.example_sentence_jp.startswith("Error generating") else item.japanese
                payload = {
                    "model": self.model,
                    "input": text_to_speak,
                    "voice": "alloy"
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        audio_filename = f"jlpt_vocabulary_in_sentence_{item.japanese}.mp3"
                        audio_path = os.path.join(AUDIO_DIR, audio_filename)
                        with open(audio_path, "wb") as audio_file:
                            audio_file.write(response.content)
                        # Set relative path for Anki CSV with [sound:] format (without 'output/' prefix)
                        item.audio_path = f"[sound:{audio_filename}]"
                        print(f"Audio file generated for '{item.japanese}': {audio_path}")
                    else:
                        item.audio_path = f"API error for audio of {item.japanese} (status {response.status_code})"
                        print(f"API error generating audio for '{item.japanese}': Status code {response.status_code}")
                except Exception as e:
                    item.audio_path = f"Error generating audio for {item.japanese}: {str(e)}"
                    print(f"Exception generating audio for '{item.japanese}': {str(e)}")
            else:
                print(f"Skipping audio {i}/{total_items}: Audio path already exists for '{item.japanese}'")
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
                    item.japanese,
                    item.chinese,  # Changed from english to chinese
                    item.example_sentence_jp,
                    item.example_sentence_cn,  # Note: This is Chinese translation
                    item.example_furigana,
                    item.grammar_notes,
                    item.audio_path
                ])
        print(f"Exported {len(items)} new cards to {self.output_path}")
        return items

def load_vocabulary(csv_path: str) -> List[VocabularyItem]:
    """Load vocabulary from CSV file"""
    items = []
    with open(csv_path, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            items.append(VocabularyItem(
                japanese=row['Original'],
                chinese=row['English'],  # Changed from english to chinese
                jlpt_level=row['JLPT Level']
            ))
    print(f"{len(items)} loaded")
    return items

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug', type=int, default=0, help='Enable debug mode with a limit on number of rows to process (0 for no limit)')
    args = parser.parse_args()
    
    # Load vocabulary
    csv_path = INPUT_CSV_PATH
    vocab_items = load_vocabulary(csv_path)
    
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
                        existing_items.add(row[0])  # Japanese word is the key
        except Exception as e:
            print(f"Error reading existing CSV: {str(e)}")
    
    # Filter out items that already exist
    initial_count = len(vocab_items)
    vocab_items = [item for item in vocab_items if item.japanese not in existing_items]
    print(f"{len(vocab_items)} items after dedup")
    skipped_count = initial_count - len(vocab_items)
    if skipped_count > 0:
        print(f"Skipped {skipped_count} items already in {output_path} during loading")
    
    # Get JLPT levels to filter
    level_input = input(JLPT_INPUT_PROMPT)
    level_input = level_input.replace(CHINESE_COMMA, ',')  # Handle Chinese commas
    levels = [int(l.strip()) for l in level_input.split(',')] if level_input else []
    
    # Apply JLPT filter directly before debug limit
    if levels:
        initial_level_count = len(vocab_items)
        level_filter = JLPTFilter(levels)
        vocab_items = level_filter.process(vocab_items)
        filtered_count = initial_level_count - len(vocab_items)
        if filtered_count > 0:
            print(f"Filtered out {filtered_count} items not in JLPT levels {levels}")
    
    # Apply debug limit to control the number of items to process after JLPT filter
    if args.debug:
        initial_debug_count = len(vocab_items)
        vocab_items = vocab_items[:args.debug]
        debug_skipped_count = initial_debug_count - len(vocab_items)
        if debug_skipped_count > 0:
            print(f"Limited processing to {args.debug} items, skipped {debug_skipped_count} items due to debug mode")
    
    # Create processing pipeline
    processors = []
    processors.extend([
        ExampleGenerator(),
        GrammarNotesGenerator(),
        AudioGenerator(),
        CSVExporter(output_path)
    ])
    
    # Process vocabulary through each step
    for processor in processors:
        vocab_items = processor.process(vocab_items)

if __name__ == "__main__":
    main()
