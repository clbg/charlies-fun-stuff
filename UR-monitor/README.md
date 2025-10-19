# UR Vacancy Monitor

A TypeScript/Node.js application that monitors UR-NET vacancy API and sends Slack notifications when rooms become available.

## Features

- **State Tracking**: Maintains local state to track vacancy changes over time
- **Smart Notifications**:
  - Limits new vacancy alerts to 3 times maximum to prevent spam
  - Notifies about newly added vacancies
  - Notifies about disappeared vacancies
  - Tracks room count increases/decreases
- **TypeScript**: Full type safety and modern JavaScript features
- **Environment Management**: Uses direnv for automatic environment setup

## Setup

1. **Environment Setup**:
   ```bash
   # Make sure you have direnv installed
   # The .envrc file will automatically set up Node.js 18 environment
   direnv allow
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Environment Variables**:
   Create a `.env` file with:
   ```
   SLACK_WEBHOOK_URL=your_slack_webhook_url_here
   ```

4. **Build the Project**:
   ```bash
   npm run build
   ```

## Usage

### Development Mode
```bash
npm run dev
```

### Production Mode
```bash
npm start
```

### Build Only
```bash
npm run build
```

### Watch Mode (for development)
```bash
npm run watch
```

## How It Works

1. **State Persistence**: The application saves state to `vacancy_state.json` to track:
   - Previous property states and room counts
   - Alarm counts for each property (to limit notifications)
   - Last check timestamp

2. **Change Detection**: Compares current API results with saved state to detect:
   - 🆕 **NEW**: Completely new properties with available rooms
   - 📈 **INCREASED**: Existing properties with more available rooms
   - ❌ **DISAPPEARED**: Properties that are no longer available
   - 📉 **DECREASED**: Properties with fewer available rooms

3. **Smart Alerting**:
   - New/increased room notifications are limited to 3 times per property
   - Disappeared/decreased notifications are always sent (no limit)
   - Alarm counts reset when properties disappear

4. **Monitoring Loop**: Checks the UR-NET API every 60 seconds

## File Structure

```
├── src/
│   └── ur_vacancy_monitor.ts    # Main TypeScript source
├── dist/                        # Compiled JavaScript output
├── .envrc                       # direnv configuration
├── package.json                 # Node.js dependencies and scripts
├── tsconfig.json               # TypeScript configuration
└── vacancy_state.json          # Runtime state file (auto-generated)
```

## Migration from Python

This project was migrated from Python to TypeScript/Node.js while maintaining all functionality:

- **Python pickle** → **JSON state file**
- **requests** → **axios**
- **Python logging** → **Custom logging with timestamps**
- **Python environment** → **Node.js with direnv**

The original Python version (`ur_vacancy_monitor.py`) is preserved for reference.
