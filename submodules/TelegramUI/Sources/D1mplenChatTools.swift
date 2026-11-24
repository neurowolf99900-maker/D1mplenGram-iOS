import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import UndoUI
import PromptUI
import SaveToCameraRoll
import LocalMediaResources
import SGSettingsUI
import SGSimpleSettings

// MARK: - Floating Button View

final class D1mplenChatButtonView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let iconView = UIImageView()
    private let activeDot = UIView()
    private let button = UIButton(type: .custom)
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = false
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.22
        self.layer.shadowRadius = 6.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)

        self.blurView.clipsToBounds = true
        self.blurView.layer.borderWidth = 0.6
        self.blurView.isUserInteractionEnabled = false
        self.addSubview(self.blurView)

        self.iconView.contentMode = .scaleAspectFit
        self.iconView.image = UIImage(systemName: "bolt.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17.0, weight: .semibold))
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)

        self.activeDot.backgroundColor = UIColor(red: 0.2, green: 0.84, blue: 0.48, alpha: 1.0)
        self.activeDot.layer.borderColor = UIColor.white.cgColor
        self.activeDot.layer.borderWidth = 1.5
        self.activeDot.isHidden = true
        self.activeDot.isUserInteractionEnabled = false
        self.addSubview(self.activeDot)

        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
        self.addSubview(self.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func buttonPressed() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.transform = .identity
            }
        })
        self.onTap?()
    }

    func update(theme: PresentationTheme, active: Bool) {
        self.blurView.effect = UIBlurEffect(style: theme.overallDarkAppearance ? .systemThinMaterialDark : .systemThinMaterialLight)
        self.blurView.layer.borderColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.14).cgColor
        self.iconView.tintColor = active ? UIColor(red: 1.0, green: 0.72, blue: 0.16, alpha: 1.0) : theme.list.itemAccentColor
        self.activeDot.isHidden = !active
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(self.bounds.width, self.bounds.height)
        self.blurView.frame = self.bounds
        self.blurView.layer.cornerRadius = side / 2.0
        self.button.frame = self.bounds
        self.iconView.frame = self.bounds.insetBy(dx: 10.0, dy: 10.0)
        let dotSize: CGFloat = 10.0
        self.activeDot.frame = CGRect(x: self.bounds.width - dotSize - 2.0, y: 2.0, width: dotSize, height: dotSize)
        self.activeDot.layer.cornerRadius = dotSize / 2.0
    }
}

// MARK: - Runtime Manager

final class D1mplenChatToolsManager {
    static let shared = D1mplenChatToolsManager()

    private struct FakeStatusState {
        var timer: SwiftSignalKit.Timer
        var endTime: Double
        var kind: D1mplenFakeActivityKind
    }

    private struct MassReactionState {
        var timer: SwiftSignalKit.Timer
        var ids: [EngineMessage.Id]
        var index: Int
        var emoji: String
        var context: AccountContext
        var peerId: EnginePeer.Id
        var onDone: ((Int) -> Void)?
    }

    private var fakeStatuses: [EnginePeer.Id: FakeStatusState] = [:]
    private var massReactions: [EnginePeer.Id: MassReactionState] = [:]

    private init() {}

    func hasActiveTask(for peerId: EnginePeer.Id) -> Bool {
        return self.fakeStatuses[peerId] != nil || self.massReactions[peerId] != nil
    }

    func isFakeStatusActive(for peerId: EnginePeer.Id) -> Bool {
        return self.fakeStatuses[peerId] != nil
    }

    func isMassReactionActive(for peerId: EnginePeer.Id) -> Bool {
        return self.massReactions[peerId] != nil
    }

    func startFakeStatus(
        context: AccountContext,
        peerId: EnginePeer.Id,
        threadId: Int64?,
        kind: D1mplenFakeActivityKind,
        durationSeconds: Int,
        onFinish: @escaping () -> Void
    ) {
        self.stopFakeStatus(context: context, peerId: peerId, threadId: threadId, sendCancel: false)
        let clamped = max(2, min(1800, durationSeconds))
        let endTime = CFAbsoluteTimeGetCurrent() + Double(clamped)
        let _ = d1mplenSendFakeActivity(account: context.account, peerId: peerId, threadId: threadId, kind: kind).startStandalone()

        let timer = SwiftSignalKit.Timer(timeout: 4.0, repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            if CFAbsoluteTimeGetCurrent() >= endTime {
                self.stopFakeStatus(context: context, peerId: peerId, threadId: threadId, sendCancel: true)
                onFinish()
                return
            }
            let _ = d1mplenSendFakeActivity(account: context.account, peerId: peerId, threadId: threadId, kind: kind).startStandalone()
        }, queue: Queue.mainQueue())

        self.fakeStatuses[peerId] = FakeStatusState(timer: timer, endTime: endTime, kind: kind)
        timer.start()
    }

    func stopFakeStatus(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, sendCancel: Bool = true) {
        if let existing = self.fakeStatuses.removeValue(forKey: peerId) {
            existing.timer.invalidate()
        }
        if sendCancel {
            let _ = d1mplenSendFakeActivity(account: context.account, peerId: peerId, threadId: threadId, kind: .cancel).startStandalone()
        }
    }

    func startMassReactions(
        context: AccountContext,
        peerId: EnginePeer.Id,
        filter: D1mplenRecentMessageFilter,
        limit: Int,
        emoji: String,
        onStarted: @escaping (Int) -> Void,
        onDone: @escaping (Int) -> Void
    ) {
        self.stopMassReactions(for: peerId)
        let clamped = max(1, min(200, limit))
        let _ = (d1mplenRecentMessageIds(account: context.account, peerId: peerId, filter: filter, limit: clamped)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] ids in
            guard let self else {
                return
            }
            guard !ids.isEmpty else {
                onDone(0)
                return
            }
            onStarted(ids.count)
            self.runReactionStep(context: context, peerId: peerId, ids: ids, emoji: emoji, onDone: onDone)
        })
    }

    private func runReactionStep(
        context: AccountContext,
        peerId: EnginePeer.Id,
        ids: [EngineMessage.Id],
        emoji: String,
        onDone: @escaping (Int) -> Void
    ) {
        let timer = SwiftSignalKit.Timer(timeout: 0.45, repeat: true, completion: { [weak self] in
            guard let self, var state = self.massReactions[peerId] else {
                return
            }
            if state.index >= state.ids.count {
                let count = state.ids.count
                state.timer.invalidate()
                self.massReactions.removeValue(forKey: peerId)
                state.onDone?(count)
                return
            }
            let messageId = state.ids[state.index]
            state.index += 1
            self.massReactions[peerId] = state
            let _ = updateMessageReactionsInteractively(
                account: state.context.account,
                messageIds: [messageId],
                reactions: [.builtin(state.emoji)],
                isLarge: false,
                storeAsRecentlyUsed: false,
                add: true
            ).startStandalone()
        }, queue: Queue.mainQueue())

        let initialState = MassReactionState(
            timer: timer,
            ids: ids,
            index: 1,
            emoji: emoji,
            context: context,
            peerId: peerId,
            onDone: onDone
        )
        self.massReactions[peerId] = initialState
        let _ = updateMessageReactionsInteractively(
            account: context.account,
            messageIds: [ids[0]],
            reactions: [.builtin(emoji)],
            isLarge: false,
            storeAsRecentlyUsed: false,
            add: true
        ).startStandalone()
        timer.start()
    }

    func stopMassReactions(for peerId: EnginePeer.Id) {
        if let state = self.massReactions.removeValue(forKey: peerId) {
            state.timer.invalidate()
        }
    }

    func sendAnimatedMessage(
        context: AccountContext,
        peerId: EnginePeer.Id,
        threadId: Int64?,
        silent: Bool,
        frames: [String],
        interval: Double = 0.65,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        let cleaned = frames.map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
        guard let firstFrame = cleaned.first else {
            onComplete?(false)
            return
        }
        var attributes: [EngineMessage.Attribute] = []
        if silent {
            attributes.append(NotificationInfoMessageAttribute(flags: .muted))
        }
        let message: EnqueueMessage = .message(
            text: firstFrame,
            attributes: attributes,
            inlineStickers: [:],
            mediaReference: nil,
            threadId: threadId,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
        let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: [message])
        |> mapToSignal { localIds -> Signal<EngineMessage.Id?, NoError> in
            guard let localId = localIds.first ?? nil else {
                return .single(nil)
            }
            return d1mplenWaitForCloudMessageId(
                account: context.account,
                peerId: peerId,
                localId: localId,
                matchText: firstFrame,
                timeout: 25.0
            )
        }
        |> deliverOnMainQueue).startStandalone(next: { cloudId in
            guard let cloudId else {
                onComplete?(false)
                return
            }
            let remaining = Array(cleaned.dropFirst())
            guard !remaining.isEmpty else {
                onComplete?(true)
                return
            }
            func applyFrame(at idx: Int) {
                guard idx < remaining.count else {
                    onComplete?(true)
                    return
                }
                let text = remaining[idx]
                let _ = (context.engine.messages.requestEditMessage(
                    messageId: cloudId,
                    text: text,
                    media: .keep,
                    entities: nil,
                    richText: nil,
                    inlineStickers: [:],
                    webpagePreviewAttribute: nil,
                    invertMediaAttribute: nil,
                    disableUrlPreview: false,
                    scheduleInfoAttribute: nil
                )
                |> `catch` { _ -> Signal<RequestEditMessageResult, NoError> in
                    return .complete()
                }
                |> deliverOnMainQueue).startStandalone(next: { _ in }, completed: {
                    Queue.mainQueue().after(interval) {
                        applyFrame(at: idx + 1)
                    }
                })
            }
            Queue.mainQueue().after(interval) {
                applyFrame(at: 0)
            }
        })
    }

    func sendSelfDestructMessage(
        context: AccountContext,
        peerId: EnginePeer.Id,
        threadId: Int64?,
        silent: Bool,
        text: String,
        seconds: Int,
        onScheduled: ((Bool) -> Void)? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onScheduled?(false)
            return
        }
        let delaySeconds = Double(max(1, min(86400, seconds)))
        var attributes: [EngineMessage.Attribute] = []
        if silent {
            attributes.append(NotificationInfoMessageAttribute(flags: .muted))
        }
        let message: EnqueueMessage = .message(
            text: trimmed,
            attributes: attributes,
            inlineStickers: [:],
            mediaReference: nil,
            threadId: threadId,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
        let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: [message])
        |> mapToSignal { localIds -> Signal<EngineMessage.Id?, NoError> in
            guard let localId = localIds.first ?? nil else {
                return .single(nil)
            }
            return d1mplenWaitForCloudMessageId(
                account: context.account,
                peerId: peerId,
                localId: localId,
                matchText: trimmed,
                timeout: 25.0
            )
        }
        |> deliverOnMainQueue).startStandalone(next: { cloudId in
            guard let cloudId else {
                onScheduled?(false)
                return
            }
            onScheduled?(true)
            Queue.mainQueue().after(delaySeconds) {
                let _ = context.engine.messages.deleteMessagesInteractively(messageIds: [cloudId], type: .forEveryone).startStandalone()
            }
        })
    }

    func cleanMyRecentMessages(
        context: AccountContext,
        peerId: EnginePeer.Id,
        count: Int,
        completion: @escaping (Int) -> Void
    ) {
        let clamped = max(1, min(100, count))
        let _ = (d1mplenRecentMessageIds(account: context.account, peerId: peerId, filter: .outgoing, limit: clamped)
        |> mapToSignal { ids -> Signal<Int, NoError> in
            guard !ids.isEmpty else {
                return .single(0)
            }
            return context.engine.messages.deleteMessagesInteractively(messageIds: ids, type: .forEveryone)
            |> map { _ -> Int in ids.count }
            |> then(.single(ids.count))
            |> take(1)
        }
        |> deliverOnMainQueue).startStandalone(next: { deleted in
            completion(deleted)
        })
    }

    // MARK: - Frame Builders & Text Stylers

    static func typewriterFrames(for finalText: String) -> [String] {
        let words = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard words.count > 1 else {
            return [finalText]
        }
        let maxSteps = 12
        let groupSize = max(1, Int(ceil(Double(words.count) / Double(maxSteps))))
        var frames: [String] = []
        var idx = groupSize
        while idx < words.count {
            frames.append(words.prefix(idx).joined(separator: " ") + " ▌")
            idx += groupSize
        }
        frames.append(finalText)
        return frames
    }

    static func loadingFrames(for finalText: String) -> [String] {
        return [
            "⏳ Загрузка… [░░░░░] 15%",
            "⏳ Загрузка… [██░░░] 45%",
            "⏳ Загрузка… [████░] 80%",
            "✅ Готово 100%\n\n\(finalText)"
        ]
    }

    static func heartFrames(for finalText: String) -> [String] {
        return [
            "🤍 ...",
            "❤️ ...",
            "💓 ...",
            "💘 \(finalText)"
        ]
    }

    static func hackFrames(for finalText: String) -> [String] {
        return [
            "💻 Подключение к узлу…",
            "🔐 Подбор ключа… 64%",
            "🔓 Доступ получен!",
            finalText
        ]
    }

    static func alternatingCase(_ text: String) -> String {
        var upper = true
        var result = ""
        for ch in text {
            if ch.isLetter {
                result.append(upper ? ch.uppercased() : ch.lowercased())
                upper.toggle()
            } else {
                result.append(ch)
            }
        }
        return result
    }

    static func spacedText(_ text: String) -> String {
        return text.map { String($0) }.joined(separator: " ")
    }

    static func wordSpoilerEntities(for text: String) -> [MessageTextEntity] {
        var entities: [MessageTextEntity] = []
        var currentStart: String.Index?
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            let isWs = ch.isWhitespace || ch.isNewline
            if !isWs && currentStart == nil {
                currentStart = idx
            } else if isWs, let start = currentStart {
                let nsRange = NSRange(start ..< idx, in: text)
                if nsRange.length > 0 {
                    entities.append(MessageTextEntity(range: nsRange.location ..< (nsRange.location + nsRange.length), type: .Spoiler))
                }
                currentStart = nil
            }
            idx = text.index(after: idx)
        }
        if let start = currentStart {
            let nsRange = NSRange(start ..< text.endIndex, in: text)
            if nsRange.length > 0 {
                entities.append(MessageTextEntity(range: nsRange.location ..< (nsRange.location + nsRange.length), type: .Spoiler))
            }
        }
        return entities
    }

    static func parseDurationSeconds(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasSuffix("m") || trimmed.hasSuffix("м") || trimmed.hasSuffix("мин") {
            let digits = trimmed.prefix(while: { $0.isNumber })
            if let mins = Int(digits), mins > 0 {
                return mins * 60
            }
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        return Int(digits)
    }
}

// MARK: - Chat Video -> Round Video Exporter

func d1mplenConvertMessageVideoToRound(
    context: AccountContext,
    message: EngineMessage,
    file: TelegramMediaFile,
    targetPeerId: EnginePeer.Id,
    targetThreadId: Int64?,
    silentPosting: Bool,
    presentOverlay: @escaping (ViewController) -> Void,
    pushController: @escaping (ViewController) -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    presentOverlay(
        UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Подготовка видео для кружочка…", timeout: 2.0, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        )
    )

    let mediaRef = FileMediaReference.message(message: MessageReference(message._asMessage()), media: file).abstract
    let _ = (fetchMediaData(context: context, userLocation: .peer(message.id.peerId), mediaReference: mediaRef)
    |> mapToSignal { state, _ -> Signal<String, NoError> in
        if case let .data(data) = state, data.isComplete {
            return .single(data.path)
        }
        return .complete()
    }
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { path in
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let sourceCopyURL = tempDir.appendingPathComponent("d1mplen-src-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: sourceCopyURL)
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: sourceCopyURL)
        } catch {
            presentOverlay(
                UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(title: nil, text: "Не удалось прочитать видеофайл", timeout: 2.5, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                )
            )
            return
        }

        let editor = ayuGramRoundVideoEditorController(context: context, videoURL: sourceCopyURL, completion: { selection in
            d1mplenExportAndSendRoundVideo(
                context: context,
                selection: selection,
                tempSourceURL: sourceCopyURL,
                targetPeerId: targetPeerId,
                targetThreadId: targetThreadId,
                silentPosting: silentPosting,
                presentOverlay: presentOverlay
            )
        })
        pushController(editor)
    })
}

private func d1mplenExportAndSendRoundVideo(
    context: AccountContext,
    selection: AyuGramRoundVideoURLSelection,
    tempSourceURL: URL,
    targetPeerId: EnginePeer.Id,
    targetThreadId: Int64?,
    silentPosting: Bool,
    presentOverlay: @escaping (ViewController) -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    presentOverlay(
        UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Кодирование кружочка 384×384…", timeout: 3.0, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        )
    )

    let asset = AVURLAsset(url: selection.videoURL)
    asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            try? FileManager.default.removeItem(at: tempSourceURL)
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            try? FileManager.default.removeItem(at: tempSourceURL)
            return
        }

        let totalDuration = max(0.5, asset.duration.seconds)
        let startSec = max(0.0, min(selection.start, max(0.0, totalDuration - 0.5)))
        let trimDuration = max(0.5, min(selection.duration, totalDuration - startSec))
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startSec, preferredTimescale: 600),
            duration: CMTime(seconds: trimDuration, preferredTimescale: 600)
        )

        do {
            try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            try? FileManager.default.removeItem(at: tempSourceURL)
            return
        }

        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let naturalRect = CGRect(origin: .zero, size: videoTrack.naturalSize)
        let transformedRect = naturalRect.applying(videoTrack.preferredTransform)
        let renderSide: CGFloat = 384.0
        let cropSide = max(1.0, min(selection.cropRect.width, selection.cropRect.height))
        let scale = renderSide / cropSide

        var transform = videoTrack.preferredTransform
        transform = transform.concatenating(CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y))
        transform = transform.concatenating(CGAffineTransform(translationX: -selection.cropRect.origin.x, y: -selection.cropRect.origin.y))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: trimDuration, preferredTimescale: 600))
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = CGSize(width: renderSide, height: renderSide)

        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("d1mplen-round-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: exportURL)

        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            ?? AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality)
        guard let exportSession else {
            try? FileManager.default.removeItem(at: tempSourceURL)
            return
        }
        exportSession.outputURL = exportURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            try? FileManager.default.removeItem(at: tempSourceURL)
            DispatchQueue.main.async {
                guard exportSession.status == .completed else {
                    try? FileManager.default.removeItem(at: exportURL)
                    presentOverlay(
                        UndoOverlayController(
                            presentationData: presentationData,
                            content: .info(title: nil, text: "Ошибка конвертации в кружочек", timeout: 2.5, customUndoText: nil),
                            elevatedLayout: false,
                            action: { _ in return false }
                        )
                    )
                    return
                }

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: exportURL.path)[.size] as? NSNumber)?.int64Value
                let videoResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                context.engine.resources.moveResourceData(id: EngineMediaResource.Id(videoResource.id), fromTempPath: exportURL.path)

                var previewRepresentations: [TelegramMediaImageRepresentation] = []
                if let thumbnail = selection.thumbnail {
                    let thumbnailSize = CGSize(width: 320.0, height: 320.0)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    let scaled = UIGraphicsImageRenderer(size: thumbnailSize, format: format).image { _ in
                        thumbnail.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    }
                    if let data = scaled.jpegData(compressionQuality: 0.5) {
                        let thumbResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbResource.id), data: data)
                        previewRepresentations.append(TelegramMediaImageRepresentation(
                            dimensions: PixelDimensions(thumbnailSize),
                            resource: thumbResource,
                            progressiveSizes: [],
                            immediateThumbnailData: nil,
                            hasVideo: false,
                            isPersonal: false
                        ))
                    }
                }

                let media = TelegramMediaFile(
                    fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)),
                    partialReference: nil,
                    resource: videoResource,
                    previewRepresentations: previewRepresentations,
                    videoThumbnails: [],
                    immediateThumbnailData: nil,
                    mimeType: "video/mp4",
                    size: fileSize,
                    attributes: [
                        .FileName(fileName: "round.mp4"),
                        .Video(
                            duration: trimDuration,
                            size: PixelDimensions(width: Int32(renderSide), height: Int32(renderSide)),
                            flags: [.instantRoundVideo],
                            preloadSize: nil,
                            coverTime: nil,
                            videoCodec: nil
                        )
                    ],
                    alternativeRepresentations: []
                )

                var attributes: [EngineMessage.Attribute] = []
                if silentPosting {
                    attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                }
                let roundMsg: EnqueueMessage = .message(
                    text: "",
                    attributes: attributes,
                    inlineStickers: [:],
                    mediaReference: .standalone(media: media),
                    threadId: targetThreadId,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
                let _ = enqueueMessages(account: context.account, peerId: targetPeerId, messages: [roundMsg]).startStandalone()
            }
        }
    }
}

// MARK: - ChatControllerImpl Hub & Commands

extension ChatControllerImpl {
    func d1mplenShowToast(_ text: String, isSuccess: Bool = true) {
        self.chatDisplayNode.d1mplenRefreshButton()
        let data = self.presentationData
        let content: UndoOverlayContent = isSuccess
            ? .succeed(text: text, timeout: 2.5, customUndoText: nil)
            : .info(title: nil, text: text, timeout: 2.5, customUndoText: nil)
        self.present(
            UndoOverlayController(presentationData: data, content: content, elevatedLayout: false, action: { _ in return false }),
            in: .current
        )
    }

    func d1mplenPresentChatTools() {
        guard case let .peer(peerId) = self.chatLocation else {
            return
        }
        let extra = AyuGramSettings.shared.extra
        let data = self.presentationData
        let rawPeerId = peerId.toInt64()
        let rawPeer = self.presentationInterfaceState.renderedPeer?.peer
        let enginePeer = rawPeer.map(EnginePeer.init)
        let isUserPeer = (rawPeer as? TelegramUser)?.botInfo == nil && (rawPeer is TelegramUser) && peerId != self.context.account.peerId
        let displayName = enginePeer?.debugDisplayTitle ?? "Контакт"
        let username = enginePeer?.addressName
        let threadId = self.chatLocation.threadId
        let silent = self.presentationInterfaceState.interfaceState.silentPosting
        let manager = D1mplenChatToolsManager.shared

        let sheet = ActionSheetController(presentationData: data)
        var mainItems: [ActionSheetItem] = []

        if isUserPeer {
            let isTracked = D1mplenTrackerStore.shared.isTracked(rawPeerId)
            if isTracked {
                mainItems.append(ActionSheetButtonItem(title: "📡 В мониторинге · Статистика", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentTrackingOptions(peerId: peerId, displayName: displayName, username: username)
                }))
            } else {
                mainItems.append(ActionSheetButtonItem(title: "📡 В мониторинг (отслеживать чат)", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    guard let self else { return }
                    D1mplenTrackerStore.shared.addOrUpdateContact(peerId: rawPeerId, displayName: displayName, username: username)
                    self.d1mplenShowToast("Контакт добавлен в радар D1mplenGram")
                    self.chatDisplayNode.d1mplenRefreshButton()
                }))
            }
        }

        if extra.d1mplenFakeStatusEnabled {
            if manager.isFakeStatusActive(for: peerId) {
                mainItems.append(ActionSheetButtonItem(title: "⏹ Остановить фейк-статус", color: .destructive, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    guard let self else { return }
                    manager.stopFakeStatus(context: self.context, peerId: peerId, threadId: threadId)
                    self.d1mplenShowToast("Фейк-статус остановлен")
                }))
            } else {
                mainItems.append(ActionSheetButtonItem(title: "🎭 Фейк-статус (печатает / кружок / ГС)", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentFakeStatusPicker(peerId: peerId, threadId: threadId)
                }))
            }
        }

        if extra.d1mplenMassReactionsEnabled {
            if manager.isMassReactionActive(for: peerId) {
                mainItems.append(ActionSheetButtonItem(title: "⏹ Остановить масс-реакции", color: .destructive, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    guard let self else { return }
                    manager.stopMassReactions(for: peerId)
                    self.d1mplenShowToast("Масс-реакции остановлены")
                }))
            } else {
                mainItems.append(ActionSheetButtonItem(title: "❤️ Масс-реакции на N сообщений", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentMassReactionsFilter(peerId: peerId)
                }))
            }
        }

        if extra.d1mplenTextAnimEnabled {
            mainItems.append(ActionSheetButtonItem(title: "✨ Анимация отправки текста", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentAnimationPicker(peerId: peerId, threadId: threadId, silent: silent)
            }))
            mainItems.append(ActionSheetButtonItem(title: "🔤 Стилизация текста (ЛеСеНкА / Спойлер)", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentTextStyler(peerId: peerId, threadId: threadId, silent: silent)
            }))
        }

        if extra.d1mplenSendWhenOnlineEnabled && isUserPeer {
            let queuedCount = D1mplenTrackerStore.shared.queuedMessages(for: rawPeerId).count
            let queueSuffix = queuedCount > 0 ? " (\(queuedCount) в очереди)" : ""
            mainItems.append(ActionSheetButtonItem(title: "🕒 Отправить когда зайдёт в сеть\(queueSuffix)", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPromptSendWhenOnline(peerId: peerId, displayName: displayName, username: username, silent: silent)
            }))
        }

        if extra.d1mplenSelfDestructEnabled {
            mainItems.append(ActionSheetButtonItem(title: "💣 Самоудаляющееся сообщение", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentSelfDestructPicker(peerId: peerId, threadId: threadId, silent: silent)
            }))
        }

        if extra.d1mplenCleanMyMessagesEnabled {
            mainItems.append(ActionSheetButtonItem(title: "🧹 Очистить мои последние N", color: .destructive, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentCleanCountPicker(peerId: peerId)
            }))
        }

        let settingsGroup = ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: "⚙️ Настройки D1mplenGram", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                guard let self else { return }
                self.push(d1mplenGramSettingsScreen(context: self.context))
            })
        ])

        var groups: [ActionSheetItemGroup] = []
        if !mainItems.isEmpty {
            groups.append(ActionSheetItemGroup(items: mainItems))
        }
        groups.append(settingsGroup)
        groups.append(ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ]))
        sheet.setItemGroups(groups)
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentTrackingOptions(peerId: EnginePeer.Id, displayName: String, username: String?) {
        let data = self.presentationData
        let sheet = ActionSheetController(presentationData: data)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "📊 Открыть статистику", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    guard let self else { return }
                    D1mplenTrackerStore.shared.addOrUpdateContact(peerId: peerId.toInt64(), displayName: displayName, username: username)
                    self.push(d1mplenContactStatsScreen(context: self.context, peerId: peerId))
                }),
                ActionSheetButtonItem(title: "Убрать из мониторинга", color: .destructive, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    D1mplenTrackerStore.shared.removeContact(peerId.toInt64())
                    self?.d1mplenShowToast("Мониторинг отключён для этого чата")
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentFakeStatusPicker(peerId: EnginePeer.Id, threadId: Int64?) {
        let data = self.presentationData
        let choices: [(String, D1mplenFakeActivityKind)] = [
            ("✍️ Печатает текст", .typing),
            ("🎥 Записывает кружочек", .recordingRound),
            ("🎤 Записывает голосовое", .recordingVoice),
            ("🖼 Отправляет фото", .uploadingPhoto),
            ("📹 Отправляет видео", .uploadingVideo),
            ("🎮 Играет в игру", .playingGame),
            ("👾 Выбирает стикер", .choosingSticker)
        ]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Выберите скрытый фейк-статус (в чат ничего не отправится)")]
        for (title, kind) in choices {
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentFakeDurationPicker(peerId: peerId, threadId: threadId, kind: kind, label: title)
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentFakeDurationPicker(peerId: EnginePeer.Id, threadId: Int64?, kind: D1mplenFakeActivityKind, label: String) {
        let data = self.presentationData
        let presets: [(String, Int)] = [
            ("15 секунд", 15),
            ("30 секунд", 30),
            ("1 минута", 60),
            ("3 минуты", 180),
            ("5 минут", 300)
        ]
        let applyDuration: (Int) -> Void = { [weak self] seconds in
            guard let self else { return }
            D1mplenChatToolsManager.shared.startFakeStatus(
                context: self.context,
                peerId: peerId,
                threadId: threadId,
                kind: kind,
                durationSeconds: seconds,
                onFinish: { [weak self] in
                    self?.d1mplenShowToast("Фейк-статус завершён")
                }
            )
            self.d1mplenShowToast("\(label) · \(seconds)с")
        }

        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "\(label): длительность")]
        for (title, seconds) in presets {
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                applyDuration(seconds)
            }))
        }
        items.append(ActionSheetButtonItem(title: "⏱ Своё время…", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Введите длительность в секундах (например 45 или 2m):",
                value: "45",
                placeholder: "Секунды или 2m",
                characterLimit: 12,
                apply: { value in
                    guard let value, let parsed = D1mplenChatToolsManager.parseDurationSeconds(value), parsed > 0 else {
                        return
                    }
                    applyDuration(parsed)
                }
            )
            self.present(prompt, in: .window(.root))
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentMassReactionsFilter(peerId: EnginePeer.Id) {
        let data = self.presentationData
        let sheet = ActionSheetController(presentationData: data)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Кому ставить реакции?"),
                ActionSheetButtonItem(title: "Только собеседника", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentMassReactionsCount(peerId: peerId, filter: .incoming)
                }),
                ActionSheetButtonItem(title: "Только мои", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentMassReactionsCount(peerId: peerId, filter: .outgoing)
                }),
                ActionSheetButtonItem(title: "Все подряд", color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.d1mplenPresentMassReactionsCount(peerId: peerId, filter: .all)
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentMassReactionsCount(peerId: EnginePeer.Id, filter: D1mplenRecentMessageFilter) {
        let data = self.presentationData
        let counts = [5, 10, 20, 50, 100]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Сколько последних сообщений?")]
        for count in counts {
            items.append(ActionSheetButtonItem(title: "Последние \(count)", color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.d1mplenPresentMassReactionsEmoji(peerId: peerId, filter: filter, count: count)
            }))
        }
        items.append(ActionSheetButtonItem(title: "✏️ Своё количество…", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Введите число сообщений (1–200):",
                value: "25",
                placeholder: "Количество",
                characterLimit: 4,
                apply: { [weak self] value in
                    guard let self, let value, let num = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), num > 0 else {
                        return
                    }
                    self.d1mplenPresentMassReactionsEmoji(peerId: peerId, filter: filter, count: num)
                }
            )
            self.present(prompt, in: .window(.root))
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentMassReactionsEmoji(peerId: EnginePeer.Id, filter: D1mplenRecentMessageFilter, count: Int) {
        let data = self.presentationData
        let emojis = ["❤️", "👍", "🔥", "😂", "😍", "⚡", "🍓"]
        let run: (String) -> Void = { [weak self] emoji in
            guard let self else { return }
            D1mplenChatToolsManager.shared.startMassReactions(
                context: self.context,
                peerId: peerId,
                filter: filter,
                limit: count,
                emoji: emoji,
                onStarted: { [weak self] actual in
                    self?.d1mplenShowToast("Ставлю \(emoji) на \(actual) сообщ.…")
                },
                onDone: { [weak self] total in
                    self?.d1mplenShowToast(total > 0 ? "Готово: \(emoji) на \(total) сообщ." : "Подходящие сообщения не найдены")
                }
            )
        }

        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Выберите реакцию для \(count) сообщ.")]
        for emoji in emojis {
            items.append(ActionSheetButtonItem(title: "\(emoji)  Реакция \(emoji)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                run(emoji)
            }))
        }
        items.append(ActionSheetButtonItem(title: "✏️ Свой эмодзи…", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Введите один стандартный эмодзи для реакции:",
                value: "🔥",
                placeholder: "Эмодзи",
                characterLimit: 8,
                apply: { value in
                    guard let value else { return }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    run(trimmed)
                }
            )
            self.present(prompt, in: .window(.root))
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentAnimationPicker(peerId: EnginePeer.Id, threadId: Int64?, silent: Bool) {
        let data = self.presentationData
        let styles: [(title: String, builder: (String) -> [String])] = [
            ("⌨️ Печатная машинка (по словам)", D1mplenChatToolsManager.typewriterFrames(for:)),
            ("⏳ Загрузка 15% → 100% ✅", D1mplenChatToolsManager.loadingFrames(for:)),
            ("💓 Сердцебиение 🤍 → 💘", D1mplenChatToolsManager.heartFrames(for:)),
            ("💻 Взлом терминала 🔓", D1mplenChatToolsManager.hackFrames(for:))
        ]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Выберите эффект отправки")]
        for style in styles {
            items.append(ActionSheetButtonItem(title: style.title, color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                guard let self else { return }
                let prompt = promptController(
                    context: self.context,
                    text: "Финальный текст сообщения:",
                    value: "",
                    placeholder: "Введите текст",
                    characterLimit: 1000,
                    apply: { [weak self] value in
                        guard let self, let value else { return }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let frames = style.builder(trimmed)
                        D1mplenChatToolsManager.shared.sendAnimatedMessage(
                            context: self.context,
                            peerId: peerId,
                            threadId: threadId,
                            silent: silent,
                            frames: frames,
                            onComplete: { [weak self] ok in
                                if !ok {
                                    self?.d1mplenShowToast("Не удалось завершить анимацию", isSuccess: false)
                                }
                            }
                        )
                    }
                )
                self.present(prompt, in: .window(.root))
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentTextStyler(peerId: EnginePeer.Id, threadId: Int64?, silent: Bool) {
        let data = self.presentationData
        enum TextStyleKind {
            case alternating
            case spaced
            case reversed
            case wordSpoilers
        }
        let choices: [(String, TextStyleKind)] = [
            ("ЛеСеНкА (ПрИвЕт)", .alternating),
            ("В р а з р я д к у", .spaced),
            ("Наоборот (тевирП)", .reversed),
            ("Спойлер на каждое слово", .wordSpoilers)
        ]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Стиль оформления перед отправкой")]
        for (title, kind) in choices {
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                guard let self else { return }
                let prompt = promptController(
                    context: self.context,
                    text: "Введите текст:",
                    value: "",
                    placeholder: "Текст",
                    characterLimit: 1000,
                    apply: { [weak self] value in
                        guard let self, let value else { return }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        var outText = trimmed
                        var attributes: [EngineMessage.Attribute] = []
                        if silent {
                            attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                        }
                        switch kind {
                        case .alternating:
                            outText = D1mplenChatToolsManager.alternatingCase(trimmed)
                        case .spaced:
                            outText = D1mplenChatToolsManager.spacedText(trimmed)
                        case .reversed:
                            outText = String(trimmed.reversed())
                        case .wordSpoilers:
                            let entities = D1mplenChatToolsManager.wordSpoilerEntities(for: trimmed)
                            if !entities.isEmpty {
                                attributes.append(TextEntitiesMessageAttribute(entities: entities))
                            }
                        }
                        let msg: EnqueueMessage = .message(
                            text: outText,
                            attributes: attributes,
                            inlineStickers: [:],
                            mediaReference: nil,
                            threadId: threadId,
                            replyToMessageId: nil,
                            replyToStoryId: nil,
                            localGroupingKey: nil,
                            correlationId: nil,
                            bubbleUpEmojiOrStickersets: []
                        )
                        let _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).startStandalone()
                    }
                )
                self.present(prompt, in: .window(.root))
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPromptSendWhenOnline(peerId: EnginePeer.Id, displayName: String, username: String?, silent: Bool) {
        let prompt = promptController(
            context: self.context,
            text: "Сообщение для «\(displayName)» улетит автоматически, как только он(а) появится в сети:",
            value: "",
            placeholder: "Текст сообщения",
            characterLimit: 2000,
            apply: { [weak self] value in
                guard let self, let value else { return }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                D1mplenTrackerStore.shared.addOrUpdateContact(peerId: peerId.toInt64(), displayName: displayName, username: username)
                D1mplenTrackerStore.shared.enqueueOnlineMessage(peerId: peerId.toInt64(), text: trimmed, silent: silent)
                self.d1mplenShowToast("Поставлено в очередь до входа в сеть")
            }
        )
        self.present(prompt, in: .window(.root))
    }

    private func d1mplenPresentSelfDestructPicker(peerId: EnginePeer.Id, threadId: Int64?, silent: Bool) {
        let data = self.presentationData
        let askText: (Int) -> Void = { [weak self] seconds in
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Текст сообщения (удалится у всех через \(seconds)с после доставки):",
                value: "",
                placeholder: "Секретный текст",
                characterLimit: 1000,
                apply: { [weak self] value in
                    guard let self, let value else { return }
                    D1mplenChatToolsManager.shared.sendSelfDestructMessage(
                        context: self.context,
                        peerId: peerId,
                        threadId: threadId,
                        silent: silent,
                        text: value,
                        seconds: seconds,
                        onScheduled: { [weak self] ok in
                            self?.d1mplenShowToast(ok ? "Удалится через \(seconds)с" : "Ошибка запуска таймера", isSuccess: ok)
                        }
                    )
                }
            )
            self.present(prompt, in: .window(.root))
        }

        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Через сколько секунд удалить у всех?")]
        for sec in [5, 15, 30, 60] {
            items.append(ActionSheetButtonItem(title: "\(sec) секунд", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                askText(sec)
            }))
        }
        items.append(ActionSheetButtonItem(title: "⏱ Своё время…", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Таймер удаления в секундах (например 20 или 2m):",
                value: "20",
                placeholder: "Секунды",
                characterLimit: 12,
                apply: { value in
                    guard let value, let seconds = D1mplenChatToolsManager.parseDurationSeconds(value), seconds > 0 else { return }
                    askText(seconds)
                }
            )
            self.present(prompt, in: .window(.root))
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func d1mplenPresentCleanCountPicker(peerId: EnginePeer.Id) {
        let data = self.presentationData
        let runClean: (Int) -> Void = { [weak self] count in
            guard let self else { return }
            D1mplenChatToolsManager.shared.cleanMyRecentMessages(context: self.context, peerId: peerId, count: count, completion: { [weak self] deleted in
                self?.d1mplenShowToast(deleted > 0 ? "Удалено \(deleted) ваших сообщ." : "Ваших сообщений не найдено")
            })
        }

        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Удалить ваши последние сообщения у всех")]
        for count in [5, 10, 20, 50] {
            items.append(ActionSheetButtonItem(title: "Удалить последние \(count)", color: .destructive, action: { [weak sheet] in
                sheet?.dismissAnimated()
                runClean(count)
            }))
        }
        items.append(ActionSheetButtonItem(title: "✏️ Своё количество…", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            guard let self else { return }
            let prompt = promptController(
                context: self.context,
                text: "Сколько ваших последних сообщений удалить (1–100)?",
                value: "15",
                placeholder: "Количество",
                characterLimit: 4,
                apply: { value in
                    guard let value, let count = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return }
                    runClean(count)
                }
            )
            self.present(prompt, in: .window(.root))
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    // MARK: - Local Command Interceptor

    func d1mplenHandleLocalCommand(_ rawText: String, silentPosting: Bool) -> Bool {
        let extra = AyuGramSettings.shared.extra
        guard extra.d1mplenCommandsEnabled else {
            return false
        }
        guard case let .peer(peerId) = self.chatLocation else {
            return false
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".") else {
            return false
        }

        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let threadId = self.chatLocation.threadId
        let silent = silentPosting || self.presentationInterfaceState.interfaceState.silentPosting
        let manager = D1mplenChatToolsManager.shared

        switch cmd {
        case ".menu":
            self.d1mplenPresentChatTools()
            return true
        case ".fake":
            guard extra.d1mplenFakeStatusEnabled else {
                self.d1mplenShowToast("Фейк-статусы выключены в настройках D1mplenGram", isSuccess: false)
                return true
            }
            let tokens = arg.split(whereSeparator: { $0.isWhitespace }).map { String($0).lowercased() }
            if tokens.first == "stop" {
                manager.stopFakeStatus(context: self.context, peerId: peerId, threadId: threadId)
                self.d1mplenShowToast("Фейк-статус остановлен")
                return true
            }
            let kind: D1mplenFakeActivityKind
            switch tokens.first {
            case "round":
                kind = .recordingRound
            case "voice", "audio":
                kind = .recordingVoice
            case "photo":
                kind = .uploadingPhoto
            case "video":
                kind = .uploadingVideo
            case "game":
                kind = .playingGame
            case "sticker":
                kind = .choosingSticker
            default:
                kind = .typing
            }
            let seconds = tokens.dropFirst().first.flatMap(D1mplenChatToolsManager.parseDurationSeconds) ?? 30
            manager.startFakeStatus(context: self.context, peerId: peerId, threadId: threadId, kind: kind, durationSeconds: seconds, onFinish: { [weak self] in
                self?.d1mplenShowToast("Фейк-статус завершён")
            })
            self.d1mplenShowToast("Скрытый фейк-статус запущен на \(seconds)с")
            return true
        case ".like":
            guard extra.d1mplenMassReactionsEnabled else {
                self.d1mplenShowToast("Масс-реакции выключены в настройках D1mplenGram", isSuccess: false)
                return true
            }
            let tokens = arg.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if tokens.first?.lowercased() == "stop" {
                manager.stopMassReactions(for: peerId)
                self.d1mplenShowToast("Масс-реакции остановлены")
                return true
            }
            var count = 20
            var emoji = "❤️"
            var filter: D1mplenRecentMessageFilter = .incoming
            for token in tokens {
                let lower = token.lowercased()
                if let n = Int(token), n > 0 {
                    count = n
                } else if lower == "all" || lower == "все" {
                    filter = .all
                } else if lower == "me" || lower == "мои" {
                    filter = .outgoing
                } else if lower == "them" || lower == "он" || lower == "она" {
                    filter = .incoming
                } else {
                    emoji = token
                }
            }
            manager.startMassReactions(
                context: self.context,
                peerId: peerId,
                filter: filter,
                limit: count,
                emoji: emoji,
                onStarted: { [weak self] actual in
                    self?.d1mplenShowToast("Ставлю \(emoji) на \(actual) сообщ.…")
                },
                onDone: { [weak self] total in
                    self?.d1mplenShowToast(total > 0 ? "Готово: \(emoji) на \(total) сообщ." : "Сообщения не найдены")
                }
            )
            return true
        case ".type":
            guard extra.d1mplenTextAnimEnabled else {
                self.d1mplenShowToast("Анимация текста выключена в настройках D1mplenGram", isSuccess: false)
                return true
            }
            guard !arg.isEmpty else {
                self.d1mplenShowToast("Использование: .type ваш текст", isSuccess: false)
                return true
            }
            manager.sendAnimatedMessage(
                context: self.context,
                peerId: peerId,
                threadId: threadId,
                silent: silent,
                frames: D1mplenChatToolsManager.typewriterFrames(for: arg)
            )
            return true
        case ".timer":
            guard extra.d1mplenSelfDestructEnabled else {
                self.d1mplenShowToast("Таймер самоуничтожения выключен в настройках D1mplenGram", isSuccess: false)
                return true
            }
            let sub = arg.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard sub.count == 2, let seconds = D1mplenChatToolsManager.parseDurationSeconds(sub[0]), seconds > 0 else {
                self.d1mplenShowToast("Использование: .timer 15с текст", isSuccess: false)
                return true
            }
            manager.sendSelfDestructMessage(
                context: self.context,
                peerId: peerId,
                threadId: threadId,
                silent: silent,
                text: sub[1],
                seconds: seconds,
                onScheduled: { [weak self] ok in
                    self?.d1mplenShowToast(ok ? "Удалится через \(seconds)с" : "Ошибка запуска таймера", isSuccess: ok)
                }
            )
            return true
        case ".online":
            guard extra.d1mplenSendWhenOnlineEnabled else {
                self.d1mplenShowToast("Отправка при онлайне выключена в настройках", isSuccess: false)
                return true
            }
            guard !arg.isEmpty else {
                self.d1mplenShowToast("Использование: .online ваш текст", isSuccess: false)
                return true
            }
            let enginePeer = self.presentationInterfaceState.renderedPeer?.peer.map(EnginePeer.init)
            let displayName = enginePeer?.debugDisplayTitle ?? "Контакт"
            D1mplenTrackerStore.shared.addOrUpdateContact(peerId: peerId.toInt64(), displayName: displayName, username: enginePeer?.addressName)
            D1mplenTrackerStore.shared.enqueueOnlineMessage(peerId: peerId.toInt64(), text: arg, silent: silent)
            self.d1mplenShowToast("Поставлено в очередь до входа в сеть")
            return true
        case ".clean":
            guard extra.d1mplenCleanMyMessagesEnabled else {
                self.d1mplenShowToast("Очистка сообщений выключена в настройках", isSuccess: false)
                return true
            }
            let count = Int(arg) ?? 10
            manager.cleanMyRecentMessages(context: self.context, peerId: peerId, count: count, completion: { [weak self] deleted in
                self?.d1mplenShowToast(deleted > 0 ? "Удалено \(deleted) ваших сообщ." : "Ваших сообщений не найдено")
            })
            return true
        default:
            return false
        }
    }
}
