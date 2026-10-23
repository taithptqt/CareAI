import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';

export type MotionMode = 'sos' | 'confirm' | 'alert' | 'incident' | 'ack';

export type MotionOverlayProps = {
  mode: MotionMode;
  accent: string;
  /** Scene time in seconds; omit when mounted in a scene-local sequence. */
  elapsedSeconds?: number;
  /** Playback speed for all illustrative interaction animations. */
  timeScale?: number;
  /** Real scene time when the confirmed screenshot is fully visible. */
  acknowledgedAt?: number;
};

const clamp = (value: number) => Math.min(1, Math.max(0, value));
const easeOut = (value: number) => 1 - Math.pow(1 - clamp(value), 3);

const TapCursor = ({x, y, time, start = 1.8}: {x: number; y: number; time: number; start?: number}) => {
  const local = time - start;
  if (local < 0) return null;
  const phase = local % 3.8;
  const enter = easeOut(phase / 0.55);
  const press = clamp((phase - 0.7) / 0.2) - clamp((phase - 0.92) / 0.24);
  const opacity = clamp(phase / 0.2) * (1 - clamp((phase - 2.1) / 0.4));
  const ripple = clamp((phase - 0.75) / 0.9);
  return <g opacity={opacity}>
    <circle cx={x} cy={y} r={12 + ripple * 48} fill="none" stroke="#ffffff" strokeWidth={4 - ripple * 3} opacity={phase < 0.75 ? 0 : (1 - ripple) * 0.9}/>
    <g transform={`translate(${x + 24 * (1 - enter)},${y + 62 * (1 - enter) + press * 5}) scale(${1 - press * 0.12})`}>
      <path d="M0 0 L3 43 L14 33 L27 57 L39 51 L25 28 L41 25 Z" fill="#ffffff" stroke="#0b253b" strokeWidth="3.5" strokeLinejoin="round"/>
    </g>
  </g>;
};

const Outline = ({x, y, width, height, color, time, radius = 18}: {x: number; y: number; width: number; height: number; color: string; time: number; radius?: number}) => {
  const draw = easeOut((time - 0.4) / 0.9);
  return <g>
    <rect x={x - 5} y={y - 5} width={width + 10} height={height + 10} rx={radius + 4} fill="none" stroke={color} strokeWidth="10" opacity={0.08 + 0.08 * (0.5 + 0.5 * Math.sin(time * 4.2))}/>
    <rect x={x} y={y} width={width} height={height} rx={radius} pathLength="1" fill="none" stroke={color} strokeWidth="3.5" strokeLinecap="round" strokeDasharray="1" strokeDashoffset={1 - draw} opacity={0.65 + 0.25 * Math.sin(time * 3.2)}/>
  </g>;
};

/**
 * Place above a phone screenshot at its top-left, in a 504 px wide coordinate
 * system. All motion is tied to the Remotion frame, so scrubbing is stable.
 * The annotations explain screenshots; they do not introduce health readings.
 */
export const MotionOverlay: React.FC<MotionOverlayProps> = ({mode, accent, elapsedSeconds, timeScale = 1, acknowledgedAt = 4.35}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const realTime = Math.max(0, elapsedSeconds ?? frame / fps);
  const time = realTime * timeScale;
  const fade = easeOut(time / 0.45);
  const accepted = mode === 'ack' && realTime >= acknowledgedAt;
  const acceptedTime = realTime - acknowledgedAt;
  const checkProgress = accepted ? easeOut((acceptedTime - 0.15) / 0.65) : 0;
  return <svg
    width="504"
    height="1120"
    viewBox="0 0 504 1120"
    aria-hidden="true"
    style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', pointerEvents: 'none', opacity: fade}}
  >
    {mode === 'sos' && <>
      {[0, 1, 2].map((index) => {
        const phase = ((time + index * 0.8) % 2.4) / 2.4;
        return <circle key={index} cx="252" cy="610" r={151 + phase * 58} fill="none" stroke={accent} strokeWidth={4 - phase * 2} opacity={(1 - phase) * 0.52}/>;
      })}
      <TapCursor x={252} y={610} time={time} start={2}/>
    </>}

    {mode === 'confirm' && <>
      <Outline x={282} y={679} width={145} height={58} radius={29} color={accent} time={time}/>
      <TapCursor x={356} y={708} time={time} start={2.2}/>
    </>}

    {mode === 'alert' && <>
      <Outline x={9} y={63} width={486} height={218} radius={18} color={accent} time={time}/>
      <g transform={`translate(463,79) rotate(${Math.sin(time * 15) * Math.max(0, 1 - (time % 3) / 0.8) * 14})`}>
        <circle r="26" fill="#152439" stroke={accent} strokeWidth="2"/>
        <path d="M-12 9 H12 L8 4 V-5 A8 8 0 0 0 -8 -5 V4 Z M-4 14 A4 4 0 0 0 4 14" fill="none" stroke="#ffffff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
      </g>
      <TapCursor x={281} y={234} time={time} start={3}/>
    </>}

    {mode === 'incident' && <>
      <Outline x={44} y={904} width={416} height={54} radius={12} color={accent} time={time}/>
      <TapCursor x={262} y={931} time={time} start={2.1}/>
    </>}

    {mode === 'ack' && realTime < acknowledgedAt - 0.6 && <>
      <Outline x={18} y={1007} width={468} height={54} radius={12} color={accent} time={time}/>
      <TapCursor x={252} y={1034} time={time} start={1.4}/>
    </>}

    {accepted && <g transform={`translate(420,120) scale(${0.8 + 0.2 * easeOut(acceptedTime / 0.45)})`} opacity={easeOut(acceptedTime / 0.25)}>
      {[0, 1].map((index) => {
        const phase = ((acceptedTime + index * 1.1) % 2.2) / 2.2;
        return <circle key={index} r={34 + phase * 32} fill="none" stroke="#37e1b3" strokeWidth="3" opacity={(1 - phase) * 0.5}/>;
      })}
      <circle r="34" fill="#133c39" stroke="#37e1b3" strokeWidth="3"/>
      <path d="M-15 0 L-4 12 L18 -13" pathLength="1" stroke="#a7ffdf" strokeWidth="6" fill="none" strokeLinecap="round" strokeLinejoin="round" strokeDasharray="1" strokeDashoffset={1 - checkProgress}/>
    </g>}
  </svg>;
};
