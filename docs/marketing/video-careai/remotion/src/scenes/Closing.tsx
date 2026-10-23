import {AbsoluteFill,useVideoConfig} from 'remotion';


import {ClosingBrand} from '../ClosingBrand';
import {BasicCaptions} from '../basic-captions';
export const Closing=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<ClosingBrand durationInFrames={68}/>



<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "CareAI – Một kết nối,\ntriệu yêu thương",
    "startMs": 15,
    "endMs": 1864,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
