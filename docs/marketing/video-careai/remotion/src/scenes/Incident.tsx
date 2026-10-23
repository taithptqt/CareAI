import {AbsoluteFill,staticFile,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';

import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Incident=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"PHẢN HỒI"}
      title={"Xem thông tin.\nLiên hệ người nhà."}
      subtitle={""}
      accent={"#38bdf8"}
      shot={{"file":"09_chi_tiet_su_co_va_gps.png","width":448,"height":940,"focus":{"top":0.68,"height":0.3,"width":800}}}
      secondShot={{"file":"10_anh_hien_truong_va_nut_tiep_nhan.png","width":448,"height":970,"focus":{"top":0.13,"height":0.77,"width":620},"masks":[{"left":53,"top":80.5,"width":40,"height":3}]}}
      switchAt={1.936}/>


<Audio name="Âm thanh tap" src={staticFile('audio/tap.wav')} from={Math.round(1.3713333333333333*fps)} volume={0.28} premountFor={fps}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Xem vị trí và ảnh khi có",
    "startMs": 15,
    "endMs": 1265,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "dữ liệu, mở chỉ đường hoặc gọi",
    "startMs": 1265,
    "endMs": 2737,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "liên hệ để tìm hiểu tình hình.",
    "startMs": 2737,
    "endMs": 4013.333333333333,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
