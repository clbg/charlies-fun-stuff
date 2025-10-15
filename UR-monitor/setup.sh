#!/bin/bash

# UR Monitor Setup Script
# This script sets up the virtual environment and installs dependencies

set -e  # Exit on any error

echo "🏠 Setting up UR Monitor environment..."

# Create virtual environment if it doesn't exist
if [ ! -d "ur_env" ]; then
    echo "Creating virtual environment..."
    python3 -m venv ur_env
else
    echo "Virtual environment already exists."
fi

# Activate virtual environment
echo "Activating virtual environment..."
source ur_env/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install requirements
echo "Installing dependencies..."
pip install -r requirements.txt

echo "✅ Setup complete!"
echo ""
echo "To use the UR Monitor:"
echo "1. Activate the environment: source ur_env/bin/activate"
echo "2. Run the monitor: python ur_vacancy_monitor.py"
echo ""
echo "Or if you have direnv installed:"
echo "1. Allow direnv: direnv allow"
echo "2. Run the monitor: python ur_vacancy_monitor.py"
