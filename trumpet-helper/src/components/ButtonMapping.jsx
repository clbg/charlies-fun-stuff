import React from 'react';

const ButtonMapping = ({ buttonMappings, onMappingChange, pressedButtons }) => {
  return (
    <div className="section">
      <h2>Button Mapping</h2>
      <div className="button-mapping">
        {[1, 2, 3].map(buttonNumber => (
          <div key={buttonNumber} className="mapping-item">
            <label htmlFor={`button${buttonNumber}`}>Button {buttonNumber}:</label>
            <input
              type="text"
              id={`button${buttonNumber}`}
              value={buttonMappings[buttonNumber]}
              onChange={(e) => onMappingChange(buttonNumber, e.target.value)}
              maxLength={1}
              className={pressedButtons.has(buttonNumber) ? 'pressed' : ''}
            />
          </div>
        ))}
      </div>
      <p className="instructions">
        Map each trumpet button to a key on your keyboard (default: A, S, D)
      </p>
    </div>
  );
};

export default ButtonMapping;
