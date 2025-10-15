# UR Vacancy Monitor

A Python script that monitors UR-NET (Urban Renaissance Agency) rental property vacancies and sends Slack notifications when rooms become available.

## Features

- Monitors the UR-NET API every 60 seconds
- Filters properties where `roomCount > 0` (available rooms)
- Sends detailed Slack notifications with property details
- Comprehensive logging to both console and log file
- Error handling for network issues and API failures
- Graceful shutdown with Ctrl+C

## Quick Setup

**Option 1: Automated Setup (Recommended)**
```bash
cd /Users/pencheng/projects/charlies-fun-stuff/UR-monitor
./setup.sh
```

**Option 2: Manual Setup**
1. **Create and activate virtual environment:**
   ```bash
   python3 -m venv ur_env
   source ur_env/bin/activate
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

## Running the Monitor

**With virtual environment:**
```bash
source ur_env/bin/activate
python ur_vacancy_monitor.py
```

**With direnv (if installed):**
```bash
direnv allow  # First time only
python ur_vacancy_monitor.py
```

## Configuration

The script is pre-configured with:
- Slack webhook URL for notifications
- UR-NET API endpoint and search parameters
- Tokyo area coordinates (can be modified in the script)

## Output

**Slack notification format:**
```json
{
  "msg": "🏠 UR Vacancy Alert! Found 3 properties with 5 available rooms at 2025-10-15 11:10:00",
  "details": "• Property 40_3070: 1 rooms available\n• Property 40_3080: 1 rooms available\n• Property 40_3090: 1 rooms available"
}
```

**Log file:** `ur_monitor.log` - Contains detailed monitoring activity

## Files

- `ur_vacancy_monitor.py` - Main monitoring script
- `requirements.txt` - Python dependencies
- `setup.sh` - Automated environment setup script
- `.envrc` - Direnv configuration for automatic environment activation
- `README.md` - This documentation
- `ur_env/` - Virtual environment directory (created by setup)
- `ur_monitor.log` - Generated log file (created when script runs)

## Usage

The script will run continuously until stopped with Ctrl+C, checking for vacancies every minute and only sending notifications when rooms are actually available.
