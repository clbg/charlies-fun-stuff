import React, { useRef } from 'react';

const FileUpload = ({ musicXmlFile, onFileUpload }) => {
  const fileInputRef = useRef(null);

  return (
    <div className="section">
      <h2>Upload MusicXML File</h2>
      <input
        type="file"
        ref={fileInputRef}
        onChange={onFileUpload}
        accept=".mxl,.xml,.musicxml"
        style={{ display: 'none' }}
      />
      <button onClick={() => fileInputRef.current.click()}>
        {musicXmlFile ? 'Change File' : 'Select MusicXML File'}
      </button>
      {musicXmlFile && <p>Selected: {musicXmlFile.name}</p>}
    </div>
  );
};

export default FileUpload;
