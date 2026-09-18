// Copyright (c) 2026 CLAW OS contributors.
// Production-method source adapter + real UIKit constraints; not a loaded XIB or chat page.
import XCTest
import UIKit

final class SendMessageBarResetTests: XCTestCase {
    private func onMain(_ body: () -> Void) {
        if Thread.isMainThread { body() }
        else { DispatchQueue.main.sync(execute: body) }
    }

    func testResetBeforeAnyGesturePreservesLayoutAndClearsPresentation() {
        onMain {
            let bar = SendMessageBarResetSource()
            bar.sendButtonHorizontal.constant = -37
            bar.sendButtonVertical.constant = -29
            bar.recordingStarted = true
            bar.audioLocked = true
            bar.sendButtonSize.constant = 54
            bar.verticalSliderView.isHidden = false
            bar.horizontalSliderView.isHidden = false
            bar.resetRecordingState()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, -37)
            XCTAssertEqual(bar.sendButtonVertical.constant, -29)
            XCTAssertFalse(bar.recordingStarted)
            XCTAssertFalse(bar.audioLocked)
            XCTAssertTrue(bar.verticalSliderView.isHidden)
            XCTAssertTrue(bar.horizontalSliderView.isHidden)
            XCTAssertEqual(bar.sendButtonSize.constant, bar.normalButtonSize)
            XCTAssertNil(bar.sendButtonConstrains)
            XCTAssertEqual(bar.hiddenPresentationCalls, 1)
        }
    }

    func testResetRestoresCapturedGestureAndConsumesSnapshot() {
        onMain {
            let bar = SendMessageBarResetSource()
            bar.sendButtonHorizontal.constant = -41
            bar.sendButtonVertical.constant = -31
            bar.captureCurrentLayoutForGesture()
            bar.sendButtonHorizontal.constant = -90
            bar.sendButtonVertical.constant = -82
            bar.resetRecordingState()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, -41)
            XCTAssertEqual(bar.sendButtonVertical.constant, -31)
            XCTAssertNil(bar.sendButtonConstrains)
            XCTAssertEqual(bar.hiddenPresentationCalls, 1)
        }
    }

    func testRepeatedResetDoesNotOverwriteLaterLayout() {
        onMain {
            let bar = SendMessageBarResetSource()
            bar.sendButtonHorizontal.constant = -26
            bar.sendButtonVertical.constant = -28
            bar.captureCurrentLayoutForGesture()
            bar.resetRecordingState()
            bar.sendButtonHorizontal.constant = -63
            bar.sendButtonVertical.constant = -47
            bar.resetRecordingState()
            bar.resetRecordingState()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, -63)
            XCTAssertEqual(bar.sendButtonVertical.constant, -47)
            XCTAssertNil(bar.sendButtonConstrains)
            XCTAssertEqual(bar.hiddenPresentationCalls, 3)
        }
    }

    func testNextGestureCapturesCurrentLayoutInsteadOfPriorSnapshot() {
        onMain {
            let bar = SendMessageBarResetSource()
            bar.sendButtonHorizontal.constant = -26
            bar.sendButtonVertical.constant = -28
            bar.captureCurrentLayoutForGesture()
            bar.resetRecordingState()
            bar.sendButtonHorizontal.constant = -52
            bar.sendButtonVertical.constant = -39
            bar.captureCurrentLayoutForGesture()
            bar.sendButtonHorizontal.constant = -111
            bar.sendButtonVertical.constant = -88
            bar.resetRecordingState()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, -52)
            XCTAssertEqual(bar.sendButtonVertical.constant, -39)
            XCTAssertNil(bar.sendButtonConstrains)
            XCTAssertEqual(bar.hiddenPresentationCalls, 2)
        }
    }
}
