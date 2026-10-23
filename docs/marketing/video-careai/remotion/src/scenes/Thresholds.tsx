import {AbsoluteFill, useVideoConfig} from 'remotion';
import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Thresholds=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"CÁ NHÂN HÓA"}
      title={"Theo dõi theo\nnhịp sinh hoạt."}
      subtitle={"Ngưỡng nhịp tim theo ngày và đêm."}
      shot={{"file":"04_nguong_nhip_tim_va_ghep_noi.png","width":448,"height":966,"crop":{"top":0.27,"height":0.47}}}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Các ngưỡng nhịp tim theo ngày và",
    "startMs": 400,
    "endMs": 2733,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "đêm hỗ trợ gia đình theo dõi",
    "startMs": 2733,
    "endMs": 5067,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "những thay đổi cần chú ý.",
    "startMs": 5067,
    "endMs": 7400,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
