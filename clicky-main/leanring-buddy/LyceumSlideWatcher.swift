//
//  LyceumSlideWatcher.swift
//  leanring-buddy
//
//  Watches one display during a practice run and records a snapshot every time the
//  visible slide actually changes. Feedback is anchored to these snapshots, which is
//  what turns "your talk was a bit fast" into "slide 4 took 6 seconds and you never
//  read the number on it".
//
//  Why not hashing the JPEG bytes: a menu bar clock, a blinking caret or a video
//  tile all change pixels without changing the slide. So each frame is squashed to a
//  12x8 luminance grid and compared by mean absolute difference, with the clock cell
//  excluded and a two-poll debounce before a slide is committed.
//

import AppKit
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class LyceumSlideWatcher: ObservableObject {
    @Published private(set) var slides: [LyceumSlideSnapshot] = []
    @Published private(set) var watchedDisplayName: String = "no display yet"
    @Published private(set) var secondsOnCurrentSlide: TimeInterval = 0
    @Published private(set) var isTracking = false
    /// True when the capture stopped accepting new slides (a slideshow with video).
    @Published private(set) var hasHitSlideLimit = false

    private static let signatureColumns = 12
    private static let signatureRows = 8
    /// Grid cell reserved for the macOS menu bar clock (top-right) in every comparison.
    private static let excludedSignatureCells: Set<Int> = [LyceumSlideWatcher.signatureColumns - 1]
    private static let slideChangeThreshold: Double = 0.042
    /// A change this large is trusted immediately — a real slide transition in Keynote.
    private static let slideChangeConfirmedThreshold: Double = 0.13
    private static let requiredConsecutiveDifferences = 2
    private static let pollIntervalSeconds: TimeInterval = 1.6
    private static let minimumSecondsBetweenSlides: TimeInterval = 1.2
    private static let maximumSlidesPerRun = 40

    private var pollTimerCancellable: AnyCancellable?
    private var lastCommitDate: Date?
    private var previousSignature: [Double]?
    private var committedSignature: [Double]?
    private var pendingCandidateSignature: [Double]?
    private var pendingCandidateImage: (data: Data, width: Int, height: Int)?
    private var pendingCandidateDifferenceCount = 0
    private var targetDisplayID: CGDirectDisplayID?

    func startWatching() {
        guard !isTracking else { return }
        resetRunState()
        isTracking = true

        pollTimerCancellable = Timer.publish(every: Self.pollIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    await self?.pollOnce()
                }
            }

        // Take the first snapshot right away instead of after one interval.
        Task { @MainActor [weak self] in
            await self?.pollOnce()
        }
        print("🏛️ Lyceum slide watcher: started")
    }

    func stopWatching() {
        pollTimerCancellable?.cancel()
        pollTimerCancellable = nil
        isTracking = false
    }

    /// Snapshot count as seen by the coach UI.
    var slideCount: Int { slides.count }

    func resetRunState() {
        slides = []
        previousSignature = nil
        committedSignature = nil
        pendingCandidateSignature = nil
        pendingCandidateImage = nil
        pendingCandidateDifferenceCount = 0
        lastCommitDate = nil
        secondsOnCurrentSlide = 0
        hasHitSlideLimit = false
    }

    // MARK: - Polling

    private func pollOnce() async {
        guard isTracking else { return }
        guard !hasHitSlideLimit else { return }

        guard let capture = await captureWatchedDisplay() else { return }
        let signature = Self.buildSignature(from: capture.cgImage)
        if signature.isEmpty { return }

        if committedSignature == nil {
            commitSlide(with: capture, signature: signature, reason: "first frame")
            previousSignature = signature
            return
        }

        let differenceFromCommitted = Self.meanAbsoluteDifference(between: signature, and: committedSignature ?? [])
        let differenceFromPrevious = Self.meanAbsoluteDifference(between: signature, and: previousSignature ?? [])
        previousSignature = signature

        secondsOnCurrentSlide = lastCommitDate.map { Date().timeIntervalSince($0) } ?? 0

        let isMoving = differenceFromCommitted > Self.slideChangeThreshold
            || differenceFromPrevious > Self.slideChangeThreshold

        guard isMoving else {
            // Back to the committed look: whatever motion we saw was transient
            // (hover highlight, animated chart easing back, blinking caret).
            pendingCandidateSignature = nil
            pendingCandidateImage = nil
            pendingCandidateDifferenceCount = 0
            return
        }

        let enoughTimeHasPassed = lastCommitDate.map {
            Date().timeIntervalSince($0) >= Self.minimumSecondsBetweenSlides
        } ?? true
        guard enoughTimeHasPassed else { return }

        let isDecisiveChange = differenceFromCommitted > Self.slideChangeConfirmedThreshold

        if isDecisiveChange {
            commitSlide(with: capture, signature: signature, reason: "decisive change")
            return
        }

        if let pendingCandidateSignature,
           Self.meanAbsoluteDifference(between: signature, and: pendingCandidateSignature) < Self.slideChangeThreshold {
            // The screen settled on a new stable look across two polls — commit it.
            commitSlide(with: capture, signature: signature, reason: "settled change")
            return
        }

        pendingCandidateSignature = signature
        pendingCandidateImage = capture
        pendingCandidateDifferenceCount += 1

        if pendingCandidateDifferenceCount >= Self.requiredConsecutiveDifferences {
            commitSlide(with: capture, signature: signature, reason: "sustained change")
        }
    }

    private func commitSlide(with capture: DisplayCapture, signature: [Double], reason: String) {
        guard slides.count < Self.maximumSlidesPerRun else {
            hasHitSlideLimit = true
            print("🏛️ Lyceum slide watcher: hit the \(Self.maximumSlidesPerRun) slide limit")
            return
        }

        let commitDate = Date()
        let secondsSincePrevious = lastCommitDate.map { commitDate.timeIntervalSince($0) } ?? 0

        let snapshot = LyceumSlideSnapshot(
            index: slides.count + 1,
            capturedAt: commitDate,
            secondsOnPreviousSlide: secondsSincePrevious,
            imageData: capture.jpegData,
            screenshotWidthInPixels: capture.pixelWidth,
            screenshotHeightInPixels: capture.pixelHeight,
            displayLabel: "on \(capture.displayName)"
        )

        slides.append(snapshot)
        committedSignature = signature
        previousSignature = signature
        lastCommitDate = commitDate
        secondsOnCurrentSlide = 0
        pendingCandidateSignature = nil
        pendingCandidateImage = nil
        pendingCandidateDifferenceCount = 0

        print("🏛️ Lyceum slide watcher: slide \(snapshot.index) (\(reason)) on \(capture.displayName)")
    }

    // MARK: - Capture

    private struct DisplayCapture {
        let cgImage: CGImage
        let jpegData: Data
        let pixelWidth: Int
        let pixelHeight: Int
        let displayName: String
    }

    /// Captures only the display being watched, at a size that is cheap to compare
    /// and still readable by the vision model.
    private func captureWatchedDisplay() async -> DisplayCapture? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else { return nil }

            let mouseLocation = NSEvent.mouseLocation
            var nsScreenByDisplayID: [CGDirectDisplayID: NSScreen] = [:]
            for screen in NSScreen.screens {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    nsScreenByDisplayID[screenNumber] = screen
                }
            }

            // The watched display is latched on the first poll: moving the mouse
            // mid-talk must not silently switch what we are grading.
            let selectedDisplay: SCDisplay
            if let targetDisplayID, let latchedDisplay = content.displays.first(where: { $0.displayID == targetDisplayID }) {
                selectedDisplay = latchedDisplay
            } else {
                let cursorDisplay = content.displays.first { display in
                    nsScreenByDisplayID[display.displayID]?.frame.contains(mouseLocation) ?? false
                }
                selectedDisplay = cursorDisplay ?? content.displays[0]
                targetDisplayID = selectedDisplay.displayID
            }

            let displayName = nsScreenByDisplayID[selectedDisplay.displayID]?.localizedName
                ?? "\(selectedDisplay.width)x\(selectedDisplay.height)"
            watchedDisplayName = displayName

            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let ownAppWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == ownBundleIdentifier
            }

            let filter = SCContentFilter(display: selectedDisplay, excludingWindows: ownAppWindows)
            let configuration = SCStreamConfiguration()
            let maximumDimension = 1280
            let aspectRatio = CGFloat(selectedDisplay.width) / CGFloat(max(1, selectedDisplay.height))
            if selectedDisplay.width >= selectedDisplay.height {
                configuration.width = maximumDimension
                configuration.height = Int(CGFloat(maximumDimension) / max(0.01, aspectRatio))
            } else {
                configuration.height = maximumDimension
                configuration.width = Int(CGFloat(maximumDimension) * aspectRatio)
            }

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let jpegData = NSBitmapImageRep(cgImage: cgImage)
                    .representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
                return nil
            }

            return DisplayCapture(
                cgImage: cgImage,
                jpegData: jpegData,
                pixelWidth: cgImage.width,
                pixelHeight: cgImage.height,
                displayName: displayName
            )
        } catch {
            print("⚠️ Lyceum slide watcher capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Signature maths

    /// Squashes a frame into a 12x8 luminance grid. Coarse on purpose: a slide
    /// transition is a large structural change, a hover state is not.
    private static func buildSignature(from cgImage: CGImage) -> [Double] {
        let columns = signatureColumns
        let rows = signatureRows
        var pixelBuffer = [UInt8](repeating: 0, count: columns * rows * 4)

        guard let context = CGContext(
            data: &pixelBuffer,
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: columns * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: rows))

        var luminanceValues: [Double] = []
        luminanceValues.reserveCapacity(columns * rows)

        for cellIndex in 0..<(columns * rows) {
            let columnIndex = cellIndex % columns
            let rowIndex = cellIndex / columns
            if rowIndex == 0 && excludedSignatureCells.contains(columnIndex) { continue }

            let red = Double(pixelBuffer[cellIndex * 4]) / 255.0
            let green = Double(pixelBuffer[cellIndex * 4 + 1]) / 255.0
            let blue = Double(pixelBuffer[cellIndex * 4 + 2]) / 255.0
            luminanceValues.append(0.299 * red + 0.587 * green + 0.114 * blue)
        }

        return luminanceValues
    }

    private static func meanAbsoluteDifference(between signatureA: [Double], and signatureB: [Double]) -> Double {
        guard !signatureA.isEmpty, signatureA.count == signatureB.count else { return 1 }
        var totalDifference: Double = 0
        for index in 0..<signatureA.count {
            totalDifference += abs(signatureA[index] - signatureB[index])
        }
        return totalDifference / Double(signatureA.count)
    }
}
