"""Exact one-time PBX/selector additions; no target, dependency or workflow changes."""
from pathlib import Path

project = Path('Tinodios.xcodeproj/project.pbxproj')
text = project.read_text(encoding='utf-8')
production = ['ClawAssistantRun', 'ClawAssistantStream']
tests = ['AssistantRunTests', 'AssistantStreamTests']
names = production + tests
refs = {name: f'C1A08000000000000000{index * 2 + 1:04X}' for index, name in enumerate(names)}
builds = {name: f'C1A08000000000000000{index * 2 + 2:04X}' for index, name in enumerate(names)}
assert all(len(value) == 24 and value not in text for value in [*refs.values(), *builds.values()])

def replace(anchor, replacement):
    global text
    assert text.count(anchor) == 1, anchor
    text = text.replace(anchor, replacement)

replace('/* Begin PBXBuildFile section */', '/* Begin PBXBuildFile section */\n' + ''.join(
    f'\t\t{builds[name]} /* {name}.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {refs[name]}; }};\n'
    for name in names))
replace('/* Begin PBXFileReference section */', '/* Begin PBXFileReference section */\n' + ''.join(
    f'\t\t{refs[name]} /* {name}.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}.swift; sourceTree = "<group>"; }};\n'
    for name in names))
anchor = '\t\t\t\tC1A0A0012026091800000001 /* ClawIdentityService.swift */,'
replace(anchor, ''.join(f'\t\t\t\t{refs[name]} /* {name}.swift */,\n' for name in production) + anchor)
anchor = '\t\t\t\tC1A060000000000000000001 /* CoreListLayoutTests.swift */,'
replace(anchor, ''.join(f'\t\t\t\t{refs[name]} /* {name}.swift */,\n' for name in tests) + anchor)
anchor = '\t\t\t\tC1A0A0022026091800000001 /* ClawIdentityService.swift in Sources */,'
replace(anchor, ''.join(f'\t\t\t\t{builds[name]} /* {name}.swift in Sources */,\n' for name in production) + anchor)
anchor = 'C1A070000000000000000012, ); runOnlyForDeploymentPostprocessing = 0;'
replace(anchor, 'C1A070000000000000000012, ' + ', '.join(builds[name] for name in tests) +
        ', ); runOnlyForDeploymentPostprocessing = 0;')
project.write_text(text, encoding='utf-8', newline='\n')

script = Path('Scripts/ci/verify_publish_outcomes_macos.sh')
text = script.read_text(encoding='utf-8')
anchor = '  -only-testing:TinodiosVoiceLayoutTests/AssistantLayoutTests \\\n'
replace(anchor, anchor + ''.join(f'  -only-testing:TinodiosVoiceLayoutTests/{name} \\\n' for name in tests))
script.write_text(text, encoding='utf-8', newline='\n')
print('2 App sources + 2 existing App-hosted test sources; 2 selectors appended')
