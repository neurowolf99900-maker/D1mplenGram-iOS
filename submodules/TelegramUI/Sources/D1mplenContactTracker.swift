import Foundation
import SwiftSignalKit
import TelegramCore
import SGSimpleSettings

final class D1mplenContactTracker {
    private var primaryId: AccountRecordId?
    private var accounts: [AccountRecordId: Account] = [:]
    private var subscribedAccountId: AccountRecordId?
    private var subscribedPeerIds = Set<Int64>()
    private var cachedPresenceUntil: [Int64: Double] = [:]
    private var queuedSendingIds = Set<String>()
    private var lastTypingAlertTimes: [Int64: Double] = [:]

    private let peerDisposables = DisposableDict<Int64>()
    private let activityDisposables = DisposableDict<Int64>()
    private let globalActivityDisposable = MetaDisposable()
    private var refreshTimer: SwiftSignalKit.Timer?
    private var expiryTimer: SwiftSignalKit.Timer?
    private var storeObserver: NSObjectProtocol?
    private var inFlightAiReplies = Set<Int64>()
    private var lastAiReplyTimes: [Int64: Double] = [:]

    init() {
        self.storeObserver = NotificationCenter.default.addObserver(
            forName: D1mplenTrackerStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncTrackedPeers()
        }
    }

    deinit {
        if let storeObserver = self.storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
        self.refreshTimer?.invalidate()
        self.expiryTimer?.invalidate()
        self.peerDisposables.dispose()
        self.activityDisposables.dispose()
        self.globalActivityDisposable.dispose()
    }

    func update(primary: AccountRecordId?, accounts: [(AccountRecordId, Account)]) {
        self.primaryId = primary
        self.accounts.removeAll(keepingCapacity: true)
        for (id, account) in accounts {
            self.accounts[id] = account
        }
        self.syncTrackedPeers()
        self.ensureTimers()
    }

    private func activeAccountEntry() -> (id: AccountRecordId, account: Account)? {
        if let primaryId = self.primaryId, let primaryAccount = self.accounts[primaryId] {
            return (primaryId, primaryAccount)
        }
        if let first = self.accounts.first {
            return (first.key, first.value)
        }
        return nil
    }

    private func ensureTimers() {
        if self.refreshTimer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 35.0, repeat: true, completion: { [weak self] in
                self?.refreshAllTrackedPeers()
            }, queue: Queue.mainQueue())
            self.refreshTimer = timer
            timer.start()
        }
        if self.expiryTimer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 10.0, repeat: true, completion: { [weak self] in
                self?.checkPresenceExpirations()
            }, queue: Queue.mainQueue())
            self.expiryTimer = timer
            timer.start()
        }
    }

    private func syncTrackedPeers() {
        guard let active = self.activeAccountEntry() else {
            for peerId in self.subscribedPeerIds {
                self.peerDisposables.set(nil, forKey: peerId)
                self.activityDisposables.set(nil, forKey: peerId)
            }
            self.subscribedPeerIds.removeAll()
            self.subscribedAccountId = nil
            return
        }

        if self.subscribedAccountId != active.id {
            for peerId in self.subscribedPeerIds {
                self.peerDisposables.set(nil, forKey: peerId)
                self.activityDisposables.set(nil, forKey: peerId)
            }
            self.subscribedPeerIds.removeAll()
            self.subscribedAccountId = active.id

            let globalSignal = active.account.allPeerInputActivities()
            |> deliverOnMainQueue
            self.globalActivityDisposable.set(globalSignal.startStrict(next: { [weak self, weak account = active.account] dict in
                guard let self, let account else { return }
                let now = Date().timeIntervalSince1970
                for (_, list) in dict {
                    for (activityPeerId, activity) in list {
                        if activityPeerId == account.peerId {
                            continue
                        }
                        guard let mapped = Self.mapInputActivity(activity) else {
                            continue
                        }
                        let rawPeerId = activityPeerId.toInt64()
                        let lastPacket = self.lastTypingAlertTimes[rawPeerId] ?? 0.0
                        let isNewSession = (now - lastPacket >= 7.0)
                        self.lastTypingAlertTimes[rawPeerId] = now

                        let contact = D1mplenTrackerStore.shared.contact(for: rawPeerId)
                        let allowActivity: Bool
                        switch mapped.kind {
                        case .typingStarted:
                            allowActivity = contact?.trackTyping ?? true
                        case .recordingRound, .recordingVoice:
                            allowActivity = contact?.trackVoiceAndVideo ?? true
                        default:
                            allowActivity = true
                        }

                        if AyuGramSettings.shared.extra.d1mplenTrackTyping && allowActivity && isNewSession {
                            if contact != nil {
                                let _ = D1mplenTrackerStore.shared.recordActivity(
                                    peerId: rawPeerId,
                                    kind: mapped.kind,
                                    detail: mapped.detail,
                                    now: now
                                )
                            }
                            let cachedTitle = contact?.displayName
                            let engine = TelegramEngine(account: account)
                            let _ = (engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: activityPeerId))
                            |> deliverOnMainQueue).startStandalone(next: { peer in
                                let peerTitle = peer?.debugDisplayTitle
                                let name = (peerTitle?.isEmpty == false ? peerTitle : nil) ?? cachedTitle ?? "Собеседник"
                                AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                                    accountId: active.id,
                                    account: account,
                                    peerId: rawPeerId,
                                    title: "\(mapped.kind.displayEmoji) \(name)",
                                    body: "\(mapped.kind.displayTitle) · \(Self.formatTime(now))",
                                    threadKey: "typing"
                                )
                            })
                        }
                    }
                }
            }))
        }

        let desired = Set(D1mplenTrackerStore.shared.trackedPeerIds())
        for removed in self.subscribedPeerIds.subtracting(desired) {
            self.peerDisposables.set(nil, forKey: removed)
            self.activityDisposables.set(nil, forKey: removed)
            self.subscribedPeerIds.remove(removed)
            self.cachedPresenceUntil.removeValue(forKey: removed)
        }

        for peerId in desired.subtracting(self.subscribedPeerIds) {
            self.subscribedPeerIds.insert(peerId)
            self.subscribePeer(rawPeerId: peerId, accountId: active.id, account: active.account)
        }
    }

    private func subscribePeer(rawPeerId: Int64, accountId: AccountRecordId, account: Account) {
        let enginePeerId = EnginePeer.Id(rawPeerId)
        let _ = d1mplenRefreshTrackedPeer(account: account, peerId: enginePeerId).startStandalone()
        let _ = TelegramEngine(account: account).peers.fetchAndUpdateCachedPeerData(peerId: enginePeerId).startStandalone()

        let dataSignal = TelegramEngine(account: account).data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: enginePeerId),
            TelegramEngine.EngineData.Item.Peer.Presence(id: enginePeerId),
            TelegramEngine.EngineData.Item.Peer.AboutText(id: enginePeerId),
            TelegramEngine.EngineData.Item.Peer.CommonGroupCount(id: enginePeerId)
        )
        |> deliverOnMainQueue

        self.peerDisposables.set(dataSignal.startStrict(next: { [weak self, weak account] peer, presence, aboutItem, commonGroups in
            guard let self, let account else {
                return
            }
            let now = Date().timeIntervalSince1970
            let extra = AyuGramSettings.shared.extra
            let fallbackName = D1mplenTrackerStore.shared.contact(for: rawPeerId)?.displayName ?? "Контакт \(rawPeerId)"
            let peerTitle = peer?.debugDisplayTitle
            let displayName = (peerTitle?.isEmpty == false ? peerTitle : nil) ?? fallbackName
            let username = peer?.addressName
            let avatarId = peer?.smallProfileImage?.resource.id.stringRepresentation

            let aboutKnown: Bool
            let aboutText: String?
            switch aboutItem {
            case let .known(value):
                aboutKnown = true
                aboutText = value
            case .unknown:
                aboutKnown = false
                aboutText = nil
            }

            if peer != nil {
                let changes = D1mplenTrackerStore.shared.recordProfileSnapshot(
                    peerId: rawPeerId,
                    displayName: displayName,
                    username: username,
                    aboutKnown: aboutKnown,
                    about: aboutText,
                    avatarId: avatarId,
                    commonGroupsCount: commonGroups,
                    now: now
                )
                for change in changes {
                    switch change.kind {
                    case .avatarChanged:
                        if extra.d1mplenTrackAvatar {
                            AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                                accountId: accountId,
                                account: account,
                                peerId: rawPeerId,
                                title: "🖼 \(displayName) обновил(а) аватарку",
                                body: "\(change.detail) · \(Self.formatTime(now))",
                                threadKey: "profile"
                            )
                        }
                    case .nameChanged, .usernameChanged, .bioChanged:
                        if extra.d1mplenTrackProfile {
                            AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                                accountId: accountId,
                                account: account,
                                peerId: rawPeerId,
                                title: "📝 \(displayName): \(change.kind.displayTitle.lowercased())",
                                body: "\(change.detail) · \(Self.formatTime(now))",
                                threadKey: "profile"
                            )
                        }
                    default:
                        break
                    }
                }
            }

            let isOnline: Bool
            let statusUntil: Int32?
            if let presence, case let .present(until) = presence.status {
                self.cachedPresenceUntil[rawPeerId] = Double(until)
                isOnline = Double(until) > now
                statusUntil = until
            } else {
                self.cachedPresenceUntil[rawPeerId] = nil
                isOnline = false
                statusUntil = nil
            }

            let transition = D1mplenTrackerStore.shared.updatePresence(
                peerId: rawPeerId,
                displayName: displayName,
                isOnline: isOnline,
                statusUntil: statusUntil,
                now: now
            )

            let contact = D1mplenTrackerStore.shared.contact(for: rawPeerId)
            let allowPresence = contact?.trackPresence ?? true

            if allowPresence && transition.becameOnline && extra.d1mplenTrackOnline {
                AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                    accountId: accountId,
                    account: account,
                    peerId: rawPeerId,
                    title: "🟢 \(displayName) в сети",
                    body: "Зашёл онлайн в \(Self.formatTime(now))",
                    threadKey: "presence"
                )
            } else if allowPresence && transition.becameOffline && extra.d1mplenTrackOffline {
                AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                    accountId: accountId,
                    account: account,
                    peerId: rawPeerId,
                    title: "⚫ \(displayName) вышел(а) из сети",
                    body: "Вышел из сети в \(Self.formatTime(now))",
                    threadKey: "presence"
                )
            }

            if isOnline {
                self.flushQueuedMessagesIfNeeded(rawPeerId: rawPeerId, displayName: displayName, accountId: accountId, account: account)
            }
        }), forKey: rawPeerId)

        let activitySignal = account.peerInputActivities(peerId: PeerActivitySpace(peerId: enginePeerId, category: .global))
        |> deliverOnMainQueue

        self.activityDisposables.set(activitySignal.startStrict(next: { [weak self] list in
            guard let self else {
                return
            }
            for (activityPeerId, activity) in list where activityPeerId == enginePeerId {
                guard let mapped = Self.mapInputActivity(activity) else {
                    continue
                }
                let now = Date().timeIntervalSince1970
                let lastPacket = self.lastTypingAlertTimes[rawPeerId] ?? 0.0
                let isNewSession = (now - lastPacket >= 8.0)
                self.lastTypingAlertTimes[rawPeerId] = now

                let contact = D1mplenTrackerStore.shared.contact(for: rawPeerId)
                let allowActivity: Bool
                switch mapped.kind {
                case .typingStarted:
                    allowActivity = contact?.trackTyping ?? true
                case .recordingRound, .recordingVoice:
                    allowActivity = contact?.trackVoiceAndVideo ?? true
                default:
                    allowActivity = true
                }

                if AyuGramSettings.shared.extra.d1mplenTrackTyping && allowActivity && isNewSession {
                    let _ = D1mplenTrackerStore.shared.recordActivity(
                        peerId: rawPeerId,
                        kind: mapped.kind,
                        detail: mapped.detail,
                        now: now
                    )
                    let name = contact?.displayName ?? "Контакт"
                    AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                        accountId: accountId,
                        account: account,
                        peerId: rawPeerId,
                        title: "\(mapped.kind.displayEmoji) \(name)",
                        body: "\(mapped.kind.displayTitle) · \(Self.formatTime(now))",
                        threadKey: "typing"
                    )
                }
            }
        }), forKey: rawPeerId)
    }

    private func flushQueuedMessagesIfNeeded(rawPeerId: Int64, displayName: String, accountId: AccountRecordId, account: Account) {
        let queued = D1mplenTrackerStore.shared.popQueuedMessages(for: rawPeerId)
        guard !queued.isEmpty else {
            return
        }
        let pid = EnginePeer.Id(rawPeerId)
        var enqueuedMessages: [EnqueueMessage] = []
        for item in queued where !self.queuedSendingIds.contains(item.id) {
            self.queuedSendingIds.insert(item.id)
            var attributes: [EngineMessage.Attribute] = []
            if item.silent {
                attributes.append(NotificationInfoMessageAttribute(flags: .muted))
            }
            enqueuedMessages.append(
                .message(
                    text: item.text,
                    attributes: attributes,
                    inlineStickers: [:],
                    mediaReference: nil,
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
            )
        }
        guard !enqueuedMessages.isEmpty else {
            return
        }
        let _ = (enqueueMessages(account: account, peerId: pid, messages: enqueuedMessages)
        |> deliverOnMainQueue).startStandalone(completed: {
            AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                accountId: accountId,
                account: account,
                peerId: rawPeerId,
                title: "⚡ Отправлено при входе в сеть",
                body: "Доставлено для \(displayName) (\(enqueuedMessages.count) сообщ.)",
                threadKey: "queue"
            )
        })
    }

    private func refreshAllTrackedPeers() {
        guard let active = self.activeAccountEntry() else {
            return
        }
        let ids = D1mplenTrackerStore.shared.trackedPeerIds()
        guard !ids.isEmpty else {
            return
        }
        let engine = TelegramEngine(account: active.account)
        for rawId in ids {
            let pid = EnginePeer.Id(rawId)
            let _ = d1mplenRefreshTrackedPeer(account: active.account, peerId: pid).startStandalone()
            let _ = engine.peers.fetchAndUpdateCachedPeerData(peerId: pid).startStandalone()
        }
    }

    private func checkPresenceExpirations() {
        let now = Date().timeIntervalSince1970
        let extra = AyuGramSettings.shared.extra
        let active = self.activeAccountEntry()
        for contact in D1mplenTrackerStore.shared.allContacts() where contact.isCurrentlyOnline {
            guard let until = self.cachedPresenceUntil[contact.peerId] else {
                continue
            }
            if now > until + 3.0 {
                let transition = D1mplenTrackerStore.shared.updatePresence(
                    peerId: contact.peerId,
                    displayName: contact.displayName,
                    isOnline: false,
                    statusUntil: Int32(until),
                    now: now
                )
                if transition.becameOffline && extra.d1mplenTrackOffline {
                    AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                        accountId: active?.id,
                        account: active?.account,
                        peerId: contact.peerId,
                        title: "⚫ \(contact.displayName) вышел(а) из сети",
                        body: "Вышел из сети в \(Self.formatTime(now))",
                        threadKey: "presence"
                    )
                }
            }
        }
    }

    private static func mapInputActivity(_ activity: PeerInputActivity) -> (kind: D1mplenTrackerEventKind, detail: String)? {
        switch activity {
        case .typingText:
            return (.typingStarted, "В окне личного чата")
        case .recordingInstantVideo:
            return (.recordingRound, "Начал запись видеосообщения")
        case .recordingVoice:
            return (.recordingVoice, "Начал запись голосового")
        case .uploadingPhoto:
            return (.uploadingMedia, "Загружает фото")
        case .uploadingVideo, .uploadingInstantVideo, .uploadingFile:
            return (.uploadingMedia, "Загружает файл или видео")
        default:
            return nil
        }
    }

    private static func formatTime(_ timestamp: Double) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "HH:mm"
        return df.string(from: Date(timeIntervalSince1970: timestamp))
    }

    func handleIncomingMessageForAiReply(
        account: Account,
        peerId: Int64,
        incomingText: String,
        contact: D1mplenTrackedContact
    ) {
        guard contact.aiAutoReplyEnabled else { return }
        guard !incomingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !self.inFlightAiReplies.contains(peerId) else { return }

        let now = Date().timeIntervalSince1970
        let lastTime = self.lastAiReplyTimes[peerId] ?? 0.0
        guard now - lastTime >= 6.0 else { return }

        self.inFlightAiReplies.insert(peerId)
        let enginePeerId = EnginePeer.Id(peerId)
        let space = PeerActivitySpace(peerId: enginePeerId, category: .global)

        account.updateLocalInputActivity(peerId: space, activity: .typingText, isPresent: true)

        let engine = TelegramEngine(account: account)
        let historySignal = engine.messages.ayuExportHistoryPage(peerId: enginePeerId, offsetId: 0, limit: 25)
        |> take(1)
        |> deliverOnMainQueue

        let _ = historySignal.startStandalone(next: { [weak self, weak account] page in
            guard let self, let account else {
                self?.inFlightAiReplies.remove(peerId)
                return
            }

            var userSampleLines: [String] = []
            var recentDialogLines: [String] = []

            if let messages = page?.messages {
                for m in messages.reversed() {
                    let isOut = !m.flags.contains(.Incoming)
                    let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    if isOut {
                        userSampleLines.append(text)
                        recentDialogLines.append("Я: \(text)")
                    } else {
                        recentDialogLines.append("Собеседник: \(text)")
                    }
                }
            }

            if recentDialogLines.isEmpty {
                recentDialogLines.append("Собеседник: \(incomingText)")
            }

            let userStyleContext = userSampleLines.suffix(10).joined(separator: "\n")
            let recentDialogContext = recentDialogLines.suffix(12).joined(separator: "\n")

            let systemPrompt = """
            Ты — персональный AI-автоответчик в Telegram. Ты отвечаешь от лица владельца аккаунта.
            Твоя ГЛАВНАЯ цель — написать ответ так, чтобы собеседник не догадался, что пишет ИИ.

            ПРИМЕРЫ СООБЩЕНИЙ ВЛАДЕЛЬЦА АККАУНТА (изучи его стиль, регистр, длину сообщений, сленг, смайлики):
            \(userStyleContext.isEmpty ? "Короткие ответы по делу, дружелюбно, без формальностей" : userStyleContext)

            ПРАВИЛА:
            1. Отвечай СТРОГО в стиле владельца (если он пишет с маленькой буквы — пиши с маленькой; если использует сленг или смайлики — используй их; если отвечает кратко — отвечай кратко).
            2. НИКАКИХ фраз робота ("Я виртуальный помощник", "Здравствуйте!", "Чем могу помочь?").
            3. Отвечай только готовым текстом сообщения. Никаких кавычек или пояснений.
            """

            let userPrompt = """
            Контекст последних сообщений в чате:
            \(recentDialogContext)

            Последнее сообщение собеседника: "\(incomingText)"
            Напиши ответ:
            """

            pipAiComplete(system: systemPrompt, prompt: userPrompt, maxTokens: 200) { [weak self, weak account] responseText in
                Queue.mainQueue().async {
                    guard let self, let account, let response = responseText?.trimmingCharacters(in: .whitespacesAndNewlines), !response.isEmpty else {
                        self?.inFlightAiReplies.remove(peerId)
                        return
                    }

                    let configuredDelay = Double(max(0, contact.aiAutoReplyDelaySeconds))
                    let typingDuration = max(2.5, min(9.0, Double(response.count) * 0.08))
                    let totalWait = configuredDelay + typingDuration

                    let timer = SwiftSignalKit.Timer(timeout: 2.5, repeat: true, completion: { [weak account] in
                        account?.updateLocalInputActivity(peerId: space, activity: .typingText, isPresent: true)
                    }, queue: Queue.mainQueue())
                    timer.start()

                    Queue.mainQueue().after(totalWait) { [weak self, weak account] in
                        timer.invalidate()
                        guard let self, let account else {
                            self?.inFlightAiReplies.remove(peerId)
                            return
                        }

                        let enqueuedMessage = EnqueueMessage.message(
                            text: response,
                            attributes: [],
                            inlineStickers: [:],
                            mediaReference: nil,
                            threadId: nil,
                            replyToMessageId: nil,
                            replyToStoryId: nil,
                            localGroupingKey: nil,
                            correlationId: nil,
                            bubbleUpEmojiOrStickersets: []
                        )

                        let _ = (enqueueMessages(account: account, peerId: enginePeerId, messages: [enqueuedMessage])
                        |> deliverOnMainQueue).startStandalone(completed: { [weak self] in
                            guard let self else { return }
                            self.lastAiReplyTimes[peerId] = Date().timeIntervalSince1970
                            self.inFlightAiReplies.remove(peerId)

                            AyuGramBackgroundNotifier.current?.postD1mplenCustomAlert(
                                accountId: account.id,
                                account: account,
                                peerId: peerId,
                                title: "🤖 Pip AI ответил",
                                body: "Для \(contact.displayName): «\(response)»",
                                threadKey: "ai-reply"
                            )
                        })
                    }
                }
            }
        })
    }

}
