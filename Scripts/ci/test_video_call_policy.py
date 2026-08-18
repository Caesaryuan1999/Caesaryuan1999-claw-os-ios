#!/usr/bin/env python3
"""Static regression checks for iOS video-call initialization."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, marker: str, message: str) -> None:
    if marker not in text:
        raise AssertionError(message)


def main() -> None:
    call = (ROOT / "Tinodios" / "CallViewController.swift").read_text(encoding="utf-8")
    plist = (ROOT / "Tinodios" / "Info.plist").read_text(encoding="utf-8")

    require(call, "cameraManager.delegate = self", "camera capture delegate must be attached")
    require(call, "webRTCClient.delegate = self", "WebRTC delegate must be attached")
    require(call, "setupViews()", "video call must create the WebRTC tracks/renderers")
    require(call, "DispatchQueue.global(qos: .background).async", "camera capture must not block the UI thread")
    require(call, "Cache.log.info(\"CallVC - video media initialized", "video call initialization must be observable")
    require(call, "didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]", "Unified Plan remote video receiver callback is missing")
    require(call, "didStartReceivingOn transceiver: RTCRtpTransceiver", "Unified Plan remote transceiver callback is missing")
    require(call, "handleRemoteVideoTrack(_ client: WebRTCClient, track: RTCVideoTrack)", "remote video track must be attached to a renderer")
    require(call, "localPeer?.add(audioTrack, streamIds: [\"ARDAMS\"])", "audio must be added as a Unified Plan track")
    require(call, "localPeer?.add(videoTrack, streamIds: [\"ARDAMS\"])", "video must be added as a Unified Plan track")
    if "localPeer?.add(stream)" in call:
        raise AssertionError("legacy add(stream) must not be used with Unified Plan")
    require(plist, "CLAW OS uses the camera for video calls", "camera permission text must explain video calls")
    require(plist, "CLAW OS uses the microphone for voice and video calls", "microphone permission text must explain video calls")

    setup_start = call.index("private func setupCaptureSessionAndStartCall()")
    setup_end = call.index("    private func checkMicPermissions", setup_start)
    setup = call[setup_start:setup_end]
    if setup.index("cameraManager.startCapture()") < setup.index("cameraManager.delegate = self"):
        raise AssertionError("camera capture starts before the delegate is attached")
    if setup.index("cameraManager.startCapture()") < setup.index("setupViews()"):
        raise AssertionError("camera capture starts before WebRTC media tracks are created")

    print("iOS video call policy checks passed.")


if __name__ == "__main__":
    main()
