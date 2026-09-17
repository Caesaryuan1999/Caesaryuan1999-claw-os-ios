from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MESSAGE_VIEW = (ROOT / "Tinodios" / "MessageViewController.swift").read_text(encoding="utf-8")
FORMAT_NODE = (ROOT / "Tinodios" / "format" / "FormatNode.swift").read_text(encoding="utf-8")


assert "static let maxTextWidth: CGFloat = 360" in MESSAGE_VIEW
assert "static let viewportFraction: CGFloat = 0.76" in MESSAGE_VIEW

audio_start = FORMAT_NODE.index("private func createAudioAttachmentString")
audio_end = FORMAT_NODE.index("private func createImageAttachmentString", audio_start)
audio_formatter = FORMAT_NODE[audio_start:audio_end]
assert "speaker.wave.2.fill" in audio_formatter
assert "WaveTextAttachment(" not in audio_formatter
assert "Linebreak." not in audio_formatter
