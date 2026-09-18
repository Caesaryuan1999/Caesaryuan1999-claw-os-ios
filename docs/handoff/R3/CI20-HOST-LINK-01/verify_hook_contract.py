from pathlib import Path
import hashlib,json,re,subprocess
root=Path(__file__).resolve().parents[4]
pod=(root/'Podfile').read_text(encoding='utf8')
lock=(root/'Podfile.lock').read_text(encoding='utf8')
base_pod=subprocess.check_output(['git','show','c0971f929dc3550683817a59cb768fb389a3fc1f:Podfile'],cwd=root).decode()
base_lock=subprocess.check_output(['git','show','c0971f929dc3550683817a59cb768fb389a3fc1f:Podfile.lock'],cwd=root).decode()
start=pod.index("  # Only the empty VLC host")
end=pod.index("  # See explanation here:",start)
hook=pod[start:end]
checks={}
checks['only_bounded_hook_added']=pod[:start]+pod[end:]==base_pod
checks['lock_only_podfile_checksum']=re.sub(r'PODFILE CHECKSUM: [0-9a-f]+','PODFILE CHECKSUM:',lock)==re.sub(r'PODFILE CHECKSUM: [0-9a-f]+','PODFILE CHECKSUM:',base_lock)
checks['podfile_lock_matches']=hashlib.sha1((root/'Podfile').read_bytes().replace(b'\r\n',b'\n')).hexdigest()==re.search(r'PODFILE CHECKSUM: (\w+)',lock).group(1)
checks['explicit_two_target_allowlist']='probe_targets = %w[TinodiosVLCProbeHost TinodiosVLCProbeTests]' in hook and 'next unless probe_targets.include?(user_target.name)' in hook
checks['generated_own_config_required']="aggregate_target.xcconfigs.fetch(config.name).attributes.fetch('OTHER_LDFLAGS')" in hook
checks['parent_inheritance_removed']="generated.gsub('$(inherited)', '').gsub('${inherited}', '').strip" in hook
checks['single_setting_override']=re.findall(r"config.build_settings\['([^']+)'\]",hook)==['OTHER_LDFLAGS']
checks['host_frameworks_required']='%w[MobileVLCKit Kingfisher SQLite SwiftKeychainWrapper]' in hook
checks['foreign_dependency_rejected']='Firebase|FBLPromises|GoogleAppMeasurement|WebRTC' in hook
checks['both_targets_required']='configured_probe_targets.sort == probe_targets.sort' in hook
red=json.loads((Path(__file__).parent/'ci20-link-red.json').read_text())
checks['actual_red_link_commands']=len(red['links'])==2 and all('FBLPromises' in x['frameworks'] for x in red['links'])
checks['actual_dyld_failure']=len(red['dyld'])>0
report={'layer':'Windows source/lock/evidence checks; not Ruby/CocoaPods/Xcode execution','checks':checks,'passed':sum(checks.values()),'total':len(checks)}
print(json.dumps(report,indent=2))
(Path(__file__).parent/'source-checks.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
assert all(checks.values())
