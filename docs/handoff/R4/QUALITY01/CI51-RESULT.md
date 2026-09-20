# CI51 — dependency connection blocked before native execution

One authorized non-force push advanced the verification branch from `1aea86fb87f42a7d2d6215635c7c744262c8943e` to reviewed test-only successor `0877d9a8411b0835a1076b426a92da64e0ab9468`. Dispatch at `2026-09-20T15:48:54+08:00` returned HTTP 204. Run `35497878843`, job `106044188211`, attempt 1 was created at `07:48:56Z` and naturally failed while installing dependencies at `07:52:04Z`; its final log timestamp is `07:52:07.2570610Z`.

The locked MobileVLCKit 3.6.0 download failed with curl code 7: connection to `download.videolan.org:443` failed after 75011 ms. The actual source selected by CocoaPods was:

`https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz`

Static source policies passed 44/44. **No Swift native method ran.** SDK, storage, Image diagnostics, independent PCM control, navigation, packaging and cold launch are all NOT_RUN in this run. The planned 337 native + 3 navigation count is not an execution result. This is a dependency connection failure, not a new source or test failure; CI50's original 330-pass/6-fail evidence remains unchanged.

Artifact `10600947207` is preserved as `evidence/CI51-evidence.zip`: 5065 bytes, SHA-256 `cf9c4c4b9e3bdc090da06aa9aaa086e97373c49ee2910ef33b9598082e1db475`. It contains only original `static.json` and `simulator-id.txt`, extracted to `evidence/CI51-original/ios-01-a-20260920-074932`. The decoded GitHub job log is retained separately as `evidence/CI51-job.log`; entity hashes and bounds are in `evidence/CI51-result.json`. No native-success or screenshot index was generated for CI51.

Read-only dependency/cache check: `Podfile.lock` pins 3.6.0 and spec checksum `8fe98ae53b7464f32e4bdf527cc7d53053e4d3a5`; that checksum is not the archive's hash. `Scripts/ci/verify_publish_outcomes_macos.sh:20` runs ordinary `pod install`; its later installed-header/binary and dual-lock checks were not reached. The existing `.github/workflows/ios-smoke.yml` has no explicit cache restore/save step, and artifact uploads exclude Pods and the downloaded SDK archive. This Windows worktree has no `Pods` directory, and the checked user CocoaPods/cache locations do not exist. No complete trusted SDK-archive cache was established by this bounded check; earlier App-embedded framework binaries are not treated as an SDK archive substitute.

The Pod version, lock, source URL, TLS settings, workflow, production code and assertions remain unchanged. There has been no automatic retry or new dispatch. Root coordinates a separate bounded availability check; a later retry requires new evidence and authorization. All three test successors remain preserved and unexecuted on Mac.
