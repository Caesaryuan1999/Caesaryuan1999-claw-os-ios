from pathlib import Path
import ast,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[4]
BASE='63b8fe4ae4092311745a5159ea523e90ed82857d'
def read(p):return (ROOT/p).read_text(encoding='utf8')
def old(p):return subprocess.check_output(['git','show',BASE+':'+p],cwd=ROOT).decode()
checks={}
rec=read('Tinodios/MediaRecorder.swift');vc=read('Tinodios/MessageViewController.swift')
delegate=read('Tinodios/MessageViewController+SendMessageBarDelegate.swift')
bar=read('Tinodios/widgets/SendMessageBar.swift');cache=read('Tinodios/Cache.swift')
interactor=read('Tinodios/MessageInteractor.swift')
permission=rec.split('session.requestRecordPermission {')[1].split('        case .granted:')[0]
checks['permission_callback_never_starts']='startRecording(' not in permission and '.start(' not in permission and 'self.permissionRequest == request' in permission
checks['no_recorder_IUO']=re.search(r'(AVAudioRecorder|MediaRecordingEngine)!',rec) is None
checks['completed_first_stop_retained']='if let completed = completed { return completed }' in rec
checks['actual_read_failure_preserves_preview']='data = try readData(recording.url)' in rec and 'guard recording.duration >= minimumDuration' in rec
checks['cache_marks_before_retirement_outside_locks']='defer { retiredRecorder?.finishRetirement() }' in cache and 'recorder?.markRetired()' in cache
checks['no_dynamic_recorder_consumer']='Cache.mediaRecorder' not in vc+delegate+bar
checks['same_owner_generation_store_gate']='owner.store?.myUid == uid' in vc+interactor and 'Cache.sessionGeneration == generation' in vc+interactor
checks['inactive_keeps_preview']='suspendVoiceRecording()' in vc.split('func appGoingInactive()')[1].split('@objc')[0] and 'voicePausedNotice = true' in vc
checks['page_leave_discards_lease']='voicePageActive = false\n        discardVoiceRecording()' in vc
checks['submit_before_release']='recorder.didSubmit(recording)\n            discardVoiceRecording()' in vc
checks['preview_only_after_real_recorder']='voiceUI(recorder) { sendMessageBar.recordingDidStart() }' in delegate
checks['no_optimistic_player_start']='self.delegate?.sendMessageBar(recordAudio: .playbackStart)' in bar and 'showAudioBar(.longPlayback)' not in bar.split('@IBAction func playRecording')[1].split('@IBAction')[0]
checks['player_callback_identity']='self.recordingPlaybackPlayer === player' in delegate
checks['upload_captured_helper']='audioHelper ?? Cache.getLargeFileHelper()' in interactor and 'guard audioScope == nil || audioHelper != nil' in interactor
checks['audio_success_captured_origin']='draftyAudio(refurl: srvUrl,' in interactor and interactor.count('baseURL: audioBase)')==2
checks['other_drafty_helpers_unchanged']=all(
 re.search(r'(?ms)^    private static func '+name+r'\(.*?^    \}\n',interactor)[0] ==
 re.search(r'(?ms)^    private static func '+name+r'\(.*?^    \}\n',old('Tinodios/MessageInteractor.swift'))[0]
 for name in ['draftyFile','draftyImage','draftyVideo'])
checks['audio_sampler_unchanged']=rec.split('// Class for generating audio preview')[1]==old('Tinodios/MediaRecorder.swift').split('// Class for generating audio preview')[1]
checks['original_text_sender_unchanged']=interactor.split('    func sendMessage(content: Drafty) {')[1].split('    func sendReadNotification')[0]==old('Tinodios/MessageInteractor.swift').split('    func sendMessage(content: Drafty) {')[1].split('    func sendReadNotification')[0]
graph_source=read('docs/handoff/R3/CI19-VLC-HOST-DIAG/verify_wiring.py')
node=next(n for n in ast.parse(graph_source).body if isinstance(n,ast.FunctionDef) and n.name=='parse')
scope={'re':re,'json':json};exec(ast.get_source_segment(graph_source,node),scope)
parse=scope['parse'];before=parse(old('Tinodios.xcodeproj/project.pbxproj'))['objects'];after=parse(read('Tinodios.xcodeproj/project.pbxproj'))['objects']
changed={k for k in before if before[k]!=after[k]}
checks['only_UIrunner_group_and_sources_changed']=changed=={'0AE21E4C28D21849008F486C','0AE21E4728D21849008F486C'}
checks['three_graph_objects_added']=len(set(after)-set(before))==3
checks['exact_production_recorder_in_test_target']='C1A046022026091800000001' in after['0AE21E4728D21849008F486C']['files']
script=read('Scripts/ci/verify_publish_outcomes_macos.sh')
selectors=re.findall(r'-only-testing:([^\s\\]+)',script)
prior=re.findall(r'-only-testing:([^\s\\]+)',old('Scripts/ci/verify_publish_outcomes_macos.sh'))
checks['only_one_new_selector']=[x for x in selectors if x!='TinodiosUITests/MediaRecorderLifecycleTests']==prior
methods=re.findall(r'func (test\w+)\(',read('TinodiosUITests/MediaRecorderLifecycleTests.swift'))
checks['eight_actual_class_methods']=len(methods)==8 and 'MediaRecorder(' in read('TinodiosUITests/MediaRecorderLifecycleTests.swift')
counts={}
for sel in selectors:
 if sel.startswith('TinodeSDKTests/'):path='TinodeSDKTests/TinodeSDKTests.swift'
 else:
  cls=sel.split('/')[1]
  candidates=[p for p in (ROOT/'TinodiosUITests').glob('*.swift') if re.search(r'class '+cls+r'\b',p.read_text(encoding='utf8'))]
  assert len(candidates)==1,(cls,candidates)
  path=str(candidates[0].relative_to(ROOT))
 source=read(path);cls=sel.split('/')[1]
 start=re.search(r'(?m)^(?:final )?class '+cls+r'\b',source).start()
 tail=source[start:];following=re.search(r'(?m)^(?:final )?class \w+',tail[tail.index('\n')+1:])
 part=tail[:tail.index('\n')+1+following.start()] if following else tail
 counts[sel]=len(re.findall(r'func test\w+\(',part))
checks['expected_native_210']=sum(v for k,v in counts.items() if not k.endswith('/IdentityNavigationUITests'))==210
checks['navigation_3_preserved']=counts['TinodiosUITests/IdentityNavigationUITests']==3 and read('TinodiosUITests/IdentityNavigationUITests.swift')==old('TinodiosUITests/IdentityNavigationUITests.swift')
checks['VLC_four_bytes_preserved']=read('TinodiosUITests/VLCPlaybackProbeTests.swift')==old('TinodiosUITests/VLCPlaybackProbeTests.swift')
report={'layer':'Windows source/graph checks only; AV/system/UIKit/Swift NOT_RUN','checks':checks,'methods':methods,'counts':counts,'passed':sum(checks.values()),'total':len(checks)}
(Path(__file__).parent/'source-checks.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,indent=2));assert all(checks.values())
