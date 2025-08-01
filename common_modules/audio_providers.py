import os
import requests
import base64
from abc import ABC, abstractmethod
from enum import Enum
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class Language(Enum):
    EN = "en"
    JA = "ja"

class AudioProvider(ABC):
    """Abstract base class for Audio providers"""
    
    @abstractmethod
    def generate_audio(self, text: str, output_path: str) -> str:
        """Generate audio from the Audio provider"""
        pass

class GoogleTTSProvider(AudioProvider):
    """Google Text-to-Speech API provider"""
    def __init__(self, language: Language):
        self.language = language
        self.access_token = os.getenv("GOOGLE_ACCESS_TOKEN")
        if not self.access_token:
            raise ValueError("GOOGLE_ACCESS_TOKEN environment variable not set. Please set it before running the script.")
        self.endpoint = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={self.access_token}"
        self.project_id = "sub-craft" # This might be specific to the original project, consider making it configurable if needed

    def generate_audio(self, text: str, output_path: str) -> str:
        headers = {
            "Content-Type": "application/json",
        }
        
        if self.language == Language.JA:
            voice_config = {
                "languageCode": "ja-JP",
                "name": "ja-JP-Chirp3-HD-Achernar",
                "voiceClone": {}
            }
        elif self.language == Language.EN:
            voice_config = {
                "languageCode": "en-US",
                "name": "en-US-Chirp3-HD-Achernar"
            }
        else:
            raise ValueError(f"Unsupported language: {self.language}")

        payload = {
            "input": {
                "markup": text
            },
            "voice": voice_config,
            "audioConfig": {
                "audioEncoding": "MP3",
                "speakingRate": 0.75,
            }
        }
        
        response = requests.post(self.endpoint, json=payload, headers=headers)
        if response.status_code == 200:
            response_data = response.json()
            audio_content = response_data.get("audioContent", "")
            if audio_content:
                with open(output_path, "wb") as audio_file:
                    audio_file.write(base64.b64decode(audio_content))
                return output_path
            else:
                raise Exception(f"No audio content returned for text: {text}")
        else:
            raise Exception(f"API error generating audio for text: {text} (status {response.status_code}, response: {response.text})")

def create_audio_provider(language: Language, provider_type: str = "google_tts", **kwargs) -> AudioProvider:
    """Factory function to create Audio providers
    
    Args:
        language: The language to use for TTS.
        provider_type: Type of provider ("google_tts")
        **kwargs: Additional parameters for the provider
    
    Returns:
        AudioProvider instance
    """
    if provider_type.lower() == "google_tts":
        return GoogleTTSProvider(language=language, **kwargs)
    else:
        raise ValueError(f"Unsupported audio provider type: {provider_type}")
