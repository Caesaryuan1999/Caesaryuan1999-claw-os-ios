# CI50 — actual native result and bounded successors

Source `1aea86fb87f42a7d2d6215635c7c744262c8943e`, run `35478057066`, job `105990668493`, attempt 1 failed naturally. The run was created at `2026-09-20T00:10:15Z`; native tests ended at `00:22:39Z`, the test command reported failure at `00:22:58Z`, and the last job-log timestamp is `00:23:14.4931000Z`. Local observation resumed at `15:25 +08:00` after a requested 60-second sleep returned after 25604 seconds. That observation gap is not the CI duration. No cancellation, repeat dispatch or same-source retry occurred.

The exact original artifact `10594579051` is 106809960 bytes, SHA-256 `a9a9ee544f4826fb6e51c567bfb151443b655faa36ee925df7fc1bfeef73002a`. It is preserved in `evidence/CI50-evidence.zip`, extracted without alteration to `evidence/CI50-original/ios-01-a-20260920-001047`. `CI50-native-evidence-index.json` binds the source, counts and 179 relevant original attachments to their names, methods, absolute paths and SHA-256 values.

SDK44 passed. Storage/app tests executed 292 methods: 286 passed, 6 failed, none skipped. Total native is **330 passed / 6 failed**. Navigation, unsigned package and cold launch did not run. Compilation succeeded: the CI49 MessageCell diagnostics at lines 193, 200 and 212 are closed by this compiler run, not by the earlier source review. CoreList6 and compact voice3 passed.

## Six Image methods

| Method suffix | Actual result | Original diagnostic |
| --- | --- | --- |
| FullFormatterPreservesOrdinaryGeometryAndUsesDecodedBeforeUnknown | FAIL | line 63: decoded 240×120 versus expected 80×40 |
| LongTopAndUnknownFitRenderActualPixelsWithoutChangingCanvas | PASS | actual raster pixel checks |
| ActualMessageCellLongImageInBothDirectionsAndAccessibilityAppearances | FAIL | line 127: height 242.18666666666672 versus 242.1866666666667 |
| OwnedAttachmentRetryKeepsCanvasAndRejectsCancelledAndRetiredCallbacks | FAIL | line 290: `first failure`, original 3-second wait |
| ActualRetryConsumerRechecksEntityPageBulkSelectionAndReuse | FAIL | line 290: `retry available`, original 3-second wait |
| RealHTTPFailureRetryUsesOriginalOwnerAndShowsClearTextAction | FAIL | line 290: `real HTTP 403`, original 3-second wait |

Only the pixel test reached its attachment capture: `84F0D76F-1D5D-48CD-98C9-D1A9C1967D31.png` is unknown FIT and `A4DC4C51-64DB-4EE6-A8F7-8908CB4B5892.png` is long TOP. These are synthetic renderer images, not complete message screenshots. The other five failed before their planned captures; there is no full Image-cell PNG/geometry evidence from this run.

The first geometry expectation compared the renderer's point size with PNG bytes decoded by UIImage at scale 1. The legacy formatter correctly uses the latter. The second comparison differs by approximately 5.7e-14 pt through UIView geometry conversion. Test-only successor `45bc5cdab4da2e28b8486ac2aecff0dbf12cf018` uses the same bytes' actual UIImage decoding for the legacy-path oracle and compares overlay axes with absolute 1e-9 pt accuracy. Existing ratio, maximum, containment, binding and retry checks remain. Its inverse reproduces the complete prior file; the six method names are unchanged.

The three wait failures remain **unclassified**. Both controlled transports reached their first request and passed the existing count assertion before the error callback was invoked. That establishes initial context/resource/consumer admission; it does not prove the queued completion entered, which later guard accepted it, or the state at timeout. Original evidence contains no state/request-stage attachment for these methods. The HTTP case likewise lacks a request-count snapshot. An owner failure, production defect, or predicate/scheduling defect cannot be selected from these records.

Diagnostic successor `dfb7bc04be8491bad9b461132b003a3995c220fc` changes only that test file. At every existing cutoff it saves current state, consumer/source checks, current owner scope, transport/HTTP request counts, controlled callback counts, a passive main-queue marker and predicate evaluations before the existing failure assertion. The observed context shares the same owner and generation (or the controller context); it is not a direct read of the attachment's private context instance. No production probe, extra drain, forced state, new wait or relaxed condition was added. All existing assertion lines and six methods remain.

## AAC evidence and independent PCM control

The existing AAC method failed at VoiceLayoutTests line 734: production finish did not complete within its original three seconds. Both bare and production deadline JSONs independently report timeout, zero same-engine successful finishes, and no getter-free delegate-entry event. The event buffers were not full. Main-thread samples continued; currentTime reached duration 1 while isPlaying stayed true, with loops 0 and the expected engine/delegate. Production scope remained current. The original bare assertions follow line 734 and were not reached; bare failure is established by its original deadline JSON.

Bare deadline: `7070EF9E-40BA-4EC7-A647-EA737F1CE069.json`. Production deadline: `8C8BDBAF-BC24-4FB9-BE51-B91F71357CCE.json`. Final bare/production traces are `51A99855-EFD4-4AB8-A67C-B1DC74E1C06E.json` and `A07B80C2-F71D-44DD-8A60-802564E27A68.json`, under the original storage-attachments directory. This result does not support the previously considered pre-entry AV-getter observation blind spot. It does not establish a production-player or platform root cause.

Independent test-only successor `0877d9a8411b0835a1076b426a92da64e0ab9468` adds one bare AVAudioPlayer control with canonical one-second PCM RIFF/WAVE bytes: 16000 Hz, mono, signed 16-bit little endian, 32000 data bytes and 44 header bytes. It uses the real same-engine delegate, Playback session, and an async wait outside MainActor with the same three-second bound. Original bytes and deadline observations are attached before the strict completion/finish-count assertions. Only this control's engine is stopped during cleanup. Removing the new method reproduces the complete previous VoiceLayoutTests file; all original 20 methods, AAC generation and observer helpers are unchanged. Actual execution order must be read from the next original log, not inferred as a runtime result here.

The three successors affect two test files only; production, selector, PBX, dependencies and workflow remain unchanged. Windows diff/inverse/assertion checks passed; all successors are **NOT_RUN** on Mac. Expected next selection is **337 native + 3 navigation**, not a passed count. They have not been pushed or dispatched in this report. Root/backend fixed-source review gates one later combined diagnostic run. Rollback is reversal of these three test commits in reverse order; the original CI50 source and all earlier failures remain intact.
