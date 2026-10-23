import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

export const MotionBackdrop:React.FC<{accent:string}>=({accent})=>{
  const frame=useCurrentFrame();
  const {fps}=useVideoConfig();
  const t=frame/fps*1.25;
  const path='M 0 130 L 150 130 L 177 110 L 200 149 L 230 36 L 272 220 L 310 105 L 335 130 L 630 130';
  return <AbsoluteFill style={{pointerEvents:'none',overflow:'hidden'}}>
    <div style={{position:'absolute',width:750,height:750,top:460,left:160,borderRadius:'50%',border:`1px solid ${accent}30`,scale:1+Math.sin(t*0.6)*0.08,rotate:`${t*3}deg`}}/>
    <div style={{position:'absolute',width:850,height:850,top:410,left:110,borderRadius:'50%',border:`2px dashed ${accent}17`,rotate:`${-t*5}deg`}}/>
    <div style={{position:'absolute',width:550,height:550,top:500+Math.sin(t*0.5)*110,left:200+Math.cos(t*0.45)*90,borderRadius:'50%',background:`radial-gradient(circle,${accent}1c,transparent 70%)`}}/>
    <svg width="630" height="260" style={{position:'absolute',left:230,top:1250,opacity:0.18}}>
      <path d={path} fill="none" stroke={accent} strokeWidth="3" pathLength={1} strokeDasharray={1} strokeDashoffset={interpolate(frame%(6*fps),[0,3*fps,6*fps],[1,0,-1])}/>
    </svg>
    {Array.from({length:10},(_,i)=><div key={i} style={{position:'absolute',left:100+((i*173)%880)+Math.sin(t*0.5+i)*23,top:420+((i*197)%1040)+Math.cos(t*0.6+i)*30,width:i%3===0?7:4,height:i%3===0?7:4,borderRadius:'50%',background:accent,opacity:0.18+0.16*Math.sin(t*1.2+i)}}/>)}
  </AbsoluteFill>;
};
