import {AbsoluteFill,staticFile,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';

import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Confirmation=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"XÁC NHẬN"}
      title={"Chạm nhầm?\nCó thể hủy."}
      subtitle={""}
      accent={"#ff6969"}
      shot={{"file":"06_xac_nhan_sos.png","width":444,"height":943,"focus":{"top":0.26,"height":0.55,"width":780}}}/>


<Audio name="Âm thanh tap" src={staticFile('audio/tap.wav')} from={Math.round(1.508*fps)} volume={0.28} premountFor={fps}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Có thể hủy nếu chạm nhầm, hoặc",
    "startMs": 15,
    "endMs": 1530,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "chọn gửi ngay tín hiệu cần giúp.",
    "startMs": 1530,
    "endMs": 2880,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
