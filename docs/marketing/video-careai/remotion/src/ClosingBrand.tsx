import React from 'react';
import {AbsoluteFill, CanvasImage, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

export type ClosingBrandProps = {durationInFrames: number};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const easeOut = (value: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, value)), 3);

const FamilySymbol = ({side, progress}: {side: 'elder' | 'family'; progress: number}) => <g opacity={progress}>
  <circle r="65" fill="#12323f" stroke="#48bfae" strokeOpacity="0.65" strokeWidth="2"/>
  <circle r="79" fill="none" stroke="#328c86" strokeOpacity="0.18"/>
  {side === 'elder' ? <>
    <circle cy="-18" r="18" fill="#9cebd9"/>
    <path d="M-34 36 C-34 13 -20 2 0 2 C20 2 34 13 34 36" fill="#74cfc0"/>
    <path d="M-14 -26 C-7 -36 6 -37 16 -26" fill="none" stroke="#e0fff5" strokeWidth="6" strokeLinecap="round"/>
  </> : <>
    <circle cx="-17" cy="-19" r="15" fill="#9cebd9"/>
    <circle cx="24" cy="-10" r="12" fill="#d9f8ef"/>
    <path d="M-44 34 C-44 14 -33 1 -17 1 C0 1 10 14 10 34" fill="#74cfc0"/>
    <path d="M4 34 C4 18 12 7 24 7 C37 7 45 18 45 34" fill="#b5e8d9"/>
  </>}
</g>;

/** Closing composition with a clear hold and no invented distribution links. */
export const ClosingBrand: React.FC<ClosingBrandProps> = ({durationInFrames}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const seconds = frame / fps;
  const titleIn = easeOut(seconds / 0.55);
  const diagramIn = easeOut((seconds - 0.12) / 0.65);
  const brandIn = easeOut((seconds - 0.25) / 0.55);
  const supportIn = easeOut((seconds - 0.45) / 0.6);
  const fadeOut = interpolate(frame, [Math.max(0, durationInFrames - 0.25 * fps), durationInFrames], [1, 0], clamp);
  const linkDraw = easeOut((seconds - 0.32) / 0.65);
  const orbitAngle = seconds * 0.35;

  return <AbsoluteFill style={{overflow: 'hidden', background: '#08131f', color: '#f2fffb', fontFamily: '"Segoe UI", Arial, sans-serif'}}>
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 50% 45%,#17413f66 0%,transparent 58%),linear-gradient(165deg,#0d2635 0%,#08131f 66%,#0a1b29 100%)'}}/>
    <svg width="1080" height="1920" viewBox="0 0 1080 1920" aria-hidden="true" style={{position: 'absolute', opacity: fadeOut}}>
      <defs>
        <radialGradient id="closing-brand-glow"><stop offset="0" stopColor="#40dab9" stopOpacity="0.19"/><stop offset="1" stopColor="#40dab9" stopOpacity="0"/></radialGradient>
        <linearGradient id="closing-brand-link" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="#239fb9"/><stop offset="0.5" stopColor="#79f5ce"/><stop offset="1" stopColor="#239fb9"/></linearGradient>
      </defs>
      <circle cx="540" cy="905" r={340 + Math.sin(seconds * 1.1) * 12} fill="url(#closing-brand-glow)"/>
      <g opacity={diagramIn}>
        <circle cx="540" cy="905" r="165" fill="#11313b" fillOpacity="0.28" stroke="#4be2bf" strokeOpacity="0.22" strokeWidth="1.5"/>
        <circle cx="540" cy="905" r="197" fill="none" stroke="#65d9bd" strokeOpacity="0.11" strokeWidth="1.5"/>
        <circle cx={540 + Math.cos(orbitAngle) * 197} cy={905 + Math.sin(orbitAngle) * 197} r="4" fill="#a1ffdf" opacity="0.7"/>
        <circle cx={540 - Math.cos(orbitAngle) * 197} cy={905 - Math.sin(orbitAngle) * 197} r="3" fill="#68d9e8" opacity="0.55"/>
        <path d="M303 930 C350 930 365 905 402 905 M678 905 C716 905 730 930 777 930" fill="none" stroke="#23545c" strokeWidth="3"/>
        <path d="M303 930 C350 930 365 905 402 905 M678 905 C716 905 730 930 777 930" fill="none" stroke="url(#closing-brand-link)" strokeWidth="3" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - linkDraw} strokeLinecap="round"/>
        {[0, 1].map((index) => {
          const phase = ((seconds * 0.5 + index * 0.5) % 1);
          return <g key={index} opacity={Math.sin(phase * Math.PI) * linkDraw}>
            <circle cx={308 + phase * 88} cy={930 - easeOut(phase) * 25} r="5" fill="#a1ffdf"/>
            <circle cx={683 + phase * 88} cy={905 + easeOut(phase) * 25} r="5" fill="#a1ffdf"/>
          </g>;
        })}
      </g>
      <g transform={`translate(235,930) translate(0,${(1 - diagramIn) * 25})`}><FamilySymbol side="elder" progress={diagramIn}/></g>
      <g transform={`translate(845,930) translate(0,${(1 - diagramIn) * 25})`}><FamilySymbol side="family" progress={diagramIn}/></g>
      <g fill="#a9d9cf" fontSize="30" fontWeight="600" textAnchor="middle" opacity={diagramIn}>
        <text x="235" y="1060">Cha mẹ</text><text x="845" y="1060">Gia đình</text>
      </g>
      <path d="M252 1510 H387 L416 1496 L438 1531 L466 1467 L496 1542 L527 1492 L554 1510 H828" fill="none" stroke="#57d3be" strokeOpacity="0.15" strokeWidth="2.5" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - supportIn}/>
    </svg>

    <div style={{position: 'absolute', inset: 0, opacity: fadeOut}}>
      <div style={{position: 'absolute', top: 144, left: 82, right: 82, textAlign: 'center', fontSize: 25, fontWeight: 650, letterSpacing: 5, color: '#82cfc4', opacity: titleIn}}>KẾT NỐI SỰ QUAN TÂM</div>
      <div style={{position: 'absolute', top: 260, left: 70, right: 70, textAlign: 'center', fontSize: 91, lineHeight: 1.18, fontWeight: 750, letterSpacing: -2.6, opacity: titleIn, translate: `0px ${(1 - titleIn) * 28}px`}}>
        <div>Một kết nối</div>
        <div style={{color: '#8bffda', marginTop: 10}}>Triệu yêu thương</div>
      </div>
      <CanvasImage src={staticFile('brand/logo.png')} premountFor={fps} style={{position: 'absolute', left: 425, top: 790, width: 230, height: 230, objectFit: 'contain', opacity: diagramIn, scale: 0.84 + diagramIn * 0.16}}/>
      <div style={{position: 'absolute', top: 1145, left: 82, right: 82, textAlign: 'center', fontSize: 126, fontWeight: 750, letterSpacing: -5, opacity: brandIn, translate: `0px ${(1 - brandIn) * 22}px`}}>CareAI<span style={{color: '#59e2c2'}}>.</span></div>
      <div style={{position: 'absolute', top: 1370, left: 70, right: 70, textAlign: 'center', color: '#b8e3d8', fontSize: 38, lineHeight: 1.4, fontWeight: 500, opacity: supportIn, translate: `0px ${(1 - supportIn) * 18}px`}}>Quan tâm mỗi ngày · Cùng nhau chăm sóc</div>
      <div style={{position: 'absolute', left: 82, right: 82, top: 1860, textAlign: 'center', color: '#668e9a', fontSize: 23, letterSpacing: 1}}>GIAO DIỆN VÀ TÌNH HUỐNG MINH HỌA</div>
    </div>
  </AbsoluteFill>;
};
