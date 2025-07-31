// Convert note to valve combination (simplified mapping for trumpet)
export const noteToValveCombination = (noteName) => {
  // This is a simplified mapping for demonstration purposes
  // A real implementation would need a more accurate mapping
  const valveMap = {
    'C4': [], 'C#4': [1], 'D4': [1], 'D#4': [2], 'E4': [2], 'F4': [1, 2],
    'F#4': [3], 'G4': [3], 'G#4': [1, 3], 'A4': [1, 3], 'A#4': [2, 3], 'B4': [2, 3],
    'C5': [1, 2, 3], 'C#5': [1, 2, 3], 'D5': [1, 2, 3], 'D#5': [1, 2, 3], 'E5': [1, 2, 3]
  };
  
  // For notes not in the map, return a default combination
  return valveMap[noteName] || [];
};

// Check if the pressed combination is correct
export const isCorrectCombination = (expectedCombination, pressedButtons) => {
  return expectedCombination.length === pressedButtons.size &&
    expectedCombination.every(valve => pressedButtons.has(valve)) &&
    Array.from(pressedButtons).every(button => expectedCombination.includes(button));
};

// Apply valve combinations to extracted notes
export const applyValveCombinations = (notes) => {
  return notes.map(note => ({
    ...note,
    valveCombination: noteToValveCombination(note.name)
  }));
};
