import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

public enum D1mplenFakeActivityKind: Int32, CaseIterable, Equatable {
    case typing
    case recordingRound
    case recordingVoice
    case uploadingPhoto
    case uploadingVideo
    case playingGame
    case choosingSticker
    case cancel
}

public enum D1mplenRecentMessageFilter: Int32, Equatable {
    case incoming
    case outgoing
    case all
}

private func d1mplenApiAction(for kind: D1mplenFakeActivityKind) -> Api.SendMessageAction {
    switch kind {
    case .typing:
        return .sendMessageTypingAction
    case .recordingRound:
        return .sendMessageRecordRoundAction
    case .recordingVoice:
        return .sendMessageRecordAudioAction
    case .uploadingPhoto:
        return .sendMessageUploadPhotoAction(.init(progress: 50))
    case .uploadingVideo:
        return .sendMessageUploadVideoAction(.init(progress: 50))
    case .playingGame:
        return .sendMessageGamePlayAction
    case .choosingSticker:
        return .sendMessageChooseStickerAction
    case .cancel:
        return .sendMessageCancelAction
    }
}

public func d1mplenSendFakeActivity(
    account: Account,
    peerId: PeerId,
    threadId: Int64? = nil,
    kind: D1mplenFakeActivityKind
) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Signal<Void, NoError> in
        guard peerId != account.peerId, let peer = transaction.getPeer(peerId) else {
            return .complete()
        }
        if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
            return .complete()
        }
        if let inputPeer = apiInputPeer(peer) {
            var flags: Int32 = 0
            let topMessageId = threadId.flatMap { Int32(clamping: $0) }
            if topMessageId != nil {
                flags |= 1 << 0
            }
            return account.network.request(
                Api.functions.messages.setTyping(
                    flags: flags,
                    peer: inputPeer,
                    topMsgId: topMessageId,
                    action: d1mplenApiAction(for: kind)
                )
            )
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .single(.boolFalse)
            }
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
            }
        } else if let secretChat = peer as? TelegramSecretChat, kind == .typing || kind == .cancel {
            return account.network.request(
                Api.functions.messages.setEncryptedTyping(
                    peer: .inputEncryptedChat(.init(
                        chatId: Int32(secretChat.id.id._internalGetInt64Value()),
                        accessHash: secretChat.accessHash
                    )),
                    typing: kind == .cancel ? .boolFalse : .boolTrue
                )
            )
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .single(.boolFalse)
            }
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
            }
        } else {
            return .complete()
        }
    }
    |> switchToLatest
}

public func d1mplenRecentMessageIds(
    account: Account,
    peerId: PeerId,
    filter: D1mplenRecentMessageFilter,
    limit: Int
) -> Signal<[MessageId], NoError> {
    guard limit > 0 else {
        return .single([])
    }
    return account.postbox.transaction { transaction -> [MessageId] in
        var result: [MessageId] = []
        let scanLimit = max(limit * 5, 250)
        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: scanLimit) { message -> Bool in
            if result.count >= limit {
                return false
            }
            if message.ayuHistory?.deletedAt != nil {
                return true
            }
            if message.media.contains(where: { $0 is TelegramMediaAction }) {
                return true
            }
            switch filter {
            case .incoming:
                guard message.flags.contains(.Incoming) else { return true }
            case .outgoing:
                guard !message.flags.contains(.Incoming) else { return true }
                if let authorId = message.author?.id, authorId != account.peerId {
                    return true
                }
            case .all:
                break
            }
            result.append(message.id)
            return result.count < limit
        }
        return result
    }
}

public func d1mplenWaitForCloudMessageId(
    account: Account,
    peerId: PeerId,
    localId: MessageId,
    matchText: String? = nil,
    timeout: Double = 25.0
) -> Signal<MessageId?, NoError> {
    if localId.namespace == Namespaces.Message.Cloud {
        return .single(localId)
    }
    let startedAt = CFAbsoluteTimeGetCurrent()
    let deadline = startedAt + max(1.0, timeout)

    func poll(knownUniqueId: Int64?) -> Signal<MessageId?, NoError> {
        return account.postbox.transaction { transaction -> (cloudId: MessageId?, uniqueId: Int64?) in
            var uniqueId = knownUniqueId
            if uniqueId == nil, let localMessage = transaction.getMessage(localId) {
                uniqueId = localMessage.globallyUniqueId
            }
            if let uid = uniqueId, let cloudId = transaction.messageIdForGloballyUniqueMessageId(peerId: peerId, id: uid), cloudId.namespace == Namespaces.Message.Cloud {
                return (cloudId, uid)
            }
            if uniqueId == nil, let matchText, !matchText.isEmpty {
                var matched: MessageId?
                let nowTs = Int32(Date().timeIntervalSince1970)
                transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 15) { message -> Bool in
                    if !message.flags.contains(.Incoming),
                       message.text == matchText,
                       abs(nowTs - message.timestamp) < 45 {
                        matched = message.id
                        return false
                    }
                    return true
                }
                if let matched {
                    return (matched, nil)
                }
            }
            return (nil, uniqueId)
        }
        |> mapToSignal { result -> Signal<MessageId?, NoError> in
            if let cloudId = result.cloudId {
                return .single(cloudId)
            }
            if CFAbsoluteTimeGetCurrent() >= deadline {
                return .single(nil)
            }
            return (Signal<MessageId?, NoError>.complete() |> delay(0.35, queue: Queue.concurrentDefaultQueue()))
            |> then(poll(knownUniqueId: result.uniqueId))
        }
    }

    return poll(knownUniqueId: nil)
}

public func d1mplenRefreshTrackedPeer(
    account: Account,
    peerId: PeerId
) -> Signal<Bool, NoError> {
    guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != account.peerId else {
        return .single(false)
    }
    return account.postbox.transaction { transaction -> Api.InputUser? in
        return transaction.getPeer(peerId).flatMap { apiInputUser($0) }
    }
    |> mapToSignal { inputUser -> Signal<Bool, NoError> in
        guard let inputUser else {
            return .single(false)
        }
        return account.network.request(Api.functions.users.getUsers(id: [inputUser]))
        |> `catch` { _ -> Signal<[Api.User], NoError> in
            return .single([])
        }
        |> mapToSignal { users -> Signal<Bool, NoError> in
            var matchedUser: Api.User?
            for user in users where user.peerId == peerId {
                if case .user = user {
                    matchedUser = user
                }
                break
            }
            guard let matchedUser else {
                return .single(false)
            }
            let tgUser = TelegramUser(user: matchedUser)
            let presence = TelegramUserPresence(apiUser: matchedUser)
            return account.postbox.transaction { transaction -> Bool in
                updatePeersCustom(transaction: transaction, peers: [tgUser], update: { _, updated in
                    return updated
                })
                if let presence {
                    transaction.updatePeerPresencesInternal(presences: [peerId: presence], merge: { _, updated in
                        return updated
                    })
                }
                return true
            }
        }
    }
}
