"""Read-only source inventory and route evidence. Never reads credentials/caches."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PATHS = '''Tinodios/Base.lproj/Main.storyboard
Tinodios/AppDelegate.swift
Tinodios/Cache.swift
Tinodios/UiUtils.swift
Tinodios/ChatListInteractor.swift
Tinodios/ChatListRouter.swift
Tinodios/ChatListViewController.swift
Tinodios/NewChatTabController.swift
Tinodios/LoginViewController.swift
Tinodios/SignupViewController.swift
Tinodios/ResetPasswordViewController.swift
Tinodios/CredentialsViewController.swift
Tinodios/CredentialsChangeViewController.swift
Tinodios/ClawIdentityFlow.swift
Tinodios/ClawIdentityService.swift
Tinodios/BrandingViewController.swift
Tinodios/MessageViewController.swift
Tinodios/MessageViewController+Keyboard.swift
Tinodios/MessagePresenter.swift
Tinodios/MessageInteractor.swift
Tinodios/ForwardToViewController.swift
Tinodios/widgets/SendMessageBar.swift
Tinodios/widgets/ImagePicker.swift
Tinodios/MediaRecorder.swift
Tinodios/format/FullFormatter.swift
Tinodios/format/AsyncImageTextAttachment.swift
Tinodios/ImagePreviewController.swift
Tinodios/VideoPreviewController.swift
Tinodios/FilePreviewController.swift
Tinodios/LargeFileHelper.swift
Tinodios/FindViewController.swift
Tinodios/AddByIDViewController.swift
Tinodios/account/ContactsSynchronizer.swift
Tinodios/account/ContactsManager.swift
Tinodios/NewGroupViewController.swift
Tinodios/EditMembersViewController.swift
Tinodios/TopicInfoViewController.swift
Tinodios/TopicSecurityViewController.swift
Tinodios/ArchivedChatsTableViewController.swift
Tinodios/BlockedContactsTableViewController.swift
Tinodios/AccountSettingsViewController.swift
Tinodios/AccountGeneralSettingsViewController.swift
Tinodios/SettingsNotificationsViewController.swift
Tinodios/SettingsSecurityViewController.swift
Tinodios/SettingsHelpViewController.swift
Tinodios/Utils.swift
Tinodios/ClawAssistantViewController.swift
Tinodios/ClawAssistantHistoryViewController.swift
Tinodios/ClawAssistantConversationViewController.swift
Tinodios/ClawAssistantHistory.swift
Tinodios/ClawAssistantRun.swift
Tinodios/ClawAssistantStream.swift
Tinodios/ClawAssistantSession.swift
Tinodios/CallViewController.swift
TinodiosDB/SharedUtils.swift
TinodiosDB/SqlStore.swift
TinodiosDB/BaseDb.swift
TinodiosDB/AccountDb.swift
TinodiosDB/MessageDb.swift
TinodeSDK/Tinode.swift
TinodeSDK/PromisedReply.swift
Podfile.lock
.github/workflows/ios-smoke.yml
docs/handoff/R4/QUALITY01/CI50-RESULT.md
docs/handoff/R4/QUALITY01/CI51-RESULT.md
docs/handoff/R4/QUALITY01/FINAL-CI51-HANDOFF.md'''.splitlines()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()

entries = []
for relative in PATHS:
    raw = (ROOT / relative).read_bytes()
    entries.append({'path':relative, 'bytes':len(raw), 'sha256':hashlib.sha256(raw).hexdigest(),
                    'lf_sha256':hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest()})
tree = ET.fromstring((ROOT / PATHS[0]).read_bytes())
routes = [{ 'element':node.tag, **{key:node.get(key) for key in ('id','storyboardIdentifier','customClass','destination','identifier','kind') if node.get(key)}}
          for node in tree.iter() if node.tag in ('viewController','tableViewController','collectionViewController','navigationController','tabBarController','segue')]
report = {'time':dt.datetime.now().astimezone().isoformat(), 'workspace':str(ROOT),
          'branch':git('branch','--show-current'), 'head':git('rev-parse','HEAD'),
          'origin':'https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git',
          'initial_baseline':'79f015f47b15fd7124f81d52205de5c5508f370e',
          'initial_tracked_dirty':0, 'initial_untracked_count':23538,
          'current_tracked_dirty':git('status','--porcelain','--untracked-files=no'),
          'level':'file_identity_and_static_route_inventory_not_runtime', 'inputs':entries, 'routes':routes}
parser = argparse.ArgumentParser()
parser.add_argument('--name', default='source-inventory.json')
args = parser.parse_args()
assert Path(args.name).name == args.name and args.name.endswith('.json')
with (HERE/args.name).open('x', encoding='utf-8') as stream:
    json.dump(report, stream, ensure_ascii=False, indent=2)
print(json.dumps({'head':report['head'], 'source_files':len(entries), 'storyboard_route_elements':len(routes),
                  'tracked_dirty':report['current_tracked_dirty'], 'runtime':'NOT_RUN'}))
