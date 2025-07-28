import csv
from dataclasses import dataclass
from typing import List, Optional, Dict, Any
import os
import argparse
import requests
import json
import base64
import boto3
from abc import ABC, abstractmethod
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

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

class LLMProvider(ABC):
    """Abstract base class for LLM providers"""
    
    @abstractmethod
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion from the LLM provider"""
        pass

class OpenAIProvider(LLMProvider):
    """OpenAI API provider"""
    
    def __init__(self, api_key: str = None, model: str = "gpt-4.1", endpoint: str = "https://api.openai.com/v1/chat/completions"):
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set or api_key parameter not provided.")
        self.model = model
        self.endpoint = endpoint
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using OpenAI API"""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "max_tokens": max_tokens
        }
        
        response = requests.post(self.endpoint, json=payload, headers=headers)
        if response.status_code == 200:
            response_data = response.json()
            return response_data['choices'][0]['message']['content'].strip()
        else:
            raise Exception(f"API error: Status code {response.status_code}")

class AnthropicProvider(LLMProvider):
    """Anthropic Claude API provider"""
    
    def __init__(self, api_key: str = None, model: str = "claude-3-sonnet-20240229", endpoint: str = "https://api.anthropic.com/v1/messages"):
        self.api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY environment variable not set or api_key parameter not provided.")
        self.model = model
        self.endpoint = endpoint
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using Anthropic API"""
        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        }
        
        payload = {
            "model": self.model,
            "max_tokens": max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
        
        response = requests.post(self.endpoint, json=payload, headers=headers)
        if response.status_code == 200:
            response_data = response.json()
            return response_data['content'][0]['text'].strip()
        else:
            raise Exception(f"API error: Status code {response.status_code}")

class BedrockProvider(LLMProvider):
    """AWS Bedrock API provider for Claude models using boto3 with API key"""
    
    def __init__(self, api_key: str = None, model: str = "us.anthropic.claude-sonnet-4-20250514-v1:0", region: str = "us-west-2"):
        self.api_key = api_key or os.getenv("AWS_BEARER_TOKEN_BEDROCK")
        if not self.api_key:
            raise ValueError("AWS_BEARER_TOKEN_BEDROCK environment variable not set or api_key parameter not provided.")
        self.model = model
        self.region = region
        
        # Ensure model is a Claude model
        if not "anthropic.claude" in self.model:
            raise ValueError(f"BedrockProvider only supports Claude models. Provided model: {self.model}")
        
        # Set the API key as an environment variable for boto3
        os.environ['AWS_BEARER_TOKEN_BEDROCK'] = self.api_key
        
        # Create boto3 client for Bedrock
        self.bedrock_client = boto3.client(
            service_name='bedrock-runtime',
            region_name=self.region
        )
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using AWS Bedrock API with Claude models via boto3"""
        try:
            # For newer Claude models, use converse API
                # Prepare messages for converse API
                messages = [
                    {
                        "role": "user", 
                        "content": [{"text": prompt}]
                    }
                ]
                
                # Call the converse API
                response = self.bedrock_client.converse(
                    modelId=self.model,
                    messages=messages,
                )
                
                # Extract the completion text from converse response
                return response['output']['message']['content'][0]['text'].strip()
        except Exception as e:
            raise Exception(f"AWS Bedrock API error: {str(e)}")

class JLPTFilter(VocabularyProcessor):
    """Filter vocabulary by JLPT level"""
    def __init__(self, levels: List[int]):
        self.levels = [f'N{level}' for level in levels]

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        return [item for item in items if item.jlpt_level in self.levels]

class ExampleGenerator(VocabularyProcessor):
    def __init__(self, llm_provider: LLMProvider = None):
        self.llm_provider = llm_provider or OpenAIProvider()

    def _create_prompt(self, japanese_word: str) -> str:
        return f"""
你是日语教学助手。  
请仅返回 **有效 JSON**，不得输出多余文本或 Markdown 代码块标记。  
返回内容必须满足以下 schema 与约束：

### 📐 JSON Schema
{{
  "cn_gloss":         string,   // 目标单词的中文翻译，10 字以内
  "jp_sentence":      string,   // 纯文本日语句子，必须包含目标单词
  "cn_sentence":      string,   // jp_sentence 的中文翻译
  "jp_sentence_furigana": array,  // jp_sentence 的词块注音数组
  "grammar_html":     string    // 以 <ol><li>…</li></ol> 包裹的 1–2 条语法说明（html 字符串）
}}

### 🔒 约束
1. **jp_sentence**  
   - 不得包含字符 `<`、`>` 或任何 HTML／emoji。  
   - 字数 7–20 个假名（含空格）之间，句末用「。」。  

2. **jp_sentence_furigana**  
   - 必须是 JSON 数组，每个元素包含 "text" 和 "kana" 字段。
   - "text"：词块原文（含汉字或假名，不要拆开固定词块）。
   - "kana"：假名读音。对于纯假名或标点，kana 设为空字符串 ""。读音写成平假名，不要再分解或加空格。
   - 如果内部文本有引号，注意转义以符合 json 的格式
   - 字段顺序固定为 text → kana。
   - 各词块保持原句顺序。
   - 不要加入额外字段或多层嵌套。

3. **grammar_html**  
   - 详细的解释这个句子的所有单词，使用以`<ol>` 开头、`</ol>` 结尾；内部用 `<li>`的表格的形式
   - 详细解释这个句子设计到的语法知识
   - 如果有需要可以解释一下文化背景
   - 全部使用中文解释，必要日语词汇可加括号注音。  

4. **通用**  
   - 返回的 JSON **必须能通过 `json.loads()` 解析**（双引号、转义正确）。  
   - 不得出现空字段、额外字段或重复字段。

### ✅ 自检流程（生成后立刻执行）
- [ ] 确认只有一个顶层 JSON 对象。  
- [ ] 用正则 `"<|>"` 检查 jp_sentence ➜ 不得命中。  
- [ ] 用正则 `^<ol>` 和 `</ol>$` 检查 grammar_html ➜ 必须同时命中。  
- [ ] 成功通过才输出；否则**重新生成**直到所有检查通过。  

### 📝 任务输入
目标单词: 「{japanese_word}」
"""

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.example_sentence_jp:
                print(f"Processing item {i}/{total_items}: Generating example for '{item.japanese}'")
                prompt = self._create_prompt(item.japanese)
                
                try:
                    content = self.llm_provider.generate_completion(prompt, max_tokens=800)
                    print(f"Received response for '{item.japanese}': {content}")
                    try:
                        json_data = json.loads(content)
                        item.chinese = json_data.get('cn_gloss', f"Failed to parse translation for {item.japanese}")
                        item.example_sentence_jp = json_data.get('jp_sentence', f"Failed to parse example for {item.japanese}")
                        item.example_sentence_cn = json_data.get('cn_sentence', f"Failed to parse translation for {item.chinese}")
                        
                        furigana_data = json_data.get('jp_sentence_furigana')
                        if isinstance(furigana_data, list):
                            furigana_parts = []
                            for part in furigana_data:
                                text = part.get('text', '')
                                kana = part.get('kana', '')
                                if kana:
                                    furigana_parts.append(f"<ruby>{text}<rt>{kana}</rt></ruby>")
                                else:
                                    furigana_parts.append(text)
                            item.example_furigana = "".join(furigana_parts)
                        else:
                            item.example_furigana = f"Failed to parse furigana (expected list) for {item.japanese}: {furigana_data}"

                        item.grammar_notes = json_data.get('grammar_html', f"Failed to parse grammar notes for {item.japanese}")
                        print(f"Set Chinese translation for '{item.japanese}': {item.chinese if item.chinese is not None else 'None'}")
                        print(f"Set example for '{item.japanese}': JP: {item.example_sentence_jp if item.example_sentence_jp is not None else 'None'}")
                        print(f"Set translation for '{item.japanese}': CN: {item.example_sentence_cn if item.example_sentence_cn is not None else 'None'}")
                        print(f"Set furigana for '{item.japanese}': {item.example_furigana if item.example_furigana is not None else 'None'}")
                        print(f"Set grammar notes for '{item.japanese}': {item.grammar_notes[:50] if item.grammar_notes is not None else 'None'}...")
                    except json.JSONDecodeError as jde:
                        item.chinese = f"Failed to parse JSON for translation of {item.japanese}"
                        item.example_sentence_jp = f"Failed to parse JSON for example of {item.japanese}"
                        item.example_sentence_cn = f"Failed to parse JSON for translation"
                        item.example_furigana = f"Failed to parse JSON for furigana of {item.japanese}"
                        item.grammar_notes = f"Failed to parse JSON for grammar notes of {item.japanese}"
                        print(f"JSON parsing error for '{item.japanese}': {str(jde)}")
                except Exception as e:
                    item.example_sentence_jp = f"Error generating example for {item.japanese}: {str(e)}"
                    item.example_sentence_cn = f"Error generating translation: {str(e)}"
                    print(f"Exception for '{item.japanese}': {str(e)}")
            else:
                print(f"Skipping item {i}/{total_items}: Example already exists for '{item.japanese}'")
        return items

# Removed GrammarNotesGenerator as it's now integrated into ExampleGenerator

class AudioGenerator(VocabularyProcessor):
    """Generate audio files using Google Text-to-Speech API"""
    def __init__(self):
        self.access_token = os.getenv("GOOGLE_ACCESS_TOKEN")
        if not self.access_token:
            raise ValueError("GOOGLE_ACCESS_TOKEN environment variable not set. Please set it before running the script.")
        self.endpoint = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={self.access_token}"
        self.project_id = "sub-craft"

    def process(self, items: List[VocabularyItem]) -> List[VocabularyItem]:
        headers = {
            #"Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
            #"X-Goog-User-Project": self.project_id
        }
        os.makedirs(AUDIO_DIR, exist_ok=True)
        
        total_items = len(items)
        for i, item in enumerate(items, 1):
            if not item.audio_path:
                print(f"Processing audio {i}/{total_items}: Generating audio for '{item.japanese}'")
                # Use the Japanese word or sentence for audio generation
                text_to_speak = item.example_sentence_jp if item.example_sentence_jp is not None and not item.example_sentence_jp.startswith("Failed") and not item.example_sentence_jp.startswith("API error") and not item.example_sentence_jp.startswith("Error generating") else item.japanese
                payload = {
                    "input": {
                        "markup": text_to_speak
                    },
                    "voice": {
                        "languageCode": "ja-JP",
                        "name": "ja-JP-Chirp3-HD-Achernar",
                        "voiceClone": {}
                    },
                    "audioConfig": {
                        "audioEncoding": "MP3",
                        "speakingRate": 0.75,

                    }
                }
                
                try:
                    response = requests.post(self.endpoint, json=payload, headers=headers)
                    if response.status_code == 200:
                        response_data = response.json()
                        audio_content = response_data.get("audioContent", "")
                        if audio_content:
                            audio_filename = f"jlpt_vocabulary_in_sentence_{item.japanese}.mp3"
                            audio_path = os.path.join(AUDIO_DIR, audio_filename)
                            with open(audio_path, "wb") as audio_file:
                                audio_file.write(base64.b64decode(audio_content))
                            # Set relative path for Anki CSV with [sound:] format (without 'output/' prefix)
                            item.audio_path = f"[sound:{audio_filename}]"
                            print(f"Audio file generated for '{item.japanese}': {audio_path}")
                        else:
                            item.audio_path = f"No audio content returned for {item.japanese}"
                            print(f"No audio content returned for '{item.japanese}'")
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
                    item.chinese if item.chinese is not None else "",  # Changed from english to chinese
                    item.example_sentence_jp if item.example_sentence_jp is not None else "",
                    item.example_sentence_cn if item.example_sentence_cn is not None else "",  # Note: This is Chinese translation
                    item.example_furigana if item.example_furigana is not None else "",
                    item.grammar_notes if item.grammar_notes is not None else "",
                    item.audio_path if item.audio_path is not None else ""
                ])
        print(f"Exported {len(items)} new cards to {self.output_path}")
        return items

def create_llm_provider(provider_type: str = "openai", **kwargs) -> LLMProvider:
    """Factory function to create LLM providers
    
    Args:
        provider_type: Type of provider ("openai", "anthropic", or "bedrock")
        **kwargs: Additional parameters for the provider (api_key, model, endpoint)
    
    Returns:
        LLMProvider instance
    """
    if provider_type.lower() == "openai":
        return OpenAIProvider(**kwargs)
    elif provider_type.lower() == "anthropic":
        return AnthropicProvider(**kwargs)
    elif provider_type.lower() == "bedrock":
        return BedrockProvider(**kwargs)
    else:
        raise ValueError(f"Unsupported provider type: {provider_type}")

def load_vocabulary(csv_path: str) -> List[VocabularyItem]:
    """Load vocabulary from CSV file"""
    items = []
    with open(csv_path, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            items.append(VocabularyItem(
                japanese=row['Original'],
                chinese="",  # Will be populated via API
                jlpt_level=row['JLPT Level']
            ))
    print(f"{len(items)} loaded")
    return items

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug', type=int, default=0, help='Enable debug mode with a limit on number of rows to process (0 for no limit)')
    parser.add_argument('--llm-provider', type=str, default='openai', choices=['openai', 'anthropic', 'bedrock'], help='LLM provider to use (default: openai)')
    parser.add_argument('--model', type=str, help='Model name to use (overrides default for provider)')
    parser.add_argument('--api-key', type=str, help='API key to use (overrides environment variable)')
    parser.add_argument('--endpoint', type=str, help='API endpoint to use (overrides default for provider)')
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
    
    # Create LLM provider based on arguments
    llm_kwargs = {}
    if args.api_key:
        llm_kwargs['api_key'] = args.api_key
    if args.model:
        llm_kwargs['model'] = args.model
    if args.endpoint:
        llm_kwargs['endpoint'] = args.endpoint
    
    try:
        llm_provider = create_llm_provider(args.llm_provider, **llm_kwargs)
        print(f"Using {args.llm_provider} provider with model: {getattr(llm_provider, 'model', 'default')}")
    except Exception as e:
        print(f"Error creating LLM provider: {e}")
        return
    
    # Create processing pipeline
    processors = []
    processors.extend([
        ExampleGenerator(llm_provider=llm_provider),
        AudioGenerator(),
        CSVExporter(output_path)
    ])
    
    # Process vocabulary through each step
    for processor in processors:
        vocab_items = processor.process(vocab_items)

if __name__ == "__main__":
    main()
