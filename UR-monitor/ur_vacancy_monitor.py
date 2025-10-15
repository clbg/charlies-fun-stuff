#!/usr/bin/env python3
"""
UR Vacancy Monitor Script
Monitors UR-NET vacancy API every minute and sends Slack notifications when rooms are available.
"""

import requests
import json
import time
import logging
import os
from datetime import datetime

SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
UR_API_URL = "https://chintai.r6.ur-net.go.jp/chintai/api/bukken/search/map_marker/"

if not SLACK_WEBHOOK_URL:
    raise ValueError("SLACK_WEBHOOK_URL environment variable is required")

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('ur_monitor.log'),
        logging.StreamHandler()
    ]
)

def get_ur_vacancies():
    """Fetch vacancy data from UR-NET API"""
    headers = {
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,ja;q=0.6',
        'Connection': 'keep-alive',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'DNT': '1',
        'Origin': 'https://www.ur-net.go.jp',
        'Referer': 'https://www.ur-net.go.jp/',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
        'sec-ch-ua': '"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"macOS"'
    }

    data = {
        'rent_low': '',
        'rent_high': '',
        'floorspace_low': '',
        'floorspace_high': '',
        'ne_lat': '35.543363865095884',
        'ne_lng': '139.7336503574712',
        'sw_lat': '35.501729406951156',
        'sw_lng': '139.64816299174853',
        'small': 'false'
    }

    try:
        response = requests.post(UR_API_URL, headers=headers, data=data, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        logging.error(f"Error fetching UR data: {e}")
        return None
    except json.JSONDecodeError as e:
        logging.error(f"Error parsing JSON response: {e}")
        return None

def send_slack_notification(available_properties):
    """Send notification to Slack webhook"""
    total_rooms = sum(prop['roomCount'] for prop in available_properties)

    # Build the complete message with all details in one msg field
    msg_parts = [f"🏠 UR Vacancy Alert! Found {len(available_properties)} properties with {total_rooms} available rooms at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]

    # Add details for each property with clickable links
    for prop in available_properties:
        property_url = f"https://www.ur-net.go.jp/chintai/kanto/kanagawa/{prop['id']}.html"
        msg_parts.append(f"• Property {prop['id']}: {prop['roomCount']} rooms available - {property_url}")

    message = {
        "msg": "\n".join(msg_parts)
    }

    # Print message for debugging
    print("=== DEBUG: Slack Message ===")
    print(json.dumps(message, indent=2, ensure_ascii=False))
    print("============================")

    try:
        response = requests.post(
            SLACK_WEBHOOK_URL,
            json=message,
            headers={'Content-Type': 'application/json'},
            timeout=10
        )
        response.raise_for_status()
        logging.info(f"Slack notification sent successfully for {len(available_properties)} properties")
        return True
    except requests.exceptions.RequestException as e:
        logging.error(f"Error sending Slack notification: {e}")
        return False

def monitor_vacancies():
    """Main monitoring loop"""
    logging.info("Starting UR vacancy monitoring...")

    while True:
        try:
            logging.info("Checking for vacancies...")
            vacancies = get_ur_vacancies()

            if vacancies is None:
                logging.warning("Failed to fetch vacancy data, retrying in 1 minute...")
                time.sleep(60)
                continue

            # Filter properties with available rooms (roomCount > 0)
            available_properties = [prop for prop in vacancies if prop.get('roomCount', 0) > 0]

            if available_properties:
                logging.info(f"Found {len(available_properties)} properties with available rooms!")
                send_slack_notification(available_properties)
            else:
                logging.info("No available rooms found")

            # Wait for 1 minute before next check
            logging.info("Waiting 60 seconds before next check...")
            time.sleep(60)

        except KeyboardInterrupt:
            logging.info("Monitoring stopped by user")
            break
        except Exception as e:
            logging.error(f"Unexpected error: {e}")
            logging.info("Continuing monitoring after error...")
            time.sleep(60)

if __name__ == "__main__":
    monitor_vacancies()
