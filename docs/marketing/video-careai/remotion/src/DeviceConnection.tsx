import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';

const clamp = (value: number) => Math.max(0, Math.min(1, value));
const arrive = (time: number, delay: number) => 1 - Math.pow(1 - clamp((time - delay) / 0.48), 3);

/** An explanatory connection diagram, rather than a simulated device screen. */
export const DeviceConnection: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const time = Math.max(0, frame / fps);
  const lineProgress = arrive(time, 0.45);
  const hubPulse = 0.5 + 0.5 * Math.sin(time * 3.6);
  return <div style={{position: 'absolute', left: 80, top: 560, width: 920, height: 900, pointerEvents: 'none', fontFamily: '"Segoe UI", Arial, sans-serif'}}>
    <svg width="920" height="900" viewBox="0 0 920 900" aria-label="Sơ đồ đồng hồ người cao tuổi kết nối qua hệ thống CareAI tới ứng dụng trên điện thoại người thân" role="img">
      <defs>
        <linearGradient id="device-link-watch" x1="0" x2="1" y1="0" y2="0">
          <stop offset="0%" stopColor="#38bdf8"/><stop offset="100%" stopColor="#28dac4"/>
        </linearGradient>
        <radialGradient id="device-link-hub">
          <stop offset="0%" stopColor="#28dac4" stopOpacity="0.18"/><stop offset="100%" stopColor="#28dac4" stopOpacity="0"/>
        </radialGradient>
      </defs>

      <g opacity={arrive(time, 0)}>
        <rect x="291" y="15" width="338" height="51" rx="25" fill="#12313b" stroke="#28dac4" strokeOpacity="0.5"/>
        <text x="460" y="49" fill="#94eee4" textAnchor="middle" fontSize="26" fontWeight="700" letterSpacing="3">SƠ ĐỒ KẾT NỐI</text>
      </g>

      <circle cx="460" cy="314" r={140 + hubPulse * 12} fill="url(#device-link-hub)"/>

      <g opacity={lineProgress}>
        <path d="M233 314 H344 M576 314 H686" stroke="#244a5b" strokeWidth="5" fill="none" strokeLinecap="round"/>
        <path d="M233 314 H344 M576 314 H686" stroke="url(#device-link-watch)" strokeWidth="3" fill="none" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - lineProgress}/>
        <path d="M331 304 L344 314 L331 324 M673 304 L686 314 L673 324" fill="none" stroke="#6af0d7" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
        {[0, 1].map((index) => {
          const phase = ((time * 0.65 + index * 0.5) % 1);
          return <g key={index}>
            <circle cx={237 + phase * 100} cy="314" r="6" fill="#a6fff0" opacity={Math.sin(phase * Math.PI)}/>
            <circle cx={580 + phase * 99} cy="314" r="6" fill="#a6fff0" opacity={Math.sin(phase * Math.PI)}/>
          </g>;
        })}
      </g>

      <g opacity={arrive(time, 0.08)} transform={`translate(140,314) translate(0,${(1 - arrive(time, 0.08)) * 35})`}>
        <rect x="-45" y="-186" width="90" height="372" rx="28" fill="#173447" stroke="#33596e" strokeWidth="3"/>
        <rect x="-91" y="-110" width="182" height="220" rx="47" fill="#0b1c2b" stroke="#5ab6cb" strokeWidth="5"/>
        <rect x="91" y="-36" width="10" height="37" rx="5" fill="#3a7186"/>
        <rect x="-77" y="-95" width="154" height="190" rx="35" fill="#102d3a"/>
        <path d="M-31 -45 C-31 -63 -8 -69 0 -51 C8 -69 31 -63 31 -45 C31 -23 0 -5 0 -5 C0 -5 -31 -23 -31 -45 Z" fill="#28dac4" fillOpacity="0.18" stroke="#48ead2" strokeWidth="3"/>
        <path d="M-55 31 H-31 L-20 16 L-5 49 L12 2 L27 31 H55" fill="none" stroke="#65f6dc" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - arrive(time, 0.25)}/>
      </g>

      <g opacity={arrive(time, 0.25)} transform={`translate(460,314) scale(${0.92 + arrive(time, 0.25) * 0.08})`}>
        <circle r={109 + hubPulse * 5} fill="none" stroke="#28dac4" strokeWidth="1.5" strokeOpacity="0.24"/>
        <circle r="94" fill="#102f3b" stroke="#3ce2ca" strokeWidth="3"/>
        <path d="M-35 -30 C-35 -53 -10 -59 0 -37 C10 -59 35 -53 35 -30 C35 -5 0 18 0 18 C0 18 -35 -5 -35 -30 Z" fill="#28dac4" fillOpacity="0.12" stroke="#62f5dc" strokeWidth="3"/>
        <path d="M-47 -16 H-23 L-13 -31 L0 0 L13 -41 L26 -16 H47" fill="none" stroke="#78ffdf" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round"/>
        <text x="0" y="58" textAnchor="middle" fill="#f0fffb" fontSize="35" fontWeight="750">CareAI</text>
      </g>

      <g opacity={arrive(time, 0.4)} transform={`translate(780,314) translate(0,${(1 - arrive(time, 0.4)) * 35})`}>
        <rect x="-85" y="-174" width="170" height="348" rx="30" fill="#0b1c2b" stroke="#5ab6cb" strokeWidth="5"/>
        <rect x="-71" y="-156" width="142" height="312" rx="19" fill="#102d3a"/>
        <rect x="-26" y="-147" width="52" height="7" rx="3.5" fill="#42677a"/>
        <circle cy="-31" r="48" fill="#1b4250" stroke="#28dac4" strokeWidth="1.5"/>
        <path d="M-20 -12 H20 L14 -21 V-37 A14 14 0 0 0 -14 -37 V-21 Z M-6 -4 A6 6 0 0 0 6 -4" fill="none" stroke="#67f3dc" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round"/>
        <circle cx="37" cy="-64" r="10" fill="#ffb454"/>
        <path d="M-29 75 L-8 96 L34 48" fill="none" stroke="#67f3dc" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - arrive(time, 0.75)}/>
        <rect x="-25" y="139" width="50" height="5" rx="2.5" fill="#42677a"/>
      </g>

      <g fill="#effbff" textAnchor="middle" fontSize="42" fontWeight="650">
        <text x="140" y="565" opacity={arrive(time, 0.12)}><tspan x="140">Đồng hồ của</tspan><tspan x="140" dy="52">người cao tuổi</tspan></text>
        <text x="460" y="565" opacity={arrive(time, 0.28)}><tspan x="460">Qua hệ thống</tspan><tspan x="460" dy="52" fill="#67f3dc">CareAI</tspan></text>
        <text x="780" y="565" opacity={arrive(time, 0.43)}><tspan x="780">Ứng dụng trên</tspan><tspan x="780" dy="52">điện thoại</tspan><tspan x="780" dy="52">người thân</tspan></text>
      </g>

      <g opacity={arrive(time, 0.85)} transform={`translate(0,${(1 - arrive(time, 0.85)) * 18})`}>
        <rect x="64" y="739" width="792" height="77" rx="22" fill="#102d3a" stroke="#28dac4" strokeOpacity="0.38"/>
        <text x="460" y="788" textAnchor="middle" fill="#bff9ee" fontSize="34" fontWeight="600">Theo dõi sức khỏe • Nhận cảnh báo</text>
      </g>
    </svg>
  </div>;
};
