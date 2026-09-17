# UI04 COPY
- Parent: 003a1df9cfa5b4699540e160b390a8edd10bb3d5.
- Two production files only: TopicInfoViewController.swift title and zh-Hans.lproj/Main.strings.
- Actual storyboard route TopicInfo2TopicGeneral targets awR-up-0dD; its navigation item is zww-h7-9s0 and private-comment field is K4E-ne-sW4. Only those two locale keys changed; Do2-Ue-UdA belongs to a different route and is untouched.
- Visible copy: 聊天信息 / 聊天资料 / 备注（仅自己可见）. No state/API/storage or other locales changed.
- Windows: exact object-ID XML route checks and git diff --check PASS. Native method expectation stays 135. UIKit runtime NOT_RUN; CI7 remains immutable 003a1df and excludes this copy commit.
- Follow-up source policy now expects the authorized 聊天信息 title (previous exact old-label assertion was obsolete); all other layout assertions retained.
