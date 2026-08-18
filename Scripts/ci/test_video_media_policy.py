#!/usr/bin/env python3
"""Static regression checks for iOS video attachment delivery."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, marker: str, message: str) -> None:
    if marker not in text:
        raise AssertionError(message)


def main() -> None:
    preview = (ROOT / "Tinodios" / "VideoPreviewController.swift").read_text(encoding="utf-8")
    send = (ROOT / "Tinodios" / "MessageViewController.swift").read_text(encoding="utf-8")
    picker = (ROOT / "Tinodios" / "widgets" / "ImagePicker.swift").read_text(encoding="utf-8")

    require(
        preview,
        "DispatchQueue.main.async { self.becomeFirstResponder() }",
        "video preview must expose its input accessory after presentation",
    )
    require(
        preview,
        "private var didSubmitVideo = false",
        "video send must be guarded against duplicate taps",
    )
    require(
        preview,
        "!didSubmitVideo else { return }",
        "video send guard is missing",
    )
    require(
        send,
        "Cache.log.info(\"MessageVC - sending video attachment",
        "video send path must emit an evidence log before reading/uploading the file",
    )
    require(
        picker,
        "case kUTTypeMovie:",
        "picker must keep a movie branch",
    )
    require(
        picker,
        "Utils.mimeForUrl(url: swiftUrl, ifMissing: \"video/quicktime\")",
        "picker must preserve a video MIME type instead of converting it to an image",
    )

    print("iOS video media policy checks passed.")


if __name__ == "__main__":
    main()
