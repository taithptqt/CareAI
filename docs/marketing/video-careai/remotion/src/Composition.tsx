import {AbsoluteFill,Sequence,interpolate,staticFile,useCurrentFrame,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';
import {TransitionSeries} from '@remotion/transitions';
import {ChapterWipe} from './ChapterWipe';
import {Opening} from './scenes/Opening';
import {Connection} from './scenes/Connection';
import {Monitoring} from './scenes/Monitoring';
import {Sos} from './scenes/Sos';
import {Confirmation} from './scenes/Confirmation';
import {FallAlert} from './scenes/FallAlert';
import {Incident} from './scenes/Incident';
import {Acknowledged} from './scenes/Acknowledged';
import {Closing} from './scenes/Closing';
const ContinuousSource=()=>{const {fps,durationInFrames}=useVideoConfig();const frame=useCurrentFrame();return <AbsoluteFill>
<Audio name="Lời dẫn nam tiếng Việt liền mạch" src={staticFile("audio/north-v9/narration-continuous.wav")} volume={0.9} premountFor={fps}/>
<Audio name="Nhạc nền · Gắn kết gia đình" src={staticFile('audio/music-family-connection.wav')} volume={interpolate(frame,[0,0.5*fps,durationInFrames-1.5*fps,durationInFrames],[0,0.16,0.16,0],{extrapolateLeft:'clamp',extrapolateRight:'clamp'})} premountFor={fps}/>
<TransitionSeries>
<TransitionSeries.Sequence name="01 · Đi làm xa vẫn gần cha mẹ" durationInFrames={179} premountFor={fps}><Opening/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#28dac4"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="02 · Đồng hồ đến điện thoại" durationInFrames={98} premountFor={fps}><Connection/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#28dac4"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="03 · Theo dõi sức khỏe mỗi ngày" durationInFrames={296} premountFor={fps}><Monitoring/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#ff6969"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="04 · Chủ động báo cần giúp" durationInFrames={107} premountFor={fps}><Sos/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#ff6969"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="05 · Xác nhận tín hiệu" durationInFrames={87} premountFor={fps}><Confirmation/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#ff6969"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="06 · Cảnh báo ngã từ đồng hồ" durationInFrames={129} premountFor={fps}><FallAlert/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#38bdf8"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="07 · Xem và liên hệ" durationInFrames={121} premountFor={fps}><Incident/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#ffb454"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="08 · Gia đình cùng phản hồi" durationInFrames={100} premountFor={fps}><Acknowledged/></TransitionSeries.Sequence>
<TransitionSeries.Overlay durationInFrames={0.3*fps} premountFor={fps}><ChapterWipe accent="#28dac4"/></TransitionSeries.Overlay>
<TransitionSeries.Sequence name="09 · Một kết nối triệu yêu thương" durationInFrames={68} premountFor={fps}><Closing/></TransitionSeries.Sequence>
</TransitionSeries></AbsoluteFill>};
export const CareAIVideo=()=>{const {fps}=useVideoConfig();return <Sequence name="Nhịp chậm nhẹ · 92%" durationInFrames={1185} playbackRate={0.92} premountFor={fps}><ContinuousSource/></Sequence>;};
