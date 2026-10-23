import fs from 'node:fs';
const scenes=[
 {id:'Opening',name:'01 · Khi không ở cạnh',duration:8,title:'Khi không\nở cạnh cha mẹ…',subtitle:'Sự quan tâm vẫn luôn ở đó.',chapter:'LỜI MỞ',image:5,text:'Có những lúc bạn không thể ở cạnh cha mẹ. Nhưng sự quan tâm vẫn luôn ở đó.'},
 {id:'Connection',name:'02 · Hai vai trò',duration:9,title:'Một ứng dụng.\nKết nối gia đình.',subtitle:'Người cao tuổi và người thân.',chapter:'KẾT NỐI',image:1,text:'CareAI giúp kết nối người cao tuổi với gia đình, qua hai chế độ sử dụng trong cùng một ứng dụng.'},
 {id:'Monitoring',name:'03 · Theo dõi sức khỏe',duration:10,title:'Quan tâm từ\nnhững thông tin nhỏ.',subtitle:'Xem dữ liệu và thời điểm cập nhật.',chapter:'THEO DÕI',image:2,second:3,switchAt:3,text:'Người thân có thể xem hồ sơ và thông tin sức khỏe được thiết bị cung cấp, đồng thời chú ý thời điểm cập nhật và tình trạng kết nối.'},
 {id:'Thresholds',name:'04 · Ngưỡng ngày và đêm',duration:8,title:'Theo dõi theo\nnhịp sinh hoạt.',subtitle:'Ngưỡng nhịp tim theo ngày và đêm.',chapter:'CÁ NHÂN HÓA',image:4,crop:{top:0.27,height:0.47},text:'Các ngưỡng nhịp tim theo ngày và đêm hỗ trợ gia đình theo dõi những thay đổi cần chú ý.'},
 {id:'Sos',name:'05 · Nút SOS',duration:10,title:'Cần giúp?\nBấm SOS.',subtitle:'Nút lớn. Dễ nhận biết.',chapter:'CHỦ ĐỘNG',image:5,accent:'#ff6969',text:'Khi cần giúp, người cao tuổi có thể bấm nút SOS lớn, dễ nhận biết ngay trên màn hình.'},
 {id:'Confirmation',name:'06 · Xác nhận SOS',duration:9,title:'Xác nhận trước\nkhi gửi tín hiệu.',subtitle:'Hủy chạm nhầm hoặc chọn gửi ngay.',chapter:'XÁC NHẬN',image:6,accent:'#ff6969',text:'Bước xác nhận cho phép hủy khi chạm nhầm, hoặc chọn gửi ngay tín hiệu cần giúp đến người thân.'},
 {id:'FallAlert',name:'07 · Tình huống khác: té ngã',duration:11,title:'Một tình huống khác:\ncảnh báo té ngã.',subtitle:'Người thân xem và kiểm tra sự cố.',chapter:'CẢNH BÁO',image:7,second:8,switchAt:8,accent:'#ff6969',text:'Với tình huống cảnh báo té ngã, người thân có thể xem người cần hỗ trợ và mở thông tin sự cố để kiểm tra.'},
 {id:'Incident',name:'08 · Xem và liên hệ',duration:12,title:'Hiểu tình huống.\nChọn bước tiếp theo.',subtitle:'Thông tin hỗ trợ khi có dữ liệu.',chapter:'PHẢN HỒI',image:9,second:10,switchAt:6,accent:'#38bdf8',text:'Tại đây, gia đình có thể xem vị trí và ảnh khi có dữ liệu, mở chỉ đường hoặc gọi liên hệ để tìm hiểu tình hình.'},
 {id:'Acknowledged',name:'09 · Gia đình tiếp nhận',duration:13,title:'Đã có người\nnhận xử lý.',subtitle:'Ghi nhận trạng thái và thời điểm.',chapter:'CÙNG CHĂM SÓC',image:10,second:12,switchAt:4,accent:'#ffb454',text:'Khi một người thân tiếp nhận, hệ thống ghi lại trạng thái và thời điểm, giúp gia đình phối hợp rõ ràng hơn khi có việc cần xử lý.'},
 {id:'Closing',name:'10 · CareAI',duration:10,title:'Gần nhau hơn\nqua sự quan tâm.',subtitle:'Dành cho người cao tuổi và gia đình.',chapter:'CAREAI',ending:true,text:'CareAI. Kết nối quan tâm, cùng gia đình chăm sóc. Hỗ trợ theo dõi và cảnh báo, không thay thế chăm sóc y tế.'}
];
const files=fs.readdirSync('public/screens').sort();
function shot(index,crop){if(!index)return undefined;const file=files[index-1];const b=fs.readFileSync('public/screens/'+file);const s={file,width:b.readUInt32BE(16),height:b.readUInt32BE(20)};if(crop)s.crop=crop;
 if(index===10)s.masks=[{left:53,top:80.5,width:40,height:3}];
 if(index===12)s.masks=[{left:53,top:48,width:40,height:5.5}];
 return s;}
fs.mkdirSync('src/scenes',{recursive:true});
let offset=0;const json=[];let srt='';let cue=0;
const stamp=ms=>{const h=Math.floor(ms/3600000),m=Math.floor(ms/60000)%60,s=Math.floor(ms/1000)%60;return [h,m,s].map(v=>String(v).padStart(2,'0')).join(':')+','+String(Math.round(ms%1000)).padStart(3,'0')};
for(const s of scenes){const words=s.text.split(' ');const chunks=[];for(let i=0;i<words.length;i+=7)chunks.push(words.slice(i,i+7).join(' '));const span=(s.duration*1000-1000)/chunks.length;const captions=chunks.map((text,i)=>({text,startMs:Math.round(400+i*span),endMs:Math.round(400+(i+1)*span),timestampMs:null,confidence:null,pageBreakAfter:true}));
 for(const c of captions){json.push({...c,startMs:c.startMs+offset*1000,endMs:c.endMs+offset*1000});srt+=`${++cue}\n${stamp(c.startMs+offset*1000)} --> ${stamp(c.endMs+offset*1000)}\n${c.text}\n\n`;}
 const props={chapter:s.chapter,title:s.title,subtitle:s.subtitle,accent:s.accent,shot:shot(s.image,s.crop),secondShot:shot(s.second),switchAt:s.switchAt,ending:s.ending};
 const attrs=Object.entries(props).filter(([,v])=>v!==undefined).map(([k,v])=>`${k}={${JSON.stringify(v)}}`).join('\n      ');
 const code=`import {AbsoluteFill, useVideoConfig} from 'remotion';\nimport {SceneFrame} from '../SceneFrame';\nimport {BasicCaptions} from '../basic-captions';\nexport const ${s.id}=()=>{const {fps}=useVideoConfig();return <AbsoluteFill>\n<SceneFrame ${attrs}/>\n<BasicCaptions name="Phụ đề" premountFor={fps} width={916} combineTokensWithinMilliseconds={0} style={{position:'absolute',left:82,top:1630}} captions={${JSON.stringify(captions,null,2)}}/>\n</AbsoluteFill>};\n`;
 fs.writeFileSync(`src/scenes/${s.id}.tsx`,code);offset+=s.duration;}
const imports=scenes.map(s=>`import {${s.id}} from './scenes/${s.id}';`).join('\n');
fs.writeFileSync('src/Composition.tsx',`import {Series,useVideoConfig} from 'remotion';\n${imports}\nexport const CareAIVideo=()=>{const {fps}=useVideoConfig();return <Series>\n${scenes.map(s=>`<Series.Sequence name=${JSON.stringify(s.name)} durationInFrames={${s.duration}*fps} premountFor={fps}><${s.id}/></Series.Sequence>`).join('\n')}\n</Series>};\n`);
fs.writeFileSync('src/Root.tsx',`import {Composition,Folder} from 'remotion';\nimport {CareAIVideo} from './Composition';\n${imports}\nexport const RemotionRoot=()=> <>\n<Composition id="CareAI-Introduction" component={CareAIVideo} width={1080} height={1920} fps={30} durationInFrames={3000}/>\n<Folder name="Scenes">\n${scenes.map(s=>`<Composition id="${s.id}" component={${s.id}} width={1080} height={1920} fps={30} durationInFrames={${s.duration*30}}/>`).join('\n')}\n</Folder></>;\n`);
fs.writeFileSync('public/captions.vi.json',JSON.stringify(json,null,2));
fs.writeFileSync('public/captions.vi.srt',srt);
console.log(`Authored ${scenes.length} scenes, ${offset}s, ${json.length} caption pages.`);
