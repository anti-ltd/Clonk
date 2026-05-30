// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Captures the hidden 1080×1920 window via SCStream and writes H.264/AAC MP4.
// NOT @MainActor — see ReelScene.swift header for the macOS 26.5 rationale.
// AVAssetWriter access is serialized via a lock; NSWindow ops use
// `await MainActor.run` (which uses the async executor path, not the broken
// sync executor check).

#if CLONK_SHOWCASE

import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

// Minimal surface the recorder needs from a showcase director, so one recorder
// can capture any showcase scene (the reel, the sound check, future ones).
protocol ReelDirecting: AnyObject {
    var cycleLength: Double { get }
    func start()
}

extension ReelDirector: ReelDirecting {}

final class ReelRecorder: @unchecked Sendable {
    private let director: any ReelDirecting
    private let makeRootView: @MainActor () -> AnyView
    private let lock = NSLock()                  // guards writer / inputs
    private var captureWindow: NSWindow?
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let sink = StreamSink()
    private var autoStopTask: Task<Void, Never>?
    private let sinkQueue = DispatchQueue(label: "ltd.anti.clonk.reel.sink", qos: .userInitiated)
    private var sessionStarted = false   // protected by lock

    init(director: any ReelDirecting,
         makeRootView: @escaping @MainActor () -> AnyView) {
        self.director = director
        self.makeRootView = makeRootView
    }

    func start() async {
        // 1. NSWindow must be created on main thread. Capture both the
        // window and its windowNumber inside MainActor.run (windowNumber
        // is main-actor isolated).
        let (win, windowNumber) = await MainActor.run { () -> (NSWindow, Int) in
            let w = self.makeCaptureWindow()
            return (w, w.windowNumber)
        }
        captureWindow = win

        // 2. Locate the matching SCWindow.
        guard let content = try? await SCShareableContent.current,
              let scWin = content.windows.first(where: { $0.windowID == windowNumber })
        else {
            await MainActor.run { win.close() }
            return
        }

        // 3. Output URL on Desktop.
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Clonk-Reel-\(fmt.string(from: .now)).mp4")

        // 4. AVAssetWriter setup.
        guard let assetWriter = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            await MainActor.run { win.close() }
            return
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080, AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 15_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 60,
            ],
        ]
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 192_000,
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = true
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aIn.expectsMediaDataInRealTime = true
        assetWriter.add(vIn); assetWriter.add(aIn)

        installWriter(assetWriter, video: vIn, audio: aIn)

        // 5. SCStream — sink runs on our dedicated queue and calls append()
        //    directly, no Swift Concurrency hop.
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let config = SCStreamConfiguration()
        config.width = 1080; config.height = 1920
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true
        config.showsCursor = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 44_100
        config.channelCount = 2

        sink.onSample = { [weak self] buf in
            self?.append(buf)
        }
        let st = SCStream(filter: filter, configuration: config, delegate: nil)
        try? st.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sinkQueue)
        try? st.addStreamOutput(sink, type: .audio,  sampleHandlerQueue: sinkQueue)
        assetWriter.startWriting()
        // Bring capture up FIRST so the SCStream pipeline is emitting frames
        // before the director's t=0 events fire — otherwise the first ~0.3–
        // 0.8 s of the "clonk" typewriter gets eaten by SCStream warm-up.
        try? await st.startCapture()
        stream = st
        await MainActor.run { self.director.start() }

        // 6. Auto-stop after one full cycle + 1.0 s buffer so the bumper's
        //    final frames and audio fade are guaranteed to land in the MP4.
        let duration = director.cycleLength + 1.0
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await self?.stop()
        }
    }

    func stop() async {
        autoStopTask?.cancel(); autoStopTask = nil
        if let st = stream { try? await st.stopCapture() }
        stream = nil

        // Drain any frames still queued in the sink before marking inputs finished.
        // stopCapture() returns before all queued sinkQueue blocks execute.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sinkQueue.async { cont.resume() }
        }

        let w = finalizeWriter()
        if let w {
            await w.finishWriting()
            NSWorkspace.shared.activateFileViewerSelecting([w.outputURL])
        }

        if let win = captureWindow {
            await MainActor.run { win.close() }
            captureWindow = nil
        }
    }

    // NSLock can't be touched directly from async contexts in Swift 6, so
    // both writer mutations go through these sync helpers.
    private func installWriter(_ w: AVAssetWriter, video: AVAssetWriterInput, audio: AVAssetWriterInput) {
        lock.lock()
        defer { lock.unlock() }
        writer = w; videoInput = video; audioInput = audio
        sessionStarted = false
    }

    private func finalizeWriter() -> AVAssetWriter? {
        lock.lock()
        defer { lock.unlock() }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let w = writer
        writer = nil; videoInput = nil; audioInput = nil
        return w
    }

    // Fire-and-forget cancel from the UI button.
    func stopSync() {
        Task { await self.stop() }
    }

    private func append(_ buf: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, CMSampleBufferDataIsReady(buf) else { return }

        let isAudio = CMSampleBufferGetFormatDescription(buf).map {
            CMFormatDescriptionGetMediaType($0) == kCMMediaType_Audio
        } ?? false

        guard writer.status == .writing else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buf))
            sessionStarted = true
        }

        if isAudio {
            if audioInput?.isReadyForMoreMediaData == true { audioInput?.append(buf) }
        } else {
            guard CMSampleBufferGetImageBuffer(buf) != nil else { return }
            if videoInput?.isReadyForMoreMediaData == true { videoInput?.append(buf) }
        }
    }

    // The hidden 1080×1920 NSWindow that hosts the bound scene for capture.
    @MainActor
    private func makeCaptureWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 50_000, y: 0, width: 1080, height: 1920),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        win.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black

        let host = NSHostingView(
            rootView: makeRootView()
                .frame(width: 360, height: 640)
                .scaleEffect(3.0, anchor: .topLeading)
                .frame(width: 1080, height: 1920, alignment: .topLeading)
        )
        win.contentView = host
        win.orderFrontRegardless()
        return win
    }
}

// SCStream delivers samples on our `sinkQueue`. The shim just forwards
// to the recorder; the recorder takes a lock to serialize writer access.
private final class StreamSink: NSObject, SCStreamOutput, @unchecked Sendable {
    var onSample: ((CMSampleBuffer) -> Void)?
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if type == .screen, CMSampleBufferGetImageBuffer(sampleBuffer) == nil { return }
        onSample?(sampleBuffer)
    }
}

#endif
