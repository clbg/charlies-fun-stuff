import React from 'react';

const PracticeArea = ({ 
  currentNote, 
  currentNoteIndex, 
  notes, 
  feedback, 
  isCorrect, 
  onPrevNote, 
  onNextNote 
}) => {
  if (!currentNote) {
    return (
      <div className="section">
        <h2>Practice</h2>
        <p className="instructions">Upload a MusicXML file to begin practicing</p>
      </div>
    );
  }

  return (
    <div className="section">
      <h2>Practice</h2>
      <div className="practice-area">
        <div className="note-display">
          <h3>Current Note: {currentNote.name}</h3>
          <p>Press the correct buttons for this note</p>
        </div>
        
        <div className="valve-indicator">
          <h4>Valve Combination:</h4>
          <div className="valves">
            {[1, 2, 3].map(valve => (
              <div 
                key={valve} 
                className={`valve ${currentNote.valveCombination.includes(valve) ? 'active' : ''}`}
              >
                {valve}
              </div>
            ))}
          </div>
        </div>
        
        <div className="controls">
          <button onClick={onPrevNote} disabled={currentNoteIndex === 0}>
            Previous Note
          </button>
          <button onClick={onNextNote} disabled={currentNoteIndex === notes.length - 1}>
            Next Note
          </button>
        </div>
        
        <div className={`feedback ${isCorrect === true ? 'correct' : isCorrect === false ? 'incorrect' : ''}`}>
          {feedback}
        </div>
      </div>
    </div>
  );
};

export default PracticeArea;
