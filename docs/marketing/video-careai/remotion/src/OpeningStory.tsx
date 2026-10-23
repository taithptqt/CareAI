import React from 'react';
import {AbsoluteFill, CanvasImage, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

export type OpeningStoryProps = {connectionAt?: number};

const easeOut = (value: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, value)), 3);

export const OpeningStory: React.FC<OpeningStoryProps> = ({connectionAt = 2.5}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const seconds = frame / fps;
  const titleIn = easeOut(seconds / 0.55);
  const peopleIn = easeOut((seconds - 0.12) / 0.7);
  const supportIn = easeOut((seconds - 0.36) / 0.65);
  const linked = easeOut((seconds - connectionAt) / 0.7);
  const pulse = 0.5 + Math.sin(seconds * 2.2) * 0.5;

  return <AbsoluteFill style={{background: '#08131f', overflow: 'hidden', fontFamily: '"Segoe UI", Arial, sans-serif', color: '#effffb'}}>
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 50% 49%,#153c4266,transparent 62%),linear-gradient(155deg,#102c3a,#08131f 70%)'}}/>
    <div style={{position: 'absolute', left: 82, top: 94, display: 'flex', alignItems: 'center', gap: 15, opacity: titleIn}}>
      <CanvasImage src={staticFile('brand/logo.png')} premountFor={fps} style={{width: 54, height: 54, objectFit: 'contain'}}/>
      <span style={{fontSize: 34, fontWeight: 700, letterSpacing: 1}}>CareAI</span>
    </div>
    <div style={{position: 'absolute', left: 70, right: 70, top: 230, textAlign: 'center', fontSize: 94, fontWeight: 750, lineHeight: 1.18, letterSpacing: -2.8, opacity: titleIn, translate: `0px ${(1 - titleIn) * 30}px`}}>
      <div>Đi làm xa nhà</div>
      <div style={{color: '#91ffdd', marginTop: 9}}>Vẫn gần cha mẹ</div>
    </div>

    <svg width="1080" height="1920" viewBox="0 0 1080 1920" aria-hidden="true" style={{position: 'absolute'}}>
      <defs>
        <linearGradient id="opening-story-card" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#153b49"/><stop offset="1" stopColor="#0d2432"/></linearGradient>
        <linearGradient id="opening-story-link" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="#3cbed4"/><stop offset="0.5" stopColor="#9affd8"/><stop offset="1" stopColor="#3cbed4"/></linearGradient>
        <radialGradient id="opening-story-glow"><stop offset="0" stopColor="#3ce0ba" stopOpacity="0.22"/><stop offset="1" stopColor="#3ce0ba" stopOpacity="0"/></radialGradient>
      </defs>

      <g opacity={peopleIn} transform={`translate(0,${(1 - peopleIn) * 35})`}>
        <rect x="82" y="674" width="348" height="484" rx="34" fill="url(#opening-story-card)" stroke="#3b7280" strokeOpacity="0.7" strokeWidth="1.5"/>
        <rect x="650" y="674" width="348" height="484" rx="34" fill="url(#opening-story-card)" stroke="#3b7280" strokeOpacity="0.7" strokeWidth="1.5"/>

        <g transform="translate(256,858)">
          <rect x="-102" y="-109" width="102" height="173" rx="10" fill="#1b4b59" stroke="#4f8e9c" strokeWidth="2"/>
          <path d="M-80 -83 H-64 M-42 -83 H-26 M-80 -55 H-64 M-42 -55 H-26 M-80 -27 H-64 M-42 -27 H-26" stroke="#72b2ba" strokeWidth="6" strokeLinecap="round"/>
          <circle cx="34" cy="-42" r="30" fill="#b2eddf"/>
          <path d="M-22 72 C-22 20 -4 -2 34 -2 C72 -2 90 20 90 72 Z" fill="#5db9ad"/>
          <path d="M22 -1 L34 17 L46 -1" fill="#e6fff3"/>
          <rect x="21" y="44" width="76" height="56" rx="9" fill="#12333f" stroke="#acebdc" strokeWidth="3"/>
          <path d="M44 44 V33 H73 V44 M22 67 H96" fill="none" stroke="#acebdc" strokeWidth="3"/>
        </g>

        <g transform="translate(824,858)">
          <path d="M-107 -24 L0 -112 L107 -24" fill="none" stroke="#70bfbc" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M-83 -31 V96 H83 V-31" fill="#183e49" stroke="#70bfbc" strokeWidth="5" strokeLinejoin="round"/>
          <circle cy="-21" r="28" fill="#b2eddf"/>
          <path d="M-22 -35 C-10 -51 10 -51 22 -35" fill="none" stroke="#f1fff7" strokeWidth="9" strokeLinecap="round"/>
          <path d="M-53 86 C-53 42 -33 15 0 15 C33 15 53 42 53 86 Z" fill="#5db9ad"/>
          <path d="M-7 -27 H-23 M7 -27 H23 M-7 -27 H7" fill="none" stroke="#24565e" strokeWidth="3" strokeLinecap="round"/>
          <circle cx="-15" cy="-25" r="9" fill="none" stroke="#24565e" strokeWidth="2"/>
          <circle cx="15" cy="-25" r="9" fill="none" stroke="#24565e" strokeWidth="2"/>
        </g>

        <g textAnchor="middle" fontSize="34" fontWeight="650" fill="#edfff8">
          <text x="256" y="1077">Bạn đi làm xa</text><text x="824" y="1077">Cha mẹ ở nhà</text>
        </g>
        <g textAnchor="middle" fontSize="27" fill="#8fb9bd">
          <text x="256" y="1121">Bận rộn mỗi ngày</text><text x="824" y="1121">Vẫn luôn được quan tâm</text>
        </g>
      </g>

      <path d="M432 917 H648" stroke="#466774" strokeWidth="3" strokeDasharray="6 11" opacity={peopleIn * 0.65}/>
      <g opacity={linked}>
        <circle cx="540" cy="917" r={148 + pulse * 10} fill="url(#opening-story-glow)"/>
        <path d="M430 917 H650" stroke="url(#opening-story-link)" strokeWidth="4" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - linked}/>
        <circle cx="540" cy="917" r={85 + pulse * 4} fill="none" stroke="#67e7c8" strokeOpacity="0.24" strokeWidth="1.5"/>
        <circle cx="540" cy="917" r="70" fill="#0c2732" stroke="#66e6c9" strokeWidth="2"/>
        {[0, 1].map((index) => {
          const phase = ((Math.max(0, seconds - connectionAt) * 0.55 + index * 0.5) % 1);
          return <circle key={index} cx={435 + phase * 210} cy="917" r="4" fill="#c4ffe7" opacity={Math.sin(phase * Math.PI)}/>;
        })}
      </g>
    </svg>

    <CanvasImage src={staticFile('brand/logo.png')} premountFor={fps} style={{position: 'absolute', left: 495, top: 872, width: 90, height: 90, objectFit: 'contain', opacity: linked, scale: 0.8 + linked * 0.2}}/>
    <div style={{position: 'absolute', left: 448, top: 1028, width: 184, textAlign: 'center', color: '#a0f9db', fontSize: 31, fontWeight: 700, opacity: linked}}>CareAI</div>

    <div style={{position: 'absolute', top: 1355, left: 82, right: 82, padding: '28px 16px', borderTop: '1px solid #2c575d', borderBottom: '1px solid #2c575d', textAlign: 'center', color: '#b9e8db', fontSize: 39, lineHeight: 1.35, fontWeight: 500, opacity: supportIn, translate: `0px ${(1 - supportIn) * 20}px`}}>Theo dõi sức khỏe · Giữ kết nối</div>
    <div style={{position: 'absolute', left: 82, right: 82, top: 1860, textAlign: 'center', fontSize: 23, color: '#668f9a', letterSpacing: 1}}>GIAO DIỆN VÀ TÌNH HUỐNG MINH HỌA</div>
  </AbsoluteFill>;
};
