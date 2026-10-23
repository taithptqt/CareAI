import {AbsoluteFill,staticFile,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';

import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const FallAlert=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"CẢNH BÁO"}
      title={"Tình huống khác:\nđồng hồ báo té ngã."}
      subtitle={""}
      accent={"#ff6969"}
      shot={{"file":"07_canh_bao_te_nga.png","width":444,"height":933,"focus":{"top":0,"height":0.57,"width":780}}}/>


<Audio name="Âm thanh notification" src={staticFile('audio/notification.wav')} from={Math.round(0.35*fps)} volume={0.28} premountFor={fps}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Trong tình huống khác, khi đồng hồ",
    "startMs": 15,
    "endMs": 1519,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "báo té ngã, người thân mở thông",
    "startMs": 1519,
    "endMs": 3098,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "tin sự cố để kiểm tra.",
    "startMs": 3098,
    "endMs": 4280,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
