import { useEffect, useRef } from "react";
import * as echarts from "echarts";
import type { EChartsOption } from "echarts";

const FONT = { fontFamily: "Avenir Next, Gill Sans, Trebuchet MS, sans-serif", fontWeight: 800 as const };

export function chartTextStyle(color = "#171612") {
  return { color, ...FONT };
}

/** Thin declarative wrapper over echarts with auto-resize. */
export function Chart({
  option,
  className = "",
  height = 220,
}: {
  option: EChartsOption;
  className?: string;
  height?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const instRef = useRef<echarts.ECharts | null>(null);

  useEffect(() => {
    if (!ref.current) return;
    const inst = echarts.init(ref.current, undefined, {
      renderer: "canvas",
      devicePixelRatio: Math.min(window.devicePixelRatio || 1, 3),
    });
    instRef.current = inst;
    const ro = new ResizeObserver(() => inst.resize());
    ro.observe(ref.current);
    return () => {
      ro.disconnect();
      inst.dispose();
      instRef.current = null;
    };
  }, []);

  useEffect(() => {
    instRef.current?.setOption(option, true);
  }, [option]);

  return <div ref={ref} className={className} style={{ height, width: "100%" }} />;
}
