import React from 'react';
import {interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

export type HealthFeatureHighlightsProps = {
  metricsAt?: number;
  chartsAt?: number;
  insightsAt?: number;
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const FeatureIcon = ({stage, progress}: {stage: number; progress: number}) => <svg width="90" height="90" viewBox="0 0 90 90" aria-hidden="true">
  <rect x="2" y="2" width="86" height="86" rx="25" fill="#143c47" stroke="#59e8d0" strokeOpacity="0.4" strokeWidth="1.5"/>
  {stage === 0 && <>
    <path d="M20 29 C20 16 38 14 45 28 C52 14 70 16 70 29 C70 48 45 64 45 64 C45 64 20 48 20 29 Z" fill="#28dac4" fillOpacity="0.12" stroke="#81f7df" strokeWidth="2.5"/>
    <path d="M13 46 H29 L36 34 L45 60 L55 26 L62 46 H77" fill="none" stroke="#81f7df" strokeWidth="3.5" strokeLinejoin="round" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress}/>
  </>}
  {stage === 1 && <>
    <circle cx="45" cy="45" r="25" fill="none" stroke="#81f7df" strokeWidth="2.5" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress}/>
    <path d="M45 28 V45 L57 52" fill="none" stroke="#81f7df" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"/>
    <circle cx="66" cy="23" r="8" fill="#ffb454" stroke="#143c47" strokeWidth="3"/>
  </>}
  {stage === 2 && <>
    <path d="M29 19 H53 L64 30 V71 H26 V19 Z M51 19 V32 H64" fill="#28dac4" fillOpacity="0.1" stroke="#81f7df" strokeWidth="2.5" strokeLinejoin="round"/>
    <path d="M35 43 H54 M35 53 H54 M35 63 H46" fill="none" stroke="#81f7df" strokeWidth="3" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress}/>
    <path d="M68 39 L71 46 L78 49 L71 52 L68 59 L65 52 L58 49 L65 46 Z" fill="#81f7df"/>
  </>}
</svg>;

/** Feature annotations alongside the supplied screenshot, without synthetic readings. */
export const HealthFeatureHighlights: React.FC<HealthFeatureHighlightsProps> = ({metricsAt = 0.5, chartsAt = 5, insightsAt = 10}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const seconds = frame / fps;
  const starts = [metricsAt, chartsAt, insightsAt];
  const stage = seconds >= insightsAt ? 2 : seconds >= chartsAt ? 1 : 0;
  const labels = [
    ['Nhịp tim · SpO₂', 'Theo dõi dữ liệu sức khỏe'],
    ['Biểu đồ 24 giờ', 'Cảnh báo khi vượt ngưỡng'],
    ['Nhận định xu hướng', 'Báo cáo tuần'],
  ];

  return <div style={{position: 'absolute', left: 82, top: 1360, width: 916, height: 230, pointerEvents: 'none', fontFamily: '"Segoe UI", Arial, sans-serif', opacity: interpolate(frame, [metricsAt * fps, (metricsAt + 0.45) * fps], [0, 1], clamp), translate: interpolate(frame, [metricsAt * fps, (metricsAt + 0.45) * fps], ['0px 25px', '0px 0px'], clamp)}}>
    <div style={{position: 'absolute', inset: 0, borderRadius: 28, border: '1.5px solid #2a6f72', background: 'linear-gradient(110deg,#10323eed,#0a202eef)', boxShadow: '0 15px 50px #0005', overflow: 'hidden'}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: 4, height: '100%', background: '#5eeed4'}}/>
      {labels.map(([title, detail], index) => {
        const start = starts[index];
        const next = starts[index + 1];
        const reveal = interpolate(frame, [start * fps, (start + 0.42) * fps], [0, 1], clamp);
        const leave = next === undefined ? 0 : interpolate(frame, [next * fps, (next + 0.24) * fps], [0, 1], clamp);
        return <div key={title} style={{position: 'absolute', left: 30, right: 30, top: 30, display: 'flex', gap: 28, alignItems: 'center', opacity: reveal * (1 - leave), translate: `${(1 - reveal) * 24 - leave * 20}px 0px`}}>
          <FeatureIcon stage={index} progress={reveal}/>
          <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
            <div style={{color: '#f0fffb', fontSize: 43, fontWeight: 750, lineHeight: 1.2, letterSpacing: -0.7}}>{title}</div>
            <div style={{color: '#b8dcd9', fontSize: 34, lineHeight: 1.3, fontWeight: 500}}>{detail}</div>
          </div>
        </div>;
      })}
      <div style={{position: 'absolute', left: 152, bottom: 27, display: 'flex', gap: 13, alignItems: 'center'}}>
        {starts.map((start, index) => <div key={index} style={{position: 'relative', width: 106, height: 4, borderRadius: 4, background: '#33505d', overflow: 'hidden'}}>
          <div style={{width: `${interpolate(frame, [start * fps, (start + 0.5) * fps], [0, 100], clamp)}%`, height: '100%', background: index === stage ? '#85ffe3' : '#40b9ab'}}/>
        </div>)}
      </div>
    </div>
  </div>;
};
