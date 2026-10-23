import {AbsoluteFill,staticFile,useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';

import {SceneFrame} from '../SceneFrame';
import {BasicCaptions} from '../basic-captions';
export const Acknowledged=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>
<SceneFrame chapter={"CÙNG CHĂM SÓC"}
      title={"Người thân có thể\ntiếp nhận sự cố"}
      subtitle={""}
      accent={"#ffb454"}
      shot={{"file":"10_anh_hien_truong_va_nut_tiep_nhan.png","width":448,"height":970,"focus":{"top":0.76,"height":0.22,"width":800},"masks":[{"left":53,"top":80.5,"width":40,"height":3}]}}
      secondShot={{"file":"12_xac_nhan_da_tiep_nhan.png","width":448,"height":966,"focus":{"top":0.06,"height":0.5,"width":800},"masks":[{"left":53,"top":48,"width":40,"height":5.5}]}}
      switchAt={1.78575}/>


<Audio name="Âm thanh tap" src={staticFile('audio/tap.wav')} from={Math.round(0.9333333333333335*fps)} volume={0.28} premountFor={fps}/>
<Audio name="Âm thanh accepted" src={staticFile('audio/accepted.wav')} from={Math.round(2.06575*fps)} volume={0.28} premountFor={fps}/>
<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={[
  {
    "text": "Người thân có thể tiếp nhận sự cố.",
    "startMs": 15,
    "endMs": 1786,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  },
  {
    "text": "Gia đình cùng phối hợp hỗ trợ.",
    "startMs": 1786,
    "endMs": 3313.3333333333335,
    "timestampMs": null,
    "confidence": null,
    "pageBreakAfter": true
  }
]}/>
</AbsoluteFill>};
