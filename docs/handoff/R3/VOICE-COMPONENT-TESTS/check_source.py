from pathlib import Path
import hashlib, json, re, subprocess, xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[4]
base = '4b5ab7398cf70e153eaaf08dd09cb79cefb20ece'
folder = Path(__file__).resolve().parent
def raw(name): return (root / name).read_bytes().replace(b'\r\n', b'\n')
def old(name): return subprocess.check_output(['git', 'show', base + ':' + name], cwd=root)
def text(name): return raw(name).decode()
results = []
def check(name, passed):
    results.append({'name': name, 'pass': bool(passed)})
    assert passed, name

file = 'TinodiosUITests/VoiceLayoutTests.swift'
source = text(file)
methods = re.findall(r'^    func (test\w+)\(', source, re.M)
check('six_methods_in_actual_XCTest_class', len(methods) == 6 and source.index(methods[-1]) < source.index('private final class AccessoryFixture'))
check('actual_App_module_no_generated_adapter', '@testable import Tinodios' in source and 'let bar = SendMessageBar()' in source)
check('original_nib_asserted_in_App_bundle', 'Bundle.main.url(forResource: "SendMessageBar", withExtension: "nib")' in source)
check('unknown_host_credential_account_rejected', all(s in source for s in ['SharedUtils.getAuthToken() == nil', 'Cache.tinode.myUid == nil', 'Cache.tinode.store?.myUid == nil', '"127.0.0.1:9"', 'Unexpected host or authenticated initial state']))
check('no_data_clearing_or_login_submission', not re.search(r'\.logout\(|\.login\(|\.loginToken\(|removeItem\(|removeObject\(', source))
check('real_keyboard_notifications_and_deadline', all(s in source for s in ['keyboardDidShowNotification', 'keyboardDidHideNotification', 'software keyboard shown', 'software keyboard hidden', 'ProcessInfo.processInfo.systemUptime']))
check('real_traits_font_growth', all(s in source for s in ['bar.traitOverrides.preferredContentSizeCategory = category', 'XCTAssertGreaterThan(try XCTUnwrap(bar.audioDurationLabel.font).pointSize, normalSize)']))
check('minimum_full_button_hit_and_text_geometry', all(s in source for s in ['button.bounds.height, 52', '.contains(rectangle)', 'actualWindow.hitTest', 'needed.height + button.contentEdgeInsets.top']))
check('original_XIB_action_connections_checked', 'button.actions(forTarget: f.bar, forControlEvent: .touchUpInside)' in source)
check('handler_not_claimed_touch_recognition', 'Controlled inputs exercise the original handler, not UIKit touch recognition.' in source)
check('png_and_geometry_keepAlways', 'bar.drawHierarchy(in: bar.bounds' in source and source.count('.lifetime = .keepAlways') == 2 and 'public.json' in source)
check('evidence_before_teardown_cleanup', 'try capture("teardown-current-before-reset", value)' in source and 'defer {' in source)
check('no_secret_value_in_geometry', '"inputValue"' not in source and '"token"' not in source and 'componentDelegateHasNetworkImplementation' in source)

ci = text('Scripts/ci/verify_publish_outcomes_macos.sh')
addition = '  -only-testing:TinodiosVoiceLayoutTests/VoiceLayoutTests \\\n'
check('CI_adds_only_one_selector', ci.count(addition) == 1 and ci.replace(addition, '').encode() == old('Scripts/ci/verify_publish_outcomes_macos.sh'))
check('old_226_and_navigation_selectors_byte_preserved', re.findall(r'-only-testing:\S+', ci.replace(addition,'')) == re.findall(r'-only-testing:\S+', old('Scripts/ci/verify_publish_outcomes_macos.sh').decode()))
pod = text('Podfile')
block = "    # The real App remains the host; no duplicate production source/resource membership.\n    target 'TinodiosVoiceLayoutTests' do\n        inherit! :search_paths\n    end\n"
check('pod_hook_original_bytes_unchanged', pod.count(block) == 1 and pod.replace(block, '').encode() == old('Podfile'))
check('lock_only_podfile_checksum', re.sub(rb'PODFILE CHECKSUM: \w+', b'PODFILE CHECKSUM:', raw('Podfile.lock')) == re.sub(rb'PODFILE CHECKSUM: \w+', b'PODFILE CHECKSUM:', old('Podfile.lock')))
check('lock_matches_LF_source_sha1', ('PODFILE CHECKSUM: ' + hashlib.sha1(raw('Podfile')).hexdigest()).encode() in raw('Podfile.lock'))
check('no_production_delta', subprocess.check_output(['git','diff',base,'--name-only','--','Tinodios','TinodeSDK','TinodiosDB'],cwd=root).strip() == b'')
check('existing_native_source_tests_frozen', all(raw(p) == old(p) for p in ['TinodiosUITests/VLCPlaybackProbeTests.swift','TinodiosUITests/MediaRecorderLifecycleTests.swift','TinodiosUITests/SendMessageBarResetTests.swift','TinodiosUITests/IdentityNavigationUITests.swift','TinodiosUITests/OwnedImageTests.swift']))
check('existing_scheme_test_targets_retained', [n.attrib['BlueprintName'] for n in ET.fromstring(text('Tinodios.xcodeproj/xcshareddata/xcschemes/Tinodios.xcscheme')).findall('./TestAction/Testables/TestableReference/BuildableReference')] == ['TinodiosUITests','TinodiosVLCProbeTests','TinodiosVoiceLayoutTests'])

references = ['Tinodios/widgets/SendMessageBar.swift','Tinodios/widgets/SendMessageBar.xib','Tinodios/MessageViewController.swift','Tinodios/MessageViewController+SendMessageBarDelegate.swift']
report = {'base':base,'layer':'Source/selector checks only; real Ruby object checks separate; Swift NOT_RUN',
 'results':results,'passed':len(results),'total':len(results), 'methods':methods,
 'expected_native':{'SDK':44,'existing_UIrunner':175,'VLC_host':7,'new_App_component':6,'total':232,'navigation_separate':3},
 'production_sources':[{'path':p,'blob':subprocess.check_output(['git','rev-parse',base+':'+p],cwd=root,text=True).strip(),'sha256_LF':hashlib.sha256(raw(p)).hexdigest()} for p in references]}
(folder/'source-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Source checks {len(results)}/{len(results)}; 232+3 native expected, not executed')
