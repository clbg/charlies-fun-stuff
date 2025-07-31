import { useEffect, useRef, useState } from 'react';
import { OpenSheetMusicDisplay } from 'opensheetmusicdisplay';

const SheetMusicDisplay = ({
  file,        // File | Blob
  options = {},// 传给 OSMD 的构造参数（可选）
  onRendered,  // 渲染完成 (osmd) => void（可选）
  onError,     // 出错回调 (err) => void（可选）
}) => {
  const containerRef = useRef(null);
  const osmdRef = useRef(null);
  const [status, setStatus] = useState('idle');  // idle | loading | ready | error
  const [errorMsg, setErrorMsg] = useState('');

  // 初始化 OSMD（仅一次）
  useEffect(() => {
    if (!containerRef.current || osmdRef.current) return;

    osmdRef.current = new OpenSheetMusicDisplay(containerRef.current, {
      autoResize: true,
      backend: 'svg',
      drawCredits: false,
      drawingParameters: 'compacttight',
      ...options,
    });

    return () => {
      if (osmdRef.current) {
        try { osmdRef.current.clear(); } catch (_) {}
        osmdRef.current = null;
      }
    };
    // 不把 options 放入依赖，避免重复创建
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [containerRef]);

  // 根据 file 加载并渲染
  useEffect(() => {
    console.error("ff",file)
    let cancelled = false;

    const load = async () => {
      if (!osmdRef.current || !file) return;
      setStatus('loading');
      setErrorMsg('');

      try {
        const name = (file.name || '').toLowerCase();
        const ext = name.split('.').pop();
        const isMxl =
          ext === 'mxl' ||
          file.type === 'application/vnd.recordare.musicxml' ||
          file.type === 'application/zip';

        let inputForOsmd;
        if (isMxl) {
          // .mxl：读为 ArrayBuffer 直接传给 OSMD
          inputForOsmd = await file.arrayBuffer();
        } else {
          // .xml/.musicxml：读文本
          inputForOsmd = await file.text();
        }

        const xml = await file.text();
    await osmdRef.current.load(xml);

        //await osmdRef.current.load(inputForOsmd);
        await osmdRef.current.render();

        if (!cancelled) {
          setStatus('ready');
          onRendered?.(osmdRef.current);
        }
      } catch (err) {
        console.error('Error loading/rendering MusicXML:', err);
        if (!cancelled) {
          setStatus('error');
          setErrorMsg(err?.message || 'Failed to load score.');
          onError?.(err);
        }
      }
    };

    load();
    return () => { cancelled = true; };
  }, [file, onRendered, onError]);

  return (
    <div className="sheet-music-display-container" style={{ width: '100%', minHeight: 120 }}>
      {status === 'loading' && <p>Loading score…</p>}
      {status === 'error' && (
        <p style={{ color: 'crimson' }}>
          加载失败：{errorMsg}
          {errorMsg?.includes('Document is not an XML document') && '（文件可能不是有效的 MusicXML）'}
        </p>
      )}
      <div ref={containerRef} className="osmd-container" />
    </div>
  );
};

export default SheetMusicDisplay;
