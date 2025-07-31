import React from 'react';

const Instructions = () => {
  return (
    <div className="section">
      <h2>Instructions</h2>
      <ul className="instructions-list">
        <li>Upload a MusicXML file (.mxl or .xml)</li>
        <li>Set your button mappings (keys on your keyboard)</li>
        <li>Press the corresponding keys to play the notes</li>
        <li>Correct notes will advance automatically</li>
        <li>Incorrect notes will be highlighted in red</li>
      </ul>
    </div>
  );
};

export default Instructions;
