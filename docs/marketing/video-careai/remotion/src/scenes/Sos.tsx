import {AbsoluteFill,staticFile,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';

import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Sos=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"CHỦ ĐỘNG"}
      title={"Chủ động\nbáo cần giúp."}
      subtitle={""}
      accent={"#ff6969"}
      shot={{"file":"05_nut_sos.png","width":450,"height":880,"focus":{"top":0.3,"height":0.6,"width":780}}}/>


<Audio name="Âm thanh tap" src={staticFile('audio/tap.wav')} from={Math.round(1.498*fps)} volume={0.28} premountFor={fps}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Khi cần giúp, người cao tuổi có",
    "startMs": 15,
    "endMs": 1403,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "thể gửi SOS từ đồng hồ hoặc",
    "startMs": 1403,
    "endMs": 3023,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "điện thoại.",
    "startMs": 3023,
    "endMs": 3546.666666666667,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
