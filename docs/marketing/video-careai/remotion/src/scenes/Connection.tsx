import {AbsoluteFill,useVideoConfig} from 'remotion';

import {DeviceConnection} from '../DeviceConnection';
import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Connection=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"KẾT NỐI"}
      title={"Kết nối đồng hồ\nvới người thân"}
      subtitle={""}/>
<DeviceConnection/>


<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Hệ thống kết nối đồng hồ\ncủa người cao tuổi",
    "startMs": 15,
    "endMs": 1773,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "với ứng dụng trên\nđiện thoại người thân.",
    "startMs": 1773,
    "endMs": 3246.6666666666665,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
