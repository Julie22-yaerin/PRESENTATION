//
//  LyceumPresenceCamera.swift
//  leanring-buddy
//
//  Optional, off by default. When a student switches it on, the app takes a small
//  still from the front camera every few seconds while they rehearse, and the
//  grading model gets those stills alongside the slides so it can say something
//  about posture, eye contact and hands instead of guessing from the audio.
//
//  The deliberate limits, all of them here on purpose:
//  - stills, not video. No recording exists, so nothing can leak, and a run costs
//    a few hundred kilobytes rather than a file the user has to trust us with.
//  - the frames live in memory for the length of one review and are then dropped.
//    They are never written to Application Support and never attached to a saved
//    session.
//  - downscaled before leaving the machine. A full-resolution face is not needed
//    to notice that someone turned round to read the slide.
//  - the prompt asks only for what a frame shows. No emotion reading, no
//    attractiveness, no identity, no age or gender inference. Those are both bad
//    coaching and the kind of claim a still image cannot support.
//

import AVFoundation
import AppKit
import Foundation

/// One still, tagged with where in the run it fell so the model can line it up
/// against the slide that was on screen at the time.
struct LyceumPresenceFrame {
    let secondsIntoRun: Double
    let imageData: Data
    let widthInPixels: Int
    let heightInPixels: Int

    var modelLabel: String {
        let minutes = Int(secondsIntoRun) / 60
        let seconds = Int(secondsIntoRun) % 60
        return "presenter at \(minutes):\(String(format: "%02d", seconds)) — front camera still, \(widthInPixels)x\(heightInPixels) pixels"
    }
}

@MainActor
final class LyceumPresenceCamera {
    /// A 12-second interval gives a 10-minute run about fifty chances, and we only
    /// ever send ten. Shorter intervals make the stills useless for gestures; longer
    /// ones miss the moments.
    static let defaultIntervalSeconds: TimeInterval = 12
    static let minimumIntervalSeconds: TimeInterval = 5
    static let maximumIntervalSeconds: TimeInterval = 120

    /// What goes to the model. Beyond this the slides — the thing the student
    /// actually asked about — start losing out on the token budget.
    static let maximumFramesSentForReview = 10

    /// In-memory ceiling. A ten-minute run at 12s is ~50 frames, and truncating to
    /// the first twenty-four would lose the ending, so the cap spreads instead.
    private static let hardMemoryCap = 24

    private(set) var frames: [LyceumPresenceFrame] = []

    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureTask: Task<Void, Never>?
    /// AVFoundation keeps only a weak reference to the delegate, so the camera holds
    /// each token until its frame comes back.
    private var retainedTokens: [LyceumPhotoCaptureToken] = []

    fileprivate var currentRunStartedAt: Date?

    var intervalSeconds: TimeInterval = LyceumPresenceCamera.defaultIntervalSeconds
    var lastErrorMessage: String?

    var framesCaptured: Int { frames.count }
    var isCapturing: Bool { captureTask != nil }
    var permissionStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    // MARK: - Permission

    /// Asks once and remembers. A false return is a normal outcome: plenty of
    /// students keep this off, and a run is complete without it.
    func ensurePermission() async -> Bool {
        switch permissionStatus {
        case .authorized:
            return true
        case .denied, .restricted:
            lastErrorMessage = "camera access is off — allow The Lyceum under System Settings → Privacy & Security → Camera"
            return false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                lastErrorMessage = "camera access declined — presence analysis is off"
            }
            return granted
        @unknown default:
            lastErrorMessage = "camera access is unavailable on this Mac"
            return false
        }
    }

    // MARK: - Run control

    /// Starts capturing. Returns false with a reason the UI can show rather than
    /// failing later, because a silent camera is indistinguishable from a broken one.
    func startRun() async -> Bool {
        stopCapture()
        frames.removeAll()
        currentRunStartedAt = nil

        guard await ensurePermission() else { return false }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video) else {
            lastErrorMessage = "no camera found on this Mac — presence analysis is off"
            return false
        }

        let built = AVCaptureSession()
        built.beginConfiguration()
        built.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if built.canAdd(input) { built.addInput(input) }

            let output = AVCapturePhotoOutput()
            if built.canAdd(output) { built.addOutput(output) }
            built.commitConfiguration()

            guard !built.inputs.isEmpty, !built.outputs.isEmpty else {
                lastErrorMessage = "the camera could not be opened — presence analysis is off"
                return false
            }

            session = built
            photoOutput = output
            currentRunStartedAt = Date()
            lastErrorMessage = nil

            // startRunning() blocks for a moment on some devices, so it goes off the
            // main actor the same way the slide watcher does its setup.
            await Task.detached(priority: .userInitiated) { built.startRunning() }.value

            startCaptureLoop()
            return true
        } catch {
            lastErrorMessage = "camera unavailable: \(error.localizedDescription)"
            return false
        }
    }

    func stopRun() {
        stopCapture()
        currentRunStartedAt = nil
    }

    /// Hands the review its stills and keeps nothing afterwards.
    func takeFramesForReview() -> [LyceumPresenceFrame] {
        stopCapture()
        let picked = Self.selectFramesForReview(from: frames, maximum: Self.maximumFramesSentForReview)
        frames.removeAll()
        currentRunStartedAt = nil
        return picked
    }

    func discardFrames() {
        frames.removeAll()
        currentRunStartedAt = nil
        stopCapture()
    }

    private func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        retainedTokens.removeAll()

        guard let session else { return }
        self.session = nil
        photoOutput = nil
        if session.isRunning {
            Task.detached(priority: .userInitiated) { session.stopRunning() }
        }
    }

    private func startCaptureLoop() {
        captureTask?.cancel()
        let interval = max(Self.minimumIntervalSeconds, min(Self.maximumIntervalSeconds, intervalSeconds))

        captureTask = Task { [weak self] in
            // The first still is deliberately late: the opening seconds of a talk are
            // standing up, shuffling papers and finding the clicker.
            try? await Task.sleep(nanoseconds: UInt64(interval * 2 * 1_000_000_000))
            while !Task.isCancelled {
                self?.captureOneFrame()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func captureOneFrame() {
        guard let session, session.isRunning, let photoOutput, let startedAt = currentRunStartedAt else { return }

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPriority = .balanced

        let token = LyceumPhotoCaptureToken(camera: self, startedAt: startedAt)
        retainedTokens.append(token)
        photoOutput.capturePhoto(with: settings, delegate: token)
    }

    fileprivate func finish(_ token: LyceumPhotoCaptureToken) {
        retainedTokens.removeAll { $0 === token }
    }

    fileprivate func accept(jpegData: Data, width: Int, height: Int, startedAt: Date) {
        guard startedAt == currentRunStartedAt else { return }

        frames.append(LyceumPresenceFrame(
            secondsIntoRun: Date().timeIntervalSince(startedAt),
            imageData: jpegData,
            widthInPixels: width,
            heightInPixels: height
        ))
        thinFramesIfNeeded()
    }

    fileprivate func accept(failure message: String) {
        lastErrorMessage = message
    }

    /// Keep the spread, drop the middle: the story of a run is how the presenter
    /// opened, where they went, and how they stood at the end.
    private func thinFramesIfNeeded() {
        frames = Self.selectFramesForReview(from: frames, maximum: Self.hardMemoryCap)
    }

    static func selectFramesForReview(from frames: [LyceumPresenceFrame], maximum: Int) -> [LyceumPresenceFrame] {
        guard maximum > 1 else {
            if maximum == 1, let last = frames.last { return [last] }
            return []
        }
        guard frames.count > maximum else { return frames }

        let stride = Double(frames.count - 1) / Double(maximum - 1)
        var picked: [LyceumPresenceFrame] = []
        for index in 0..<maximum {
            let position = min(frames.count - 1, max(0, Int((Double(index) * stride).rounded())))
            if picked.last?.secondsIntoRun != frames[position].secondsIntoRun {
                picked.append(frames[position])
            }
        }
        return picked
    }
}

/// Owns the AVFoundation delegate callbacks so the camera itself does not have to
/// inherit from NSObject, and carries the run start time into the finished frame so
/// a still from a previous run can never be graded as part of this one.
final class LyceumPhotoCaptureToken: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var camera: LyceumPresenceCamera?
    private let startedAt: Date

    init(camera: LyceumPresenceCamera, startedAt: Date) {
        self.camera = camera
        self.startedAt = startedAt
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            let message = "frame capture failed: \(error.localizedDescription)"
            Task { @MainActor in
                self.camera?.accept(failure: message)
                self.camera?.finish(self)
            }
            return
        }

        guard let raw = photo.fileDataRepresentation() else {
            Task { @MainActor in self.camera?.finish(self) }
            return
        }

        Task { @MainActor in
            defer { self.camera?.finish(self) }
            guard let camera = self.camera, let downscaled = LyceumPresenceCameraSupport.downscale(raw) else { return }
            camera.accept(
                jpegData: downscaled.data,
                width: downscaled.width,
                height: downscaled.height,
                startedAt: self.startedAt
            )
        }
    }
}

enum LyceumPresenceCameraSupport {
    /// Small on purpose. The question is "were they facing the room", and 512 pixels
    /// answers it. Full resolution only costs the user money and bandwidth.
    static func downscale(_ jpegData: Data) -> (data: Data, width: Int, height: Int)? {
        guard let image = NSImage(data: jpegData) else { return nil }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let maximumEdge: CGFloat = 512
        let scale = min(1, maximumEdge / max(size.width, size.height))
        let targetSize = NSSize(width: max(1, (size.width * scale).rounded()),
                                height: max(1, (size.height * scale).rounded()))

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [
                  NSBitmapImageRep.PropertyKey.compressionFactor: 0.55
              ]) else {
            return nil
        }
        return (data, Int(targetSize.width), Int(targetSize.height))
    }
}

// MARK: - What the model is asked to do with the frames

enum LyceumPresencePrompts {
    /// Attached to the grading prompt only when frames were actually captured, so a
    /// run without a camera can never get an invented body-language paragraph.
    static let rules = """
    some of the images are stills from the presenter's own front camera, labelled "presenter at m:ss".
    use them, but stay inside what a still can show:
    - facing: turned towards the room, or reading the slide instead of the people
    - hands: visible and used, hidden, in pockets, gripping the clicker the whole time
    - posture: settled or shifting weight, leaning, stiff shoulders
    - eye contact and face: looking up at the room at the key sentence, eyes on notes, a flat expression while the content is exciting
    - change over the run: compare the stills to each other — did anything change, or is it one pose from beginning to end
    never do these: do not name emotions, do not comment on appearance, clothing, attractiveness, age, gender, weight or voice quality, do not diagnose anything, do not invent a moment that no still shows. if the frames are dark, cropped or show nobody, write "presence: could not see the presenter" and stop.
    keep each field to one sentence a student could act on in the next rehearsal, in the language the user spoke.
    """

    static func frameCountLine(_ count: Int) -> String {
        "\(count) presenter stills are attached, spread across the run."
    }
}
