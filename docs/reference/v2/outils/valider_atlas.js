/**
 * Vérification numérique et smoke test du JavaScript de l'atlas sous Node VM.
 * Aucun navigateur, DOM réel, canvas rasterisé, installation ou réseau.
 * Usage : node outils/valider_atlas.js
 * Python standard est appelé comme oracle via oracle_atlas.py.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const cp = require('node:child_process');

const BASE = path.resolve(__dirname, '..');
const REPORT = path.join(BASE, 'rapports', 'atlas.validation.json');
const FILES = {
  shell: path.join(BASE, 'outils', 'atlas_shell.html'),
  html: path.join(BASE, 'ATLAS_EXERCICES_V2.html'),
  data: path.join(BASE, 'donnees', 'atlas.etats.json'),
  motion: path.join(BASE, 'outils', 'mouvements_reference.py'),
  geometry: path.join(BASE, 'outils', 'geometrie_reference.py'),
  builder: path.join(BASE, 'outils', 'construire_visuels.py'),
  oracle: path.join(BASE, 'outils', 'oracle_atlas.py'),
};
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sourceHashes = Object.fromEntries(Object.entries(FILES).map(([key,file])=>[key,hash(file)]));
const source = {shell:fs.readFileSync(FILES.shell,'utf8'),html:fs.readFileSync(FILES.html,'utf8')};
const DATA = JSON.parse(fs.readFileSync(FILES.data,'utf8'));
const TOL = {angle_deg:1e-8,distance_m:1e-10,radius_m:1e-10,fraction:1e-10,contour_px:1e-6,time_s:1e-9};

class Audit {
  constructor(){this.checks=0;this.failureCount=0;this.failureCodes={};this.failures=[];this.groups=[];}
  check(condition,code,context,observed,expected){
    this.checks++;
    if(!condition){
      this.failureCount++;this.failureCodes[code]=(this.failureCodes[code]||0)+1;
      if(this.failures.length<100)this.failures.push({code,...(context===undefined?{}:{context}),...(observed===undefined?{}:{observed}),...(expected===undefined?{}:{expected})});
    }
    return Boolean(condition);
  }
  async run(id,fn){
    const start=performance.now(),checks=this.checks,failures=this.failureCount;let metrics={};
    try{metrics=await fn()||{};}catch(error){this.check(false,'UNEXPECTED_EXCEPTION',id,String(error));metrics={stack:String(error.stack||error)};}
    this.groups.push({id,status:this.failureCount===failures?'pass':'fail',checks:this.checks-checks,failures:this.failureCount-failures,elapsed_s:(performance.now()-start)/1000,metrics});
  }
}
const audit = new Audit();

function scripts(html){
  const found=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  const data=found.find(match=>/\bid\s*=\s*["']atlas-data["']/i.test(match[1]));
  const executable=found.filter(match=>!/\btype\s*=\s*["']application\/json["']/i.test(match[1]));
  return {dataText:data?data[2]:null,code:executable.map(match=>match[2]).join('\n'),count:executable.length};
}

class MockElement {
  constructor(tagName,id=''){
    this.tagName=tagName.toUpperCase();this.id=id;this._html='';this._value='';this.textContent='';this.children=[];this.options=[];this.dataset={};this.onclick=null;this.onchange=null;this.oninput=null;
    const classes=new Set();
    this.classList={toggle:(name,force)=>{const enabled=force===undefined?!classes.has(name):Boolean(force);if(enabled)classes.add(name);else classes.delete(name);return enabled;},contains:name=>classes.has(name)};
  }
  set innerHTML(value){
    this._html=String(value);this.children=[];
    if(this.tagName==='SELECT'){
      this.options=[...this._html.matchAll(/<option\b([^>]*)>([\s\S]*?)<\/option>/gi)].map(match=>{
        const option=new MockElement('option');option._value=(match[1].match(/\bvalue\s*=\s*["']([^"']*)["']/i)||[])[1]||'';option.textContent=match[2];option.selected=/(?:^|\s)selected(?:\s|=|$)/i.test(match[1]);return option;
      });
      this.children=this.options;this._value=(this.options.find(option=>option.selected)||this.options[0]||{_value:''})._value;
    }else if(this.id==='phaseStrip'){
      this.children=[...this._html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/gi)].map(match=>{
        const button=new MockElement('button');button.dataset.idx=(match[1].match(/\bdata-idx\s*=\s*["']([^"']*)["']/i)||[])[1];button.textContent=match[2];return button;
      });
    }
  }
  get innerHTML(){return this._html;}
  set value(value){const text=String(value);this._value=this.tagName==='SELECT'&&!this.options.some(option=>option.value===text)?'':text;}
  get value(){return this._value;}
  dispatch(type){const callback=this['on'+type];if(typeof callback!=='function')throw Error('MISSING_CONTROL_HANDLER:'+this.id+':'+type);return callback.call(this,{type,target:this,currentTarget:this});}
}

async function createHarness(label,html,dataText,code){
  const elements=new Map(),listeners=new Map(),stats={canvas_calls:0,finite_coordinate_arguments:0,draw_rectangles:0,text_calls:0,animation_frames:0,network_calls:0,controls:0};
  for(const match of html.matchAll(/<([a-zA-Z][\w:-]*)\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>/g))elements.set(match[2],new MockElement(match[1],match[2]));
  for(const match of html.matchAll(/<select\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/select>/gi))elements.get(match[1]).innerHTML=match[2];
  elements.get('atlas-data').textContent=dataText;
  const drawing={fillStyle:'',strokeStyle:'',lineWidth:1,font:'',textAlign:'left'};
  function numeric(name,args){stats.canvas_calls++;for(const value of args){if(typeof value!=='number'||!Number.isFinite(value))throw Error('NONFINITE_CANVAS_ARGUMENT:'+name+':'+String(value));stats.finite_coordinate_arguments++;}}
  for(const name of ['beginPath','closePath','fill','stroke'])drawing[name]=()=>{stats.canvas_calls++;};
  for(const name of ['moveTo','lineTo','arc'])drawing[name]=(...args)=>numeric(name,args);
  drawing.fillRect=(...args)=>{numeric('fillRect',args);stats.draw_rectangles++;};
  drawing.fillText=(text,...args)=>{if(typeof text!=='string'&&typeof text!=='number')throw Error('INVALID_CANVAS_TEXT:'+String(text));numeric('fillText',args);stats.text_calls++;};
  elements.get('scene').width=1920;elements.get('scene').height=1080;
  elements.get('scene').getContext=kind=>{if(kind!=='2d')throw Error('UNSUPPORTED_CANVAS_CONTEXT:'+kind);return drawing;};
  let clock=1000,nextFrameId=1;const frames=new Map();
  const document={getElementById:id=>elements.get(id)||null,hidden:false,fonts:{ready:Promise.resolve()},addEventListener:(name,callback)=>{if(!listeners.has(name))listeners.set(name,[]);listeners.get(name).push(callback);}};
  const blockedNetwork=()=>{stats.network_calls++;throw Error('NETWORK_NOT_PERMITTED_IN_OFFLINE_ATLAS_TEST');};
  const window={};
  const sandbox={document,window,console,performance:{now:()=>clock},requestAnimationFrame:callback=>{const id=nextFrameId++;frames.set(id,callback);return id;},cancelAnimationFrame:id=>frames.delete(id),fetch:blockedNetwork,XMLHttpRequest:blockedNetwork,WebSocket:blockedNetwork};
  vm.createContext(sandbox,{name:'AIM_LOCAL_ATLAS_'+label});
  vm.runInContext('Math.random=()=>{throw new Error("LIVE_RNG_NOT_PERMITTED_IN_ATLAS")};',sandbox);
  vm.runInContext(code,sandbox,{filename:label+'.embedded.js',timeout:10000});
  await Promise.resolve();await Promise.resolve();
  const api=window.atlasReference;
  if(!api)throw Error('MISSING_EXISTING_ATLAS_REFERENCE_INTERFACE');
  // Accès transitoire au contexte lexical de la VM, sans modifier aucun HTML.
  const testing=vm.runInContext('({setLogicalTime:t=>{seconds=t;},phaseAt,contour,isPlaying:()=>playing})',sandbox);
  function dispatch(id,type){stats.controls++;return elements.get(id).dispatch(type);}
  function advance(milliseconds){clock+=milliseconds;const pending=[...frames.values()];frames.clear();for(const callback of pending){stats.animation_frames++;callback(clock);}if(frames.size>1)throw Error('ANIMATION_FRAME_QUEUE_MULTIPLIED');}
  function visibility(hidden){document.hidden=hidden;for(const callback of listeners.get('visibilitychange')||[])callback({type:'visibilitychange'});}
  return {label,api,testing,elements,stats,dispatch,advance,visibility,dataSnapshot:JSON.stringify(api.data)};
}

function addTime(set,t,duration){if(Number.isFinite(t)&&t>=0&&t<=duration)set.add(t);}
function motionTimes(state,duration){
  const times=new Set([0,1e-7,duration-1e-7,duration,.123456789,duration*.1732050807568877,duration/2,duration*.8732050807568877]);
  const boundaries=[];
  if(state.tape)for(const piece of state.tape.pieces){boundaries.push(piece.from_s,piece.to_s);addTime(times,(piece.from_s+piece.to_s)/2,duration);}
  if(state.bounces)for(const segment of state.bounces)boundaries.push(segment.start,segment.end);
  if(state.kind==='linear_reflect'){
    const m=state.m,[lo,hi]=m.yaw_bounds_deg;
    if(m.reflection==='instantaneous_velocity_sign_change'){
      const v=state.sign*m.yaw_speed_deg_s,width=hi-lo;
      const count=Math.ceil(Math.abs(v)*duration/width)+3;
      for(let k=-count;k<=count;k++)boundaries.push((k*width-(state.x0-lo))/v);
    }else{
      const s=m.straight_segment_duration_s,T=m.turn_duration_s,period=2*(s+T);
      for(let cycle=-1;cycle<=Math.ceil(duration/period)+1;cycle++)for(const b of [0,s,s+T,2*s+T])boundaries.push(b+cycle*period-state.cycle*period);
    }
  }
  if(state.kind==='angular_ellipse'){
    const velocity=state.sign*state.m.path_angular_speed_deg_s*Math.PI/180;
    for(let cycle=-1;cycle<=3;cycle++)boundaries.push((cycle*state.ellipse.length-state.arc0)/velocity);
  }
  for(const boundary of boundaries)for(const dt of [-1e-7,0,1e-7])addTime(times,boundary+dt,duration);
  return [...times].filter(t=>t>=0&&t<=duration).sort((a,b)=>a-b);
}

function buildQueries(){
  const queries={samples:[],targets:[],contours:[]};
  for(let c=0;c<DATA.configs.length;c++)for(let p=0;p<DATA.configs[c].phases.length;p++){
    const phase=DATA.configs[c].phases[p],definition=phase.definition,duration=definition.duration_s,start=definition.start_s;
    for(let s=0;s<phase.states.length;s++)for(const t of motionTimes(phase.states[s],duration))queries.samples.push({c,p,s,t});
    const times=new Set([0,1e-7,.123456789,duration*.1732050807568877,duration/2,duration*.8732050807568877,duration-1e-7,duration]);
    for(const opportunity of phase.opportunities)for(const t of [opportunity.onset_s-1e-7,opportunity.onset_s,opportunity.onset_s+1e-7,(opportunity.onset_s+opportunity.deadline_s)/2,opportunity.deadline_s-1e-7,opportunity.deadline_s,opportunity.deadline_s+1e-7])addTime(times,t,duration);
    for(const t of [...times].sort((a,b)=>a-b))queries.targets.push({c,p,t,global_t:start+t});
    const t=phase.opportunities.length?(phase.opportunities[0].onset_s+phase.opportunities[0].deadline_s)/2:Math.min(2.3456789,duration/2);
    queries.contours.push({c,p,t,global_t:start+t,target:0});
  }
  return queries;
}

function oracle(queries){
  const python=process.env.AIM_LOCAL_PYTHON||'python';
  const result=cp.spawnSync(python,[FILES.oracle],{cwd:BASE,input:JSON.stringify(queries),encoding:'utf8',maxBuffer:32*1024*1024,timeout:30000});
  if(result.error)throw result.error;
  if(result.status!==0)throw Error('PYTHON_ORACLE_FAILED:'+result.stderr);
  return {python,response:JSON.parse(result.stdout)};
}

function compareVector(actual,expected,tolerances,code,context,maxima){
  if(!audit.check(Array.isArray(actual)&&actual.length===expected.length,code+'_DIMENSION',context,actual&&actual.length,expected.length))return;
  for(let i=0;i<expected.length;i++){
    if(expected[i]===null){audit.check(actual[i]===null,code+'_NULL_COMPONENT',{...context,component:i},actual[i],null);continue;}
    const finite=typeof actual[i]==='number'&&Number.isFinite(actual[i]);audit.check(finite,code+'_NONFINITE',{...context,component:i},actual[i]);
    if(!finite)continue;
    const error=Math.abs(actual[i]-expected[i]);maxima[i]=Math.max(maxima[i]||0,error);
    audit.check(error<=tolerances[i],code+'_ERROR',{...context,component:i},error,tolerances[i]);
  }
}

async function main(){
  const start=performance.now(),shell=scripts(source.shell),html=scripts(source.html),harnesses=[];let expected,queries;
  await audit.run('source_integrity_and_python_oracle',()=>{
    audit.check(shell.count===1&&html.count===1,'EXPECTED_SINGLE_EXECUTABLE_SCRIPT',undefined,[shell.count,html.count]);
    audit.check(shell.code===html.code,'DELIVERED_JAVASCRIPT_DIFFERS_FROM_SHELL');
    audit.check(shell.dataText==='__ATLAS_DATA__','SHELL_DATA_PLACEHOLDER_CHANGED');
    audit.check(JSON.stringify(JSON.parse(html.dataText))===JSON.stringify(DATA),'EMBEDDED_DATA_DIFFERS_FROM_ATLAS_STATES');
    audit.check(!source.html.includes('__ATLAS_DATA__')&&!source.html.includes('__FONT_NORMAL__')&&!source.html.includes('__FONT_BOLD__'),'UNRESOLVED_DELIVERY_PLACEHOLDER');
    queries=buildQueries();const result=oracle(queries);expected=result.response;
    audit.check(expected.compiler_version===DATA.compiler_version,'ORACLE_COMPILER_VERSION_MISMATCH');
    return {configurations:DATA.configs.length,phases:DATA.configs.reduce((n,c)=>n+c.phases.length,0),sample_queries:queries.samples.length,target_queries:queries.targets.length,contour_queries:queries.contours.length,python_command:result.python};
  });
  if(expected)for(const [label,documentSource,dataText,code] of [['shell',source.shell,JSON.stringify(DATA),shell.code],['delivered_html',source.html,html.dataText,html.code]]){
    let harness;
    await audit.run(label+'_load_and_initial_draw',async()=>{
      harness=await createHarness(label,documentSource,dataText,code);harnesses.push(harness);
      audit.check(harness.api.getConfig().program_id==='EX01'&&harness.api.getConfig().difficulty==='standard','INITIAL_SELECTION_NOT_EX01_STANDARD',label);
      audit.check(harness.elements.get('program').options.length===8,'PROGRAM_SELECTOR_NOT_EIGHT_OPTIONS',label);
      audit.check(harness.elements.get('level').options.length===3,'LEVEL_SELECTOR_NOT_THREE_OPTIONS',label);
      audit.check(harness.stats.draw_rectangles>0&&harness.stats.text_calls>0,'INITIAL_DRAW_NOT_EXECUTED',label);
      return {initial_program:harness.api.getConfig().program_id,initial_level:harness.api.getConfig().difficulty};
    });
    if(!harness)continue;
    await audit.run(label+'_numeric_equivalence',()=>{
      const {api,testing}=harness,maxSample=[0,0,0],maxTarget=[0,0,0,0,0],maxContour=[0,0];
      let targetRows=0;
      for(let i=0;i<queries.samples.length;i++){
        const q=queries.samples[i],state=api.data.configs[q.c].phases[q.p].states[q.s];
        compareVector(api.sample(state,q.t),expected.samples[i],[TOL.angle_deg,TOL.angle_deg,TOL.distance_m],'SAMPLE_JS_PYTHON',{query:i,...q},maxSample);
      }
      for(let i=0;i<queries.targets.length;i++){
        const q=queries.targets[i],phase=api.data.configs[q.c].phases[q.p];testing.setLogicalTime(q.global_t);
        const actual=api.targets(phase,q.t),reference=expected.targets[i];
        if(!audit.check(actual.length===reference.length,'TARGET_COUNT_JS_PYTHON',{query:i,...q},actual.length,reference.length))continue;
        for(let j=0;j<reference.length;j++){compareVector(actual[j],reference[j],[TOL.angle_deg,TOL.angle_deg,TOL.distance_m,TOL.radius_m,TOL.fraction],'TARGET_JS_PYTHON',{query:i,target:j,...q},maxTarget);targetRows++;}
      }
      for(let i=0;i<queries.contours.length;i++){
        const reference=expected.contours[i],actual=testing.contour(...reference.args);
        audit.check(actual.length===reference.points.length,'CONTOUR_POINT_COUNT_JS_PYTHON',i);
        for(let j=0;j<Math.min(actual.length,reference.points.length);j++)compareVector(actual[j],reference.points[j],[TOL.contour_px,TOL.contour_px],'CONTOUR_JS_PYTHON',{query:i,point:j},maxContour);
      }
      audit.check(JSON.stringify(api.data)===harness.dataSnapshot,'NUMERICAL_SAMPLING_MUTATES_ATLAS_DATA',label);
      return {sample_queries:queries.samples.length,target_queries:queries.targets.length,target_rows:targetRows,contours:queries.contours.length,
        maximum_sample_errors:{yaw_deg:maxSample[0],pitch_deg:maxSample[1],distance_m:maxSample[2]},
        maximum_target_errors:{yaw_deg:maxTarget[0],pitch_deg:maxTarget[1],distance_m:maxTarget[2],radius_m:maxTarget[3],remaining_fraction:maxTarget[4]},
        maximum_contour_coordinate_errors_px:{x:maxContour[0],y:maxContour[1]}};
    });
    await audit.run(label+'_controls_and_phase_boundaries',()=>{
      const {api,testing,elements}=harness;let configurations=0,phaseControls=0,boundaryChecks=0;
      for(const config of api.data.configs){
        elements.get('program').value=config.program_id;elements.get('level').value=config.difficulty;
        harness.dispatch('program','change');harness.dispatch('level','change');
        audit.check(api.getConfig().program_id===config.program_id&&api.getConfig().difficulty===config.difficulty,'SELECTORS_SELECT_WRONG_CONFIGURATION',{program:config.program_id,level:config.difficulty});
        audit.check(api.getTime()===0&&!testing.isPlaying(),'CONFIGURATION_CHANGE_MUST_RESET_AND_PAUSE',config.program_id);
        audit.check(elements.get('phase').options.length===config.phases.length&&elements.get('phaseStrip').children.length===config.phases.length,'PHASE_CONTROLS_COUNT_MISMATCH',config.program_id);
        for(let p=0;p<config.phases.length;p++){
          const phase=config.phases[p],begin=phase.definition.start_s,end=begin+phase.definition.duration_s;
          elements.get('phase').value=String(p);harness.dispatch('phase','change');
          audit.check(api.getTime()===begin&&testing.phaseAt(api.getTime())[1]===p,'PHASE_SELECTOR_JUMPS_TO_WRONG_START',{program:config.program_id,p});phaseControls++;
          const button=elements.get('phaseStrip').children[p];button.dispatch('click');
          audit.check(api.getTime()===begin&&button.classList.contains('active'),'PHASE_STRIP_NOT_ACTIVE_AT_SELECTED_START',{program:config.program_id,p});phaseControls++;
          for(const t of [begin,Math.min(end-1e-7,begin+.1),end-1e-7]){
            api.setTime(t);const active=testing.phaseAt(t);
            audit.check(active[1]===p&&active[0].id===phase.id,'PHASE_ROUTER_WRONG_WITHIN_INTERVAL',{program:config.program_id,p,t});boundaryChecks++;
          }
          if(end<60){api.setTime(end);audit.check(testing.phaseAt(end)[1]===p+1&&testing.phaseAt(end)[2]===0,'PHASE_ROUTER_BOUNDARY_NOT_NEW_PHASE',{program:config.program_id,p,end});boundaryChecks++;}
        }
        for(const t of [0,.25,19.99,20,29.99,30,39.99,40,59.99,60]){
          elements.get('time').value=String(t);harness.dispatch('time','input');
          audit.check(Math.abs(api.getTime()-t)<=TOL.time_s,'SLIDER_TIME_MISMATCH',{program:config.program_id,level:config.difficulty,t});
        }
        const final=testing.phaseAt(60);audit.check(api.targets(final[0],final[2]).length===0,'TARGETS_REMAIN_AFTER_PROGRAM_END',{program:config.program_id,level:config.difficulty});
        harness.dispatch('reset','click');audit.check(api.getTime()===0&&!testing.isPlaying(),'RESET_DID_NOT_PAUSE_AND_REWIND',config.program_id);
        harness.dispatch('play','click');audit.check(testing.isPlaying()&&elements.get('play').textContent==='Pause','PLAY_DID_NOT_START',config.program_id);
        harness.advance(250);audit.check(Math.abs(api.getTime()-.25)<=TOL.time_s,'PLAYBACK_SPEED_NOT_ONE_SECOND_PER_SECOND',config.program_id,api.getTime(),.25);
        harness.dispatch('play','click');const paused=api.getTime();harness.advance(400);audit.check(!testing.isPlaying()&&api.getTime()===paused,'PAUSED_PLAYBACK_ADVANCES',config.program_id);
        harness.dispatch('play','click');harness.visibility(true);harness.advance(250);audit.check(!testing.isPlaying()&&api.getTime()===paused,'HIDDEN_DOCUMENT_DID_NOT_PAUSE',config.program_id);harness.visibility(false);
        api.setTime(59.99);harness.dispatch('play','click');harness.advance(50);
        audit.check(api.getTime()===60&&!testing.isPlaying(),'PLAYBACK_DID_NOT_CLAMP_AND_PAUSE_AT_END',config.program_id);
        harness.dispatch('play','click');audit.check(api.getTime()===0&&testing.isPlaying(),'PLAY_FROM_END_DID_NOT_REWIND',config.program_id);harness.advance(16);
        harness.dispatch('reset','click');audit.check(api.getTime()===0&&!testing.isPlaying(),'RESET_WHILE_PLAYING_FAILED',config.program_id);
        configurations++;
      }
      audit.check(harness.stats.network_calls===0,'ATLAS_USED_NETWORK',label);
      audit.check(JSON.stringify(api.data)===harness.dataSnapshot,'UI_CONTROLS_MUTATE_ATLAS_DATA',label);
      return {configurations,phase_selector_and_strip_actions:phaseControls,phase_boundary_checks:boundaryChecks,...harness.stats};
    });
  }
  await audit.run('audited_files_unchanged',()=>{
    for(const [key,file] of Object.entries(FILES))audit.check(hash(file)===sourceHashes[key],'AUDITED_SOURCE_CHANGED_DURING_RUN',key);
    return {shell_modified:false,delivered_html_modified:false,export_added:false};
  });
  const report={
    report_version:'aimlocal.atlas_validation.v2.0',generated_at_utc:new Date().toISOString(),status:audit.failureCount?'fail':'pass',
    environment:'Node vm with minimal simulated DOM, canvas API and animation clock; no browser',node_version:process.version,
    real_browser_test_performed:false,cua_used:false,dependencies_installed:false,shell_or_html_modified:false,
    checks:audit.checks,failure_count:audit.failureCount,failure_code_counts:audit.failureCodes,failures:audit.failures,
    numeric_tolerances:TOL,input_sha256:sourceHashes,groups:audit.groups,elapsed_s:(performance.now()-start)/1000,
    coverage_limits:[
      'This is a JavaScript execution and numerical equivalence test, not a browser acceptance test.',
      'The DOM mock supports only the properties and handlers exercised by this atlas; it does not implement the complete HTML/DOM specification.',
      'Canvas commands and finite coordinates are checked, but no pixels are rasterized and no visual screenshot comparison is performed.',
      'CSS layout, responsiveness, text clipping, fonts, browser loading, real pointer/keyboard focus and accessibility are not validated here.',
      'Animation time and visibility are simulated; display refresh, device scheduling, input latency and physical screen presentation are not measured.',
      'Samples cover all delivered configurations and phases, their serialized event boundaries and selected interior times, but not all possible future seeds.',
      'The atlas has no firing or scoring implementation; this test does not validate Godot, target replacement after human hits, contact scoring or calibration decisions.',
      'At global time 60 seconds, the oracle applies programme closure to targets_at; the underlying Python pose helper alone does not apply this caller-owned lifecycle rule.'
    ],
  };
  fs.mkdirSync(path.dirname(REPORT),{recursive:true});fs.writeFileSync(REPORT,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({status:report.status,checks:report.checks,failures:report.failure_count,report:REPORT,elapsed_s:report.elapsed_s}));
  for(const group of audit.groups)if(group.status!=='pass')console.log(JSON.stringify({failed_group:group.id,failures:group.failures}));
  process.exitCode=report.status==='pass'?0:1;
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
