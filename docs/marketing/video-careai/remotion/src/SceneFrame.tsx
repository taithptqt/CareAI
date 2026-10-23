import React from 'react';
import {AbsoluteFill, CanvasImage, Easing, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {MotionBackdrop} from './MotionBackdrop';
import {MotionOverlay, type MotionMode} from './MotionOverlay';

export type Shot = {file: string; width: number; height: number; crop?: {top: number; height: number}; focus?: {top:number; height:number; width?:number}; masks?: {left:number; top:number; width:number; height:number}[]};
type Props = {chapter:string; title:string; subtitle:string; accent?:string; shot?:Shot; secondShot?:Shot; switchAt?:number; ending?:boolean};
const clamp = {extrapolateLeft:'clamp', extrapolateRight:'clamp'} as const;
const ease={...clamp,easing:Easing.bezier(0.16,1,0.3,1)};

const Screen = ({shot,mode,elapsedSeconds,interactionScale=1.25,acknowledgedAt=4.35}:{shot:Shot;mode?:MotionMode;elapsedSeconds:number;interactionScale?:number;acknowledgedAt?:number}) => {
  const frame=useCurrentFrame()*1.25;
  const {fps}=useVideoConfig();
  const focus=shot.focus?interpolate(frame,[0.9*fps,2.2*fps],[0,1],ease):0;
  const width=shot.crop ? 800 : 504+((shot.focus?.width ?? 780)-504)*focus;
  const imageHeight=width*shot.height/shot.width;
  const cropTop=(shot.crop?.top ?? (shot.focus?.top ?? 0)*focus)*imageHeight;
  const height=shot.crop ? shot.crop.height*imageHeight : imageHeight*(1+((shot.focus?.height ?? 1)-1)*focus);
  return <div style={{width, height, marginTop:shot.focus?Math.max(0,(1040-height)/2):0,position:'relative', overflow:'hidden', borderRadius:shot.crop?32:42, border:'3px solid #34475f', background:'#111a2a', boxShadow:'0 36px 90px #0008'}}>
    <div style={{position:'absolute',top:-cropTop,left:0,width,height:imageHeight}}>
      <CanvasImage src={staticFile(`screens/${shot.file}`)} premountFor={fps} style={{width:'100%',height:'100%'}} />
      {shot.masks?.map((m,i)=><div key={i} style={{position:'absolute',left:`${m.left}%`,top:`${m.top}%`,width:`${m.width}%`,height:`${m.height}%`,background:'#19334b',borderRadius:5}}/>)}
      {mode && <div style={{position:'absolute',top:0,left:0,width:504,height:1120,scale:width/504,transformOrigin:'top left'}}><MotionOverlay mode={mode} accent={mode==='ack'?'#ffb454':mode==='incident'?'#38bdf8':'#ff6969'} elapsedSeconds={elapsedSeconds} timeScale={interactionScale} acknowledgedAt={acknowledgedAt}/></div>}
    </div>
  </div>;
};

export const SceneFrame:React.FC<Props>=({chapter,title,subtitle,accent='#28dac4',shot,secondShot,switchAt=6,ending=false})=>{
  const rawFrame=useCurrentFrame();
  const frame=rawFrame*1.25;
  const {fps,durationInFrames}=useVideoConfig();
  const current=secondShot && rawFrame>=switchAt*fps ? secondShot : shot;
  const seconds=rawFrame/fps;
  const swap=interpolate(rawFrame,[(switchAt-0.2)*fps,(switchAt+0.28)*fps],[0,1],ease);
  const motion=chapter==='LỜI MỞ'?0:chapter==='KẾT NỐI'?1:chapter==='THEO DÕI'?2:chapter==='CÁ NHÂN HÓA'?3:chapter==='CHỦ ĐỘNG'?4:chapter==='XÁC NHẬN'?5:chapter==='CẢNH BÁO'?6:chapter==='PHẢN HỒI'?7:8;
  const badges=[['Quan tâm','Gia đình'],['Người cao tuổi','Người thân'],['Dữ liệu thiết bị','Lần cập nhật'],['Ban ngày','Ban đêm'],['SOS','Cần giúp'],['Hủy chạm nhầm','Gửi ngay'],['Té ngã','Mở sự cố'],['Vị trí','Gọi liên hệ'],['Gia đình','Tiếp nhận']][motion];
  const overlayMode=motion===4?'sos':motion===5?'confirm':motion===6?'alert':motion===7?'incident':motion===8?'ack':undefined;
  const sceneSeconds=durationInFrames/fps;
  const interactionScale=overlayMode==='sos'?2.7/Math.min(1.8,sceneSeconds*.42):overlayMode==='confirm'?2.95/Math.min(2,sceneSeconds*.52):overlayMode==='incident'?2.85/Math.min(1.6,sceneSeconds*.34):overlayMode==='ack'?2.1/Math.min(1.5,sceneSeconds*.28):1.25;
  return <AbsoluteFill style={{background:'#08131f',fontFamily:'"Segoe UI", Arial, sans-serif',color:'#f5fbff',overflow:'hidden'}}>
    <AbsoluteFill style={{background:`radial-gradient(ellipse at 50% 48%, ${accent}22 0%, transparent 64%), linear-gradient(150deg,#102537 0%,#08131f 55%,#0c192b 100%)`}}/>
    <svg width="1080" height="1920" style={{position:'absolute',opacity:0.12}}><defs><pattern id="grid" width="100" height="100" patternUnits="userSpaceOnUse"><path d="M 100 0 L 0 0 0 100" fill="none" stroke="#6d91ab" strokeWidth="1"/></pattern></defs><rect width="1080" height="1920" fill="url(#grid)"/></svg>
    <MotionBackdrop accent={accent}/>
    <AbsoluteFill style={{opacity:interpolate(frame,[0,0.6*fps],[0,1],clamp)}}>
      <div style={{position:'absolute',left:82,top:100,display:'flex',alignItems:'center',gap:15}}><CanvasImage src={staticFile('brand/logo.png')} premountFor={fps} style={{width:54,height:54,objectFit:'contain'}}/><span style={{fontSize:34,fontWeight:700,letterSpacing:1}}>CareAI</span></div>
      <div style={{position:'absolute',right:82,top:116,fontSize:24,letterSpacing:3,color:accent,fontWeight:600}}>{chapter}</div>
      <div style={{position:'absolute',left:82,right:82,top:210,opacity:interpolate(frame,[0,0.6*fps],[0,1],clamp),translate:interpolate(frame,[0,0.8*fps],['0px 28px','0px 0px'],{...clamp,easing:Easing.bezier(0.16,1,0.3,1)})}}>
        <div style={{fontSize:84,fontWeight:750,lineHeight:1.15,letterSpacing:-2.8}}>{title.split('\n').map((line,i)=><div key={i} style={{overflow:'hidden',paddingBottom:5}}><div style={{translate:interpolate(frame,[(0.12+i*0.16)*fps,(0.95+i*0.16)*fps],['0px 120px','0px 0px'],ease),opacity:interpolate(frame,[(0.12+i*0.16)*fps,(0.6+i*0.16)*fps],[0,1],clamp),color:i===1?accent:'#f5fbff'}}>{line}</div></div>)}</div>
        {subtitle && <div style={{marginTop:26,fontSize:36,lineHeight:1.4,color:'#a9c3d5',opacity:interpolate(frame,[0.6*fps,1.2*fps],[0,1],clamp),translate:interpolate(frame,[0.6*fps,1.2*fps],['30px 0px','0px 0px'],ease)}}>{subtitle}</div>}
      </div>
      {current && <>
        <div style={{position:'absolute',top:current.crop?620:530,left:0,right:0,height:1100,display:'flex',justifyContent:'center',perspective:1600,scale:interpolate(frame,[0,1.3*fps,durationInFrames],[0.8,1.01,1.04],ease),translate:`${Math.sin(seconds*0.65)*14}px ${interpolate(frame,[0,1.3*fps],[160,0],ease)+Math.sin(seconds*1.05)*9}px`,rotate:`${interpolate(frame,[0,1.3*fps],[-5,0],ease)+Math.sin(seconds*0.6)*0.7}deg`}}>
          {shot && <div style={{position:'absolute',opacity:secondShot?1-swap:1,translate:`${secondShot?swap*-220:0}px 0px`,rotate:`${secondShot?swap*-5:0}deg`}}><Screen shot={shot} mode={overlayMode==='ack' || (overlayMode && (overlayMode!=='incident' || seconds<switchAt-0.25))?overlayMode:undefined} elapsedSeconds={seconds} interactionScale={interactionScale} acknowledgedAt={switchAt+.28}/></div>}
          {secondShot && <div style={{position:'absolute',opacity:swap,translate:`${(1-swap)*300}px 0px`,rotate:`${(1-swap)*7}deg`}}><Screen shot={secondShot} mode={overlayMode==='ack'?overlayMode:undefined} elapsedSeconds={seconds} interactionScale={interactionScale} acknowledgedAt={switchAt+.28}/></div>}
        </div>
        {motion>0 && !current.crop && !current.focus && badges.map((label,i)=><div key={label} style={{position:'absolute',top:770+i*470,left:i===0?95:760,border:`1px solid ${accent}70`,background:'#102b3aee',boxShadow:`0 12px 50px ${accent}20`,color:'#e9ffff',borderRadius:22,padding:'17px 22px',fontSize:27,fontWeight:600,opacity:interpolate(frame,[(1.2+i*0.4)*fps,(1.7+i*0.4)*fps],[0,1],clamp),translate:`${interpolate(frame,[(1.2+i*0.4)*fps,(1.9+i*0.4)*fps],[i===0?-90:90,0],ease)}px ${Math.sin(seconds*1.8+i)*9}px`,rotate:`${Math.sin(seconds*0.8+i)*1.5}deg`}}>{label}</div>)}
      </>}
      {ending && <div style={{position:'absolute',top:650,left:82,right:82,textAlign:'center'}}>
        <div style={{position:'relative',display:'inline-flex',scale:spring({frame:Math.max(0,frame-0.4*fps),fps,config:{damping:13,stiffness:80}})}}><div style={{position:'absolute',inset:-65,border:`2px solid ${accent}60`,borderRadius:'50%',scale:1+0.06*Math.sin(seconds*2)}}/><CanvasImage src={staticFile('brand/logo.png')} premountFor={fps} style={{width:280,height:280,objectFit:'contain',translate:`0px ${Math.sin(seconds*1.4)*10}px`}}/></div>
        <div style={{fontSize:122,fontWeight:750,letterSpacing:-5,marginTop:25,opacity:interpolate(frame,[0.8*fps,1.5*fps],[0,1],clamp),translate:interpolate(frame,[0.8*fps,1.5*fps],['0px 50px','0px 0px'],ease)}}>CareAI<span style={{color:accent}}>.</span></div>
        <div style={{marginTop:65,fontSize:53,lineHeight:1.4,color:'#bfece6',opacity:interpolate(frame,[1.3*fps,2.1*fps],[0,1],clamp)}}>Kết nối quan tâm,<br/>cùng gia đình chăm sóc.</div>
        <div style={{marginTop:75,fontSize:32,lineHeight:1.5,color:'#a9c3d5'}}>Hỗ trợ theo dõi và cảnh báo.</div>
      </div>}
      <div style={{position:'absolute',left:82,right:82,bottom:100,height:3,background:'#23394d'}}><div style={{height:'100%',width:`${Math.min(100,rawFrame/durationInFrames*100)}%`,background:accent}}/></div>
      <div style={{position:'absolute',left:82,bottom:60,fontSize:23,color:'#829bb0'}}>GIAO DIỆN VÀ TÌNH HUỐNG MINH HỌA</div>
    </AbsoluteFill>
  </AbsoluteFill>;
};
