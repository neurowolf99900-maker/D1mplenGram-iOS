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
    private var refreshTimer: SwiftSignalKit.Timer?
    private var expiryTimer: SwiftSignalKit.Timer?
    private var storeObserver: NSObjectProtocol?

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
            let displayName = (peer?.debugDisplayTitle).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
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
                let recorded = D1mplenTrackerStore.shared.recordActivity(
                    peerId: rawPeerId,
                    kind: mapped.kind,
                    detail: mapped.detail,
                    now: now
                )
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
                if recorded && AyuGramSettings.shared.extra.d1mplenTrackTyping && allowActivity {
                    let cooldown = AyuGramSettings.shared.extra.pipTypingCooldownSeconds
                    let lastAlert = self.lastTypingAlertTimes[rawPeerId] ?? 0.0
                    if now - lastAlert >= cooldown {
                        self.lastTypingAlertTimes[rawPeerId] = now
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
}
