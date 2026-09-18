# CI11 control timestamp fixture correction

Failed exact source d381e074fd1ede395f6c21a658f37020661acd78, run35310934859/job105492648265.
Root inspected actual Mac output: SDK41 attempted, nine deletion methods/thirteen assertions failed with missing required ctrl.ts (keyNotFound). Storage, packaging and cold launch were blocked. This does not validate later business assertions in those methods.

One test-only data change: deletionPacket adds fixed protocol timestamp 2026-09-18T01:00:00.000Z. MsgServerCtrl.ts remains required and production decoding is untouched. All request codes, request IDs, owner/Store/session expectations, malformed packet cases and cleanup assertions are byte-identical after replacing this one literal.
No production changes. Expected181 native methods unchanged; corrected fixture NOT_RUN locally because Windows has no Xcode. Existing failed CI evidence and FINAL-D381E07 patch are retained; cumulative package not regenerated while independent review is pending.
