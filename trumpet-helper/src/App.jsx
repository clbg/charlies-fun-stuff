import { useState, useEffect, useCallback } from 'react';
import './App.css';
import FileUpload from './components/FileUpload';
import ButtonMapping from './components/ButtonMapping';
import PracticeArea from './components/PracticeArea';
import Instructions from './components/Instructions';
import SheetMusicDisplay from './components/SheetMusicDisplay'; // Import the new component
import { isCorrectCombination, applyValveCombinations } from './utils/noteMapping'; // Import applyValveCombinations

function App() {
  // State variables
  const [musicXmlFile, setMusicXmlFile] = useState(null);
  const [notes, setNotes] = useState([]);
  const [currentNoteIndex, setCurrentNoteIndex] = useState(0);
  const [buttonMappings, setButtonMappings] = useState({ 1: 'a', 2: 's', 3: 'd' });
  const [feedback, setFeedback] = useState('');
  const [isCorrect, setIsCorrect] = useState(null);
  const [showControls, setShowControls] = useState(true);

  // Get current note
  const currentNote = notes[currentNoteIndex] || null;

  // Track pressed buttons for combination checking
  const [pressedButtons, setPressedButtons] = useState(new Set());

  // Handle key press for note checking
  const handleKeyPress = useCallback((event) => {
    if (!currentNote) return;

    const key = event.key.toLowerCase();
    
    // Check if the pressed key corresponds to a mapped button
    let pressedButton = null;
    for (const [button, mappedKey] of Object.entries(buttonMappings)) {
      if (mappedKey === key) {
        pressedButton = parseInt(button);
        break;
      }
    }
    
    if (pressedButton !== null) {
      // Add the pressed button to the set of pressed buttons
      setPressedButtons(prev => {
        const newSet = new Set(prev);
        newSet.add(pressedButton);
        return newSet;
      });
      
      // Check if the current combination matches the expected combination
      setTimeout(() => {
        setPressedButtons(currentPressed => {
          const expectedCombination = currentNote.valveCombination;
          
          // Check if the pressed buttons match the expected combination
          if (isCorrectCombination(expectedCombination, currentPressed)) {
            setFeedback(`Correct! Combination ${Array.from(currentPressed).sort()} is right for ${currentNote.name}.`);
            setIsCorrect(true);
            
            // Advance to the next note after a delay
            setTimeout(() => {
              if (currentNoteIndex < notes.length - 1) {
                setCurrentNoteIndex(prev => prev + 1);
                setFeedback('');
                setIsCorrect(null);
              } else {
                setFeedback('Congratulations! You completed the exercise.');
                setIsCorrect(true);
              }
            }, 1500);
          } else if (currentPressed.size >= expectedCombination.length) {
            // If we've pressed enough buttons but they're not correct
            setFeedback(`Incorrect! Combination ${Array.from(currentPressed).sort()} is not right for ${currentNote.name}.`);
            setIsCorrect(false);
          }
          
          return currentPressed;
        });
      }, 100);
    }
  }, [currentNote, buttonMappings, currentNoteIndex, notes.length]);

  // // Reset pressed buttons when changing notes


   useEffect(() => {
  setPressedButtons(new Set());
   setFeedback('');
   setIsCorrect(null);
 }, [currentNoteIndex]);


  // Handle file upload
  const handleFileUpload = async (event) => {
    const file = event.target.files[0];
    if (file) {
      setMusicXmlFile(file);
      setCurrentNoteIndex(0); // Reset note index on new file upload
      setFeedback('File uploaded successfully! Start practicing.');
      setIsCorrect(null);
    }
  };

  // Callback from SheetMusicDisplay when notes are parsed
  const handleNotesParsed = useCallback((parsedNotes) => {
    const notesWithValves = applyValveCombinations(parsedNotes);
    setNotes(notesWithValves);
    setCurrentNoteIndex(0);
  }, []);

  // Handle button mapping changes
  const handleMappingChange = (buttonNumber, key) => {
    setButtonMappings(prev => ({
      ...prev,
      [buttonNumber]: key.toLowerCase()
    }));
  };

  // Add event listener for key presses
useEffect(() => {
  window.addEventListener('keydown', handleKeyPress);
   return () => {
     window.removeEventListener('keydown', handleKeyPress);
   };
 }, [handleKeyPress]);

  // Navigate to next note
  const nextNote = () => {
    if (currentNoteIndex < notes.length - 1) {
      setCurrentNoteIndex(prev => prev + 1);
      setFeedback('');
      setIsCorrect(null);
    }
  };

  // Navigate to previous note
  const prevNote = () => {
    if (currentNoteIndex > 0) {
      setCurrentNoteIndex(prev => prev - 1);
      setFeedback('');
      setIsCorrect(null);
    }
  };

  return (
    <div className={`trumpet-helper ${showControls ? 'controls-visible' : 'controls-hidden'}`}>
      <div className="header">
        <button className="toggle-button" onClick={() => setShowControls(!showControls)}>
          {showControls ? 'Hide Controls' : 'Show Controls'}
        </button>
        {showControls && (
          <>
            <h1>Trumpet Helper</h1>
            
            <FileUpload 
              musicXmlFile={musicXmlFile} 
              onFileUpload={handleFileUpload} 
            />
            
            <ButtonMapping 
              buttonMappings={buttonMappings} 
              onMappingChange={handleMappingChange} 
              pressedButtons={pressedButtons} 
            />
            
            <PracticeArea 
              currentNote={currentNote}
              currentNoteIndex={currentNoteIndex}
              notes={notes}
              feedback={feedback}
              isCorrect={isCorrect}
              onPrevNote={prevNote}
              onNextNote={nextNote}
            />
            
            <Instructions />
          </>
        )}
      </div>

      <div className={`main-content ${showControls ? '' : 'fullscreen'}`}>
        {musicXmlFile && (
          <SheetMusicDisplay 
            file={musicXmlFile} 
            onNotesParsed={handleNotesParsed} 
          />
        )}
      </div>
    </div>
  );
}

export default App;
