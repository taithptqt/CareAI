import {Composition,Folder} from 'remotion';
import {CareAIVideo} from './Composition';
import {Opening} from './scenes/Opening';
import {Connection} from './scenes/Connection';
import {Monitoring} from './scenes/Monitoring';
import {Sos} from './scenes/Sos';
import {Confirmation} from './scenes/Confirmation';
import {FallAlert} from './scenes/FallAlert';
import {Incident} from './scenes/Incident';
import {Acknowledged} from './scenes/Acknowledged';
import {Closing} from './scenes/Closing';
export const RemotionRoot=()=> <>
<Composition id="CareAI-Introduction" component={CareAIVideo} width={1080} height={1920} fps={30} durationInFrames={1289}/>
<Folder name="Scenes">
<Composition id="Opening" component={Opening} width={1080} height={1920} fps={30} durationInFrames={179}/>
<Composition id="Connection" component={Connection} width={1080} height={1920} fps={30} durationInFrames={98}/>
<Composition id="Monitoring" component={Monitoring} width={1080} height={1920} fps={30} durationInFrames={296}/>
<Composition id="Sos" component={Sos} width={1080} height={1920} fps={30} durationInFrames={107}/>
<Composition id="Confirmation" component={Confirmation} width={1080} height={1920} fps={30} durationInFrames={87}/>
<Composition id="FallAlert" component={FallAlert} width={1080} height={1920} fps={30} durationInFrames={129}/>
<Composition id="Incident" component={Incident} width={1080} height={1920} fps={30} durationInFrames={121}/>
<Composition id="Acknowledged" component={Acknowledged} width={1080} height={1920} fps={30} durationInFrames={100}/>
<Composition id="Closing" component={Closing} width={1080} height={1920} fps={30} durationInFrames={68}/>
</Folder></>;
