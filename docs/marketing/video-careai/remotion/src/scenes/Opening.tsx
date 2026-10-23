import {AbsoluteFill,useVideoConfig} from 'remotion';


import {OpeningStory} from '../OpeningStory';
import {BasicCaptions} from '../basic-captions';
export const Opening=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<OpeningStory connectionAt={2.01975}/>



<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Khi bạn đi làm xa",
    "startMs": 60,
    "endMs": 992,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "và không thể ở\ngần cha mẹ,",
    "startMs": 992,
    "endMs": 2020,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "CareAI giúp bạn\nvơi bớt nỗi lo",
    "startMs": 2020,
    "endMs": 3355,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "bằng cách theo dõi sức khỏe",
    "startMs": 3355,
    "endMs": 4414,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "và giữ kết nối với\nngười thân mỗi ngày.",
    "startMs": 4414,
    "endMs": 5946.666666666667,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
