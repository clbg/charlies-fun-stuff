import os
import shutil
from PIL import Image
import csv
import base64
import requests

def filter_and_organize_cards(input_dir, output_dir, start_card, end_card):
    # Create output directory for filtered cards if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Filter cards in the range start_card to end_card
    filtered_cards = []
    for card_num in range(start_card, end_card + 1):
        card_filename = f"card_{card_num:03d}.png"
        new_card_filename = f"cardsAgainstHumanity_card_{card_num:03d}.png"
        card_path = os.path.join(input_dir, card_filename)
        if os.path.exists(card_path):
            filtered_cards.append(new_card_filename)
            # Copy the card to the output directory with the new filename
            shutil.copy2(card_path, os.path.join(output_dir, new_card_filename))
    
    return filtered_cards, output_dir

def create_anki_csv(cards_dir, csv_output_path):
    # Create a CSV file for Anki import, using OpenAI 4.1 Mini API for text extraction, pronunciation, and translation
    # Retrieve OpenAI API key from environment variable to prevent leaking sensitive information
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY environment variable not set. Please set it before running the script.")
    model = "gpt-4.1-mini"
    endpoint = "https://api.openai.com/v1/chat/completions"
    
    with open(csv_output_path, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['Card_Number', 'Image', 'English', 'Pronunciation', 'Translation', 'Audio']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        
        card_files = sorted([f for f in os.listdir(cards_dir) if f.endswith('.png')])
        for card_file in card_files:
            # Extract card number from filename with format cardsAgainstHumanity_card_XXX.png
            card_num_str = card_file.split('_')[2].split('.')[0]
            card_num = int(card_num_str)
            card_path = os.path.join(cards_dir, card_file)
            
            # Read and encode the image as base64
            with open(card_path, "rb") as image_file:
                image_data = base64.b64encode(image_file.read()).decode('utf-8')
            
            # Prepare the payload for OpenAI API
            payload = {
                "model": model,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "提取文字，输出的结果只要包含提取的文字以及原文的所有下划线，不需要包含其他任何东西，以及需要删除最后一行小的Cards Against Humanity"
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/png;base64,{image_data}"
                                }
                            }
                        ]
                    }
                ],
                "max_tokens": 300
            }
            
            # Make request to OpenAI API
            try:
                headers = {
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json"
                }
                response = requests.post(endpoint, json=payload, headers=headers)
                print(f"API Response for card {card_num}: Status Code: {response.status_code}")
                if response.status_code == 200:
                    response_data = response.json()
                    print(f"API Response for card {card_num}: {response_data}")
                    english_text = response_data['choices'][0]['message']['content'].strip()
                    if not english_text:
                        english_text = f"English text for card {card_num} (API failed to extract text)"
                    else:
                        print(f"Extracted text for card {card_num}: {english_text}")
                else:
                    english_text = f"English text for card {card_num} (API returned status {response.status_code})"
                    print(f"API Error for card {card_num}: {response.text}")
            except Exception as e:
                english_text = f"English text for card {card_num} (API error: {str(e)})"
                print(f"Exception for card {card_num}: {str(e)}")
            
            # Request for Pronunciation
            try:
                payload_pron = {
                    "model": model,
                    "messages": [
                        {
                            "role": "user",
                            "content": f"Provide pronunciation for difficult words in : {english_text}, 只要输出单词和国际英标，用一个list表示，不要提供其他任何东西"
                        }
                    ],
                    "max_tokens": 100
                }
                response_pron = requests.post(endpoint, json=payload_pron, headers=headers)
                print(f"Pronunciation API Response for card {card_num}: Status Code: {response_pron.status_code}")
                if response_pron.status_code == 200:
                    response_data_pron = response_pron.json()
                    print(f"Pronunciation API Response for card {card_num}: {response_data_pron}")
                    pronunciation = response_data_pron['choices'][0]['message']['content'].strip()
                    if not pronunciation:
                        pronunciation = f"Pronunciation for card {card_num} (API failed to provide pronunciation)"
                    else:
                        print(f"Pronunciation for card {card_num}: {pronunciation}")
                else:
                    pronunciation = f"Pronunciation for card {card_num} (API returned status {response_pron.status_code})"
                    print(f"Pronunciation API Error for card {card_num}: {response_pron.text}")
            except Exception as e:
                pronunciation = f"Pronunciation for card {card_num} (API error: {str(e)})"
                print(f"Pronunciation Exception for card {card_num}: {str(e)})")
            
            # Request for Translation
            try:
                payload_trans = {
                    "model": model,
                    "messages": [
                        {
                            "role": "user",
                            "content": f"Translate to Chinese: {english_text}"
                        }
                    ],
                    "max_tokens": 100
                }
                response_trans = requests.post(endpoint, json=payload_trans, headers=headers)
                print(f"Translation API Response for card {card_num}: Status Code: {response_trans.status_code}")
                if response_trans.status_code == 200:
                    response_data_trans = response_trans.json()
                    print(f"Translation API Response for card {card_num}: {response_data_trans}")
                    translation = response_data_trans['choices'][0]['message']['content'].strip()
                    if not translation:
                        translation = f"Translation for card {card_num} (API failed to provide translation)"
                    else:
                        print(f"Translation for card {card_num}: {translation}")
                else:
                    translation = f"Translation for card {card_num} (API returned status {response_trans.status_code})"
                    print(f"Translation API Error for card {card_num}: {response_trans.text}")
            except Exception as e:
                translation = f"Translation for card {card_num} (API error: {str(e)})"
                print(f"Translation Exception for card {card_num}: {str(e)}")
            
            # Initialize audio field
            audio = f"Audio for card {card_num} (not generated)"

            # Generate audio using OpenAI TTS API if English text is available
            if english_text and not english_text.startswith("English text for card"):
                try:
                    tts_endpoint = "https://api.openai.com/v1/audio/speech"
                    payload_tts = {
                        "model": "tts-1",
                        "input": english_text,
                        "voice": "alloy"
                    }
                    headers_tts = {
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json"
                    }
                    response_tts = requests.post(tts_endpoint, json=payload_tts, headers=headers_tts)
                    print(f"TTS API Response for card {card_num}: Status Code: {response_tts.status_code}")
                    if response_tts.status_code == 200:
                        audio_filename = f"cardsAgainstHumanity_audio_{card_num:03d}.mp3"
                        audio_path = os.path.join(cards_dir, audio_filename)
                        with open(audio_path, "wb") as audio_file:
                            audio_file.write(response_tts.content)
                        audio = f'[sound:{audio_filename}]'
                        print(f"Audio file generated for card {card_num}: {audio_filename}")
                    else:
                        audio = f"Audio for card {card_num} (API returned status {response_tts.status_code})"
                        print(f"TTS API Error for card {card_num}: {response_tts.text}")
                except Exception as e:
                    audio = f"Audio for card {card_num} (API error: {str(e)})"
                    print(f"TTS Exception for card {card_num}: {str(e)}")

            writer.writerow({
                'Card_Number': card_num,
                'Image': f'<img src="{card_file}">',
                'English': english_text,
                'Pronunciation': pronunciation,
                'Translation': translation,
                'Audio': audio
            })

if __name__ == "__main__":
    input_directory = "cards_output"
    output_directory = "anki_cards_output"
    #start_card_num = 41
    #end_card_num = 640
    start_card_num = 265
    end_card_num = 271
    csv_file_path = os.path.join(output_directory, "anki_cards.csv")
    
    # Filter and organize cards
    filtered_cards, cards_dir = filter_and_organize_cards(input_directory, output_directory, start_card_num, end_card_num)
    print(f"Filtered {len(filtered_cards)} cards (from card {start_card_num} to card {end_card_num}) and saved to {cards_dir}")
    
    # Create CSV for Anki
    create_anki_csv(cards_dir, csv_file_path)
    print(f"Anki CSV file created at {csv_file_path}. Please fill in the English, Pronunciation, and Translation fields manually.")
