# Trumpet Helper

A web-based application to help trumpet players practice with MusicXML files.

## Features

- Upload and parse MusicXML files (.mxl or .xml)
- Customize button mappings for trumpet valves (1, 2, 3)
- Visual display of notes and required valve combinations
- Interactive practice mode with immediate feedback
- Responsive design that works on desktop and mobile devices

## How to Use

1. **Upload a MusicXML file**: Click the "Select MusicXML File" button to upload a MusicXML file containing the music you want to practice.

2. **Set button mappings**: Customize the keyboard keys that correspond to each trumpet valve:
   - Button 1 (default: A key)
   - Button 2 (default: S key)
   - Button 3 (default: D key)

3. **Practice**: 
   - The current note will be displayed with the required valve combination
   - Press the corresponding keys for the required valve combination
   - Correct combinations will advance to the next note
   - Incorrect combinations will be highlighted in red

4. **Navigation**: Use the "Previous Note" and "Next Note" buttons to navigate through the music.

## Technical Details

This application is built with:
- React.js for the user interface
- Vite as the build tool
- musicxml-interfaces for parsing MusicXML files

## Development

To run the application locally:

1. Install dependencies:
   ```
   npm install
   ```

2. Start the development server:
   ```
   npm run dev
   ```

3. Build for production:
   ```
   npm run build
   ```

## Limitations

- The current implementation uses a simplified mapping of notes to valve combinations
- For a production version, a more comprehensive mapping would be needed
- The MusicXML parsing is simplified and may not handle all complex MusicXML files
