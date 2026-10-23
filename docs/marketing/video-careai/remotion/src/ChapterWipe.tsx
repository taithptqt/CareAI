import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig, Easing} from 'remotion';

export const ChapterWipe=({accent='#28dac4'}:{accent?:string})=>{
  const frame=useCurrentFrame();
  const {durationInFrames}=useVideoConfig();
  return <AbsoluteFill style={{pointerEvents:'none',overflow:'hidden'}}>
    <div style={{position:'absolute',inset:-200,background:'#0b2133',translate:interpolate(frame,[0,durationInFrames],['-150% 0%','150% 0%'],{easing:Easing.bezier(0.65,0,0.35,1)}),rotate:'-12deg'}}/>
    <div style={{position:'absolute',top:-200,bottom:-200,width:180,background:accent,opacity:0.85,translate:interpolate(frame,[0,durationInFrames],['-400px 0px','1700px 0px'],{easing:Easing.bezier(0.65,0,0.35,1)}),rotate:'-12deg'}}/>
  </AbsoluteFill>;
};
