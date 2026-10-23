import {AbsoluteFill,useVideoConfig} from 'remotion';


import {HealthFeatureHighlights} from '../HealthFeatureHighlights';
import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Monitoring=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"THEO DÕI"}
      title={"Theo dõi sức khỏe.\nChủ động quan tâm."}
      subtitle={""}
      shot={{"file":"03_dashboard_suc_khoe.png","width":444,"height":897,"focus":{"top":0.34,"height":0.315,"width":800}}}/>

<HealthFeatureHighlights metricsAt={0.5} chartsAt={3.428208} insightsAt={5.580832999999999}/>


<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Ứng dụng giúp gia đình\ntheo dõi nhịp tim",
    "startMs": 15,
    "endMs": 1593,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "và độ bão hòa\noxy trong máu,",
    "startMs": 1593,
    "endMs": 3259,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "qua biểu đồ sức khỏe",
    "startMs": 3259,
    "endMs": 4117,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "cùng cảnh báo vượt ngưỡng,",
    "startMs": 4117,
    "endMs": 5433,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "và nhận định xu hướng\nkèm báo cáo tuần,",
    "startMs": 5433,
    "endMs": 7469,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "để nắm bắt thay đổi",
    "startMs": 7469,
    "endMs": 8284,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "và chủ động chăm sóc\nngười thân mỗi ngày.",
    "startMs": 8284,
    "endMs": 9846.666666666668,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
