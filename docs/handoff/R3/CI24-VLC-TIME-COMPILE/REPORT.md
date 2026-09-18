# CI24 VLC time compile correction

CI24 758b062 / run35343949470: SDK44 PASS; App compilation failed at Delegate:270; UIrunner/VLC/navigation/package/cold NOT_RUN. Prior source checks missed the imported nonoptional VLCTime type.

One production expression: player.time?.value -> player.time.value. The existing if-let still checks nullable NSNumber value; no force unwrap or change to playback/owner behavior.

Official 3.6.0 Headers/Public/VLCMediaPlayer.h:372 is under NS_ASSUME_NONNULL; VLCTime.h:65 value is nullable. Actual CI compile diagnostic and already compiled VideoPreview setTime(player.time)/probe player.time.value consumers agree.

https://raw.githubusercontent.com/videolan/vlckit/3.6.0/Headers/Public/VLCMediaPlayer.h
https://raw.githubusercontent.com/videolan/vlckit/3.6.0/Headers/Public/VLCTime.h

Windows: exact one-expression diff and diff --check; not Swift compilation. No new native methods: 215 plus separate navigation3 expected for this fixed candidate. VIDEO WIP is excluded; checkpoint WIP-CI24/video-wip.patch SHA073734a3a85a2d87998fc2ee07602bc9b339d8749bd3fef830b7fba35e078701, 13172 bytes.
