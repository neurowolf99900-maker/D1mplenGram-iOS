import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import Postbox
import TelegramPresentationData
import ItemListUI
import SGItemListUI
import SGSimpleSettings

private enum D1mplenTrackerListSection: Int32 {
    case contacts
    case alerts
}

private enum D1mplenTrackerToggle: Equatable {
    case online
    case offline
    case typing
    case avatar
    case profile
}

private enum D1mplenTrackerListAction {
    case selectContacts
    case openContact(PeerId)
    case toggle(D1mplenTrackerToggle, Bool)
}

private final class D1mplenTrackerListArguments {
    let context: AccountContext
    let perform: (D1mplenTrackerListAction) -> Void

    init(context: AccountContext, perform: @escaping (D1mplenTrackerListAction) -> Void) {
        self.context = context
        self.perform = perform
    }
}

private enum D1mplenTrackerListEntry: ItemListNodeEntry {
    case header(id: Int, section: D1mplenTrackerListSection, text: String)
    case selectContacts(id: Int, title: String, label: String)
    case contact(id: Int, contact: D1mplenTrackedContact, peer: EnginePeer?, todaySeconds: TimeInterval, now: Double)
    case emptyNotice(id: Int, text: String)
    case toggle(id: Int, key: D1mplenTrackerToggle, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool)
    case footer(id: Int, section: D1mplenTrackerListSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case .selectContacts, .contact, .emptyNotice:
            return D1mplenTrackerListSection.contacts.rawValue
        case .toggle:
            return D1mplenTrackerListSection.alerts.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .selectContacts(id, _, _),
             let .contact(id, _, _, _, _),
             let .emptyNotice(id, _),
             let .toggle(id, _, _, _, _, _, _),
             let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: D1mplenTrackerListEntry, rhs: D1mplenTrackerListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! D1mplenTrackerListArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .selectContacts(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon("person.crop.circle.badge.plus", color: AyuGramRowColor.blue),
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.perform(.selectContacts)
                }
            )
        case let .contact(_, contact, peer, todaySeconds, _):
            let name = peer?.debugDisplayTitle ?? contact.displayName
            let statusText: String
            if contact.isCurrentlyOnline {
                statusText = "🟢 В сети"
            } else if todaySeconds > 0 {
                statusText = "Сегодня \(D1mplenContactAnalytics.formatDuration(todaySeconds))"
            } else if let lastSeen = contact.lastSeenAt {
                statusText = "Был(а) \(d1mplenShortTime(lastSeen))"
            } else {
                statusText = "Ожидание"
            }
            if let peer {
                return ItemListDisclosureItem(
                    presentationData: presentationData,
                    context: args.context,
                    iconPeer: peer,
                    title: name.isEmpty ? "\(contact.peerId)" : name,
                    label: statusText,
                    sectionId: self.section,
                    style: .blocks,
                    action: {
                        args.perform(.openContact(peer.id))
                    }
                )
            } else {
                return ItemListDisclosureItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    icon: ayuGramRowIcon("person.circle.fill", color: AyuGramRowColor.teal),
                    title: name.isEmpty ? "\(contact.peerId)" : name,
                    label: statusText,
                    sectionId: self.section,
                    style: .blocks,
                    action: {
                        args.perform(.openContact(PeerId(contact.peerId)))
                    }
                )
            }
        case let .emptyNotice(_, text):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: text,
                enabled: false,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .toggle(_, key, symbol, color, title, subtitle, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon(symbol, color: color),
                title: title,
                text: subtitle,
                value: value,
                enabled: true,
                maximumNumberOfLines: 0,
                sectionId: self.section,
                style: .blocks,
                updated: { updatedValue in
                    args.perform(.toggle(key, updatedValue))
                }
            )
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func d1mplenShortTime(_ timestamp: Double) -> String {
    let date = Date(timeIntervalSince1970: timestamp)
    let df = DateFormatter()
    df.locale = Locale(identifier: "ru_RU")
    df.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "dd.MM HH:mm"
    return df.string(from: date)
}

private func d1mplenTrackerListEntries(
    extra: AyuGramExtraSettings,
    contacts: [D1mplenTrackedContact],
    peers: [PeerId: EnginePeer],
    now: Double
) -> [D1mplenTrackerListEntry] {
    var entries: [D1mplenTrackerListEntry] = []

    entries.append(.header(id: 100, section: .contacts, text: "ОТСЛЕЖИВАЕМЫЕ КОНТАКТЫ"))
    entries.append(.selectContacts(
        id: 110,
        title: "Выбрать контакты…",
        label: contacts.isEmpty ? "Нет" : "\(contacts.count)"
    ))

    if contacts.isEmpty {
        entries.append(.emptyNotice(id: 120, text: "Выберите людей — радар начнёт сбор статистики"))
    } else {
        for (idx, contact) in contacts.enumerated() {
            let todaySeconds = D1mplenTrackerStore.shared.analytics(for: contact.peerId, now: now)?.todayOnlineSeconds ?? 0
            let peer = peers[PeerId(contact.peerId)]
            entries.append(.contact(
                id: 130 + idx,
                contact: contact,
                peer: peer,
                todaySeconds: todaySeconds,
                now: now
            ))
        }
    }
    entries.append(.footer(
        id: 290,
        section: .contacts,
        text: "Нажмите на контакт, чтобы открыть подробную статистику: время в сети, среднее время захода/выхода, пиковый час, общие группы и лог событий. Также добавить контакт можно прямо в чате через кнопку «⚡»."
    ))

    entries.append(.header(id: 300, section: .alerts, text: "УВЕДОМЛЕНИЯ МОНИТОРИНГА"))
    entries.append(.toggle(
        id: 310,
        key: .online,
        symbol: "circle.fill",
        color: AyuGramRowColor.green,
        title: "Заход в сеть (Онлайн)",
        subtitle: "Присылать уведомление, когда контакт появляется онлайн",
        value: extra.d1mplenTrackOnline
    ))
    entries.append(.toggle(
        id: 320,
        key: .offline,
        symbol: "moon.fill",
        color: AyuGramRowColor.gray,
        title: "Выход из сети (Офлайн)",
        subtitle: "Фиксировать завершение сессии и время в сети",
        value: extra.d1mplenTrackOffline
    ))
    entries.append(.toggle(
        id: 330,
        key: .typing,
        symbol: "pencil.and.outline",
        color: AyuGramRowColor.blue,
        title: "Печатает / записывает кружок или ГС",
        subtitle: "Уведомлять и сохранять в лог, даже если человек передумал и не отправил",
        value: extra.d1mplenTrackTyping
    ))
    entries.append(.toggle(
        id: 340,
        key: .avatar,
        symbol: "person.crop.circle.fill",
        color: AyuGramRowColor.purple,
        title: "Смена аватарки",
        subtitle: nil,
        value: extra.d1mplenTrackAvatar
    ))
    entries.append(.toggle(
        id: 350,
        key: .profile,
        symbol: "doc.text.fill",
        color: AyuGramRowColor.orange,
        title: "Смена имени, @username и Bio",
        subtitle: nil,
        value: extra.d1mplenTrackProfile
    ))
    entries.append(.footer(
        id: 390,
        section: .alerts,
        text: "Технически Telegram шифрует несохранённый черновик на устройстве собеседника до нажатия «Отправить», а сторонние группы/каналы без вашего участия сервер не раскрывает. Поэтому радар точно фиксирует живые статусы (печатает / записывает / отправляет), смену профиля, историю онлайна и ваши общие группы."
    ))

    return entries
}

public func d1mplenTrackerSettingsScreen(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let obs1 = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        let obs2 = NotificationCenter.default.addObserver(forName: D1mplenTrackerStore.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(obs1)
            NotificationCenter.default.removeObserver(obs2)
        }
    }

    let peerMapSignal: Signal<[PeerId: EnginePeer], NoError> = changes
    |> mapToSignal { _ -> Signal<[PeerId: EnginePeer], NoError> in
        let ids = D1mplenTrackerStore.shared.trackedPeerIds().map(PeerId.init)
        if ids.isEmpty {
            return .single([:])
        }
        return context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
        |> map { dict in
            var result: [PeerId: EnginePeer] = [:]
            for (k, v) in dict {
                if let v {
                    result[k] = v
                }
            }
            return result
        }
    }

    let arguments = D1mplenTrackerListArguments(context: context, perform: { action in
        switch action {
        case .selectContacts:
            let data = context.sharedContext.currentPresentationData.with { $0 }
            let currentIds = D1mplenTrackerStore.shared.trackedPeerIds().map(PeerId.init)
            let picker = context.sharedContext.makeContactMultiselectionController(
                ContactMultiselectionControllerParams(
                    context: context,
                    mode: .chatSelection(.init(
                        title: "Выбор для мониторинга",
                        searchPlaceholder: data.strings.Common_Search,
                        selectedChats: Set(currentIds),
                        additionalCategories: nil,
                        chatListFilters: nil,
                        displayAutoremoveTimeout: false,
                        displayPresence: true,
                        onlyUsers: true,
                        disableChannels: true,
                        disableBots: true
                    )),
                    filters: [.excludeSelf, .excludeBots],
                    alwaysEnabled: true
                )
            )
            picker.navigationPresentation = .modal
            let _ = (picker.result |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak picker] result in
                guard case let .result(peerIds, _) = result else {
                    picker?.dismiss()
                    return
                }
                let selectedPeerIds: [PeerId] = peerIds.compactMap { item in
                    if case let .peer(id) = item,
                       id.namespace == Namespaces.Peer.CloudUser,
                       id != context.account.peerId {
                        return id
                    }
                    return nil
                }
                if selectedPeerIds.isEmpty {
                    D1mplenTrackerStore.shared.setTrackedPeers([])
                    picker?.dismiss()
                    return
                }
                let _ = (context.engine.data.get(EngineDataMap(selectedPeerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
                |> deliverOnMainQueue).startStandalone(next: { [weak picker] peerDict in
                    let mapped: [(peerId: Int64, displayName: String, username: String?)] = selectedPeerIds.map { id in
                        let peer = peerDict[id] ?? nil
                        let title = peer?.debugDisplayTitle ?? "Контакт \(id.toInt64())"
                        return (peerId: id.toInt64(), displayName: title, username: peer?.addressName)
                    }
                    D1mplenTrackerStore.shared.setTrackedPeers(mapped)
                    picker?.dismiss()
                })
            })
            pushImpl?(picker)
        case let .openContact(peerId):
            pushImpl?(d1mplenContactStatsScreen(context: context, peerId: peerId))
        case let .toggle(key, value):
            if value {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
            switch key {
            case .online:
                AyuGramSettings.shared.updateExtra { $0.d1mplenTrackOnline = value }
            case .offline:
                AyuGramSettings.shared.updateExtra { $0.d1mplenTrackOffline = value }
            case .typing:
                AyuGramSettings.shared.updateExtra { $0.d1mplenTrackTyping = value }
            case .avatar:
                AyuGramSettings.shared.updateExtra { $0.d1mplenTrackAvatar = value }
            case .profile:
                AyuGramSettings.shared.updateExtra { $0.d1mplenTrackProfile = value }
            }
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, changes, peerMapSignal)
    |> deliverOnMainQueue
    |> map { data, _, peers -> (ItemListControllerState, (ItemListNodeState, D1mplenTrackerListArguments)) in
        let entries = d1mplenTrackerListEntries(
            extra: AyuGramSettings.shared.extra,
            contacts: D1mplenTrackerStore.shared.allContacts(),
            peers: peers,
            now: Date().timeIntervalSince1970
        )
        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text("Мониторинг и статистика"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(data),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (state, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] target in
        controller?.push(target)
    }
    return controller
}

// MARK: - Per-Contact Detailed Stats Screen

private enum D1mplenStatsSection: Int32 {
    case summary
    case profile
    case queued
    case timeline
    case actions
}

private enum D1mplenStatsAction {
    case openProfile
    case cancelQueued(String)
    case openChat
    case clearStats
    case removeTracking
}

private final class D1mplenStatsArguments {
    let perform: (D1mplenStatsAction) -> Void

    init(perform: @escaping (D1mplenStatsAction) -> Void) {
        self.perform = perform
    }
}

private enum D1mplenStatsEntry: ItemListNodeEntry {
    case header(id: Int, section: D1mplenStatsSection, text: String)
    case metric(id: Int, section: D1mplenStatsSection, symbol: String, color: UIColor, title: String, label: String, clickable: Bool, openProfile: Bool)
    case toggle(id: Int, section: D1mplenStatsSection, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool, onToggle: (Bool) -> Void)
    case queuedRow(id: Int, message: D1mplenQueuedOnlineMessage)
    case eventRow(id: Int, event: D1mplenTrackerEvent)
    case actionRow(id: Int, title: String, destructive: Bool, actionKind: Int32)
    case footer(id: Int, section: D1mplenStatsSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .metric(_, section, _, _, _, _, _, _), let .toggle(_, section, _, _, _, _, _, _), let .footer(_, section, _):
            return section.rawValue
        case .queuedRow:
            return D1mplenStatsSection.queued.rawValue
        case .eventRow:
            return D1mplenStatsSection.timeline.rawValue
        case .actionRow:
            return D1mplenStatsSection.actions.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .metric(id, _, _, _, _, _, _, _),
             let .toggle(id, _, _, _, _, _, _, _),
             let .queuedRow(id, _),
             let .eventRow(id, _),
             let .actionRow(id, _, _, _),
             let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: D1mplenStatsEntry, rhs: D1mplenStatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: D1mplenStatsEntry, rhs: D1mplenStatsEntry) -> Bool {
        if lhs.stableId != rhs.stableId {
            return false
        }
        switch (lhs, rhs) {
        case let (.header(id1, s1, t1), .header(id2, s2, t2)):
            return id1 == id2 && s1 == s2 && t1 == t2
        case let (.metric(id1, s1, sym1, c1, t1, l1, cl1, op1), .metric(id2, s2, sym2, c2, t2, l2, cl2, op2)):
            return id1 == id2 && s1 == s2 && sym1 == sym2 && c1 == c2 && t1 == t2 && l1 == l2 && cl1 == cl2 && op1 == op2
        case let (.toggle(id1, s1, sym1, c1, t1, sub1, v1, _), .toggle(id2, s2, sym2, c2, t2, sub2, v2, _)):
            return id1 == id2 && s1 == s2 && sym1 == sym2 && c1 == c2 && t1 == t2 && sub1 == sub2 && v1 == v2
        case let (.queuedRow(id1, m1), .queuedRow(id2, m2)):
            return id1 == id2 && m1 == m2
        case let (.eventRow(id1, e1), .eventRow(id2, e2)):
            return id1 == id2 && e1 == e2
        case let (.actionRow(id1, t1, d1, a1), .actionRow(id2, t2, d2, a2)):
            return id1 == id2 && t1 == t2 && d1 == d2 && a1 == a2
        case let (.footer(id1, s1, t1), .footer(id2, s2, t2)):
            return id1 == id2 && s1 == s2 && t1 == t2
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! D1mplenStatsArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .metric(_, _, symbol, color, title, label, clickable, openProfile):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon(symbol, color: color),
                title: title,
                enabled: true,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: clickable ? .arrow : .none,
                action: clickable && openProfile ? {
                    args.perform(.openProfile)
                } : nil
            )
        case let .toggle(_, _, symbol, color, title, subtitle, value, onToggle):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon(symbol, color: color),
                title: title,
                text: subtitle,
                value: value,
                enabled: true,
                maximumNumberOfLines: 0,
                sectionId: self.section,
                style: .blocks,
                updated: { val in
                    onToggle(val)
                }
            )
        case let .queuedRow(_, queued):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon("clock.badge.checkmark.fill", color: AyuGramRowColor.teal),
                title: queued.text,
                enabled: true,
                label: "Отменить",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    args.perform(.cancelQueued(queued.id))
                }
            )
        case let .eventRow(_, event):
            let timeText = d1mplenShortTime(event.timestamp)
            let detailSuffix = event.detail.isEmpty ? "" : " · \(event.detail)"
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "\(event.kind.displayEmoji) \(event.kind.displayTitle)\(detailSuffix)",
                enabled: true,
                label: timeText,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .actionRow(_, title, destructive, actionKind):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: destructive ? .destructive : .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    switch actionKind {
                    case 1:
                        args.perform(.openChat)
                    case 2:
                        args.perform(.clearStats)
                    default:
                        args.perform(.removeTracking)
                    }
                }
            )
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func d1mplenContactStatsEntries(
    contact: D1mplenTrackedContact?,
    peer: EnginePeer?,
    commonGroups: Int32?,
    analytics: D1mplenContactAnalytics?,
    queued: [D1mplenQueuedOnlineMessage]
) -> [D1mplenStatsEntry] {
    var entries: [D1mplenStatsEntry] = []

    let statusValue: String
    if let contact, contact.isCurrentlyOnline {
        statusValue = "🟢 В сети"
    } else if let lastSeen = contact?.lastSeenAt {
        statusValue = "Был(а) \(d1mplenShortTime(lastSeen))"
    } else {
        statusValue = "Нет данных"
    }

    entries.append(.header(id: 100, section: .summary, text: "АКТИВНОСТЬ И СТАТИСТИКА"))
    entries.append(.metric(
        id: 110,
        section: .summary,
        symbol: "dot.radiowaves.left.and.right",
        color: contact?.isCurrentlyOnline == true ? AyuGramRowColor.green : AyuGramRowColor.gray,
        title: "Текущий статус",
        label: statusValue,
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 120,
        section: .summary,
        symbol: "sun.max.fill",
        color: AyuGramRowColor.orange,
        title: "В сети сегодня",
        label: analytics.map { D1mplenContactAnalytics.formatDuration($0.todayOnlineSeconds) } ?? "0с",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 130,
        section: .summary,
        symbol: "clock.fill",
        color: AyuGramRowColor.blue,
        title: "Всего за всё время",
        label: analytics.map { D1mplenContactAnalytics.formatDuration($0.totalOnlineSeconds) } ?? "0с",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 140,
        section: .summary,
        symbol: "chart.bar.fill",
        color: AyuGramRowColor.indigo,
        title: "В среднем в день",
        label: analytics.map { D1mplenContactAnalytics.formatDuration($0.averageDailySeconds) } ?? "0с",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 150,
        section: .summary,
        symbol: "repeat",
        color: AyuGramRowColor.teal,
        title: "Сессий / средняя",
        label: analytics.map { "\($0.sessionCount) · \(D1mplenContactAnalytics.formatDuration($0.averageSessionSeconds))" } ?? "0",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 160,
        section: .summary,
        symbol: "sunrise.fill",
        color: AyuGramRowColor.pink,
        title: "Средний первый заход",
        label: analytics?.averageFirstSeenSecondsOfDay.map(D1mplenContactAnalytics.formatTimeOfDay) ?? "—",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 170,
        section: .summary,
        symbol: "sunset.fill",
        color: AyuGramRowColor.purple,
        title: "Средний последний выход",
        label: analytics?.averageLastSeenSecondsOfDay.map(D1mplenContactAnalytics.formatTimeOfDay) ?? "—",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 180,
        section: .summary,
        symbol: "flame.fill",
        color: AyuGramRowColor.red,
        title: "Пиковый час активности",
        label: analytics?.peakHour.map { String(format: "%02d:00–%02d:59", $0, $0) } ?? "—",
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 190,
        section: .summary,
        symbol: "keyboard.fill",
        color: AyuGramRowColor.blue,
        title: "Попыток набора / записи",
        label: "\(analytics?.unsentTypingAttempts ?? 0)",
        clickable: false,
        openProfile: false
    ))

    entries.append(.header(id: 200, section: .profile, text: "ПРОФИЛЬ И ОБЩИЕ ГРУППЫ"))
    let usernameLabel = (peer?.addressName ?? contact?.username).map { "@\($0)" } ?? "нет"
    entries.append(.metric(
        id: 210,
        section: .profile,
        symbol: "at",
        color: AyuGramRowColor.teal,
        title: "Username",
        label: usernameLabel,
        clickable: false,
        openProfile: false
    ))
    let bioLabel = contact?.about ?? "скрыто или пусто"
    entries.append(.metric(
        id: 220,
        section: .profile,
        symbol: "quote.bubble.fill",
        color: AyuGramRowColor.orange,
        title: "Bio",
        label: bioLabel,
        clickable: false,
        openProfile: false
    ))
    entries.append(.metric(
        id: 230,
        section: .profile,
        symbol: "arrow.triangle.2.circlepath",
        color: AyuGramRowColor.purple,
        title: "Изменений профиля в логе",
        label: "\(analytics?.profileChangesCount ?? 0)",
        clickable: false,
        openProfile: false
    ))
    let groupCount = commonGroups ?? contact?.commonGroupsCount
    entries.append(.metric(
        id: 240,
        section: .profile,
        symbol: "person.3.fill",
        color: AyuGramRowColor.green,
        title: "Общие группы (профиль)",
        label: groupCount.map { "\($0)" } ?? "Открыть",
        clickable: peer != nil,
        openProfile: true
    ))

    entries.append(.header(id: 250, section: .profile, text: "ИНДИВИДУАЛЬНЫЕ УВЕДОМЛЕНИЯ"))
    let pOnline = contact?.trackPresence ?? true
    let pTyping = contact?.trackTyping ?? true
    let pVoice = contact?.trackVoiceAndVideo ?? true
    let cPeerId = contact?.peerId ?? 0

    entries.append(.toggle(
        id: 251,
        section: .profile,
        symbol: "bell.badge.fill",
        color: AyuGramRowColor.green,
        title: "Вход и выход из сети",
        subtitle: "Уведомлять при заходе и выходе из онлайна",
        value: pOnline,
        onToggle: { val in
            D1mplenTrackerStore.shared.updateAlertSettings(for: cPeerId, trackPresence: val, trackTyping: pTyping, trackVoiceAndVideo: pVoice)
        }
    ))
    entries.append(.toggle(
        id: 252,
        section: .profile,
        symbol: "pencil.and.outline",
        color: AyuGramRowColor.blue,
        title: "Печатает сообщение",
        subtitle: "Уведомлять при наборе текста (с защитой от спама)",
        value: pTyping,
        onToggle: { val in
            D1mplenTrackerStore.shared.updateAlertSettings(for: cPeerId, trackPresence: pOnline, trackTyping: val, trackVoiceAndVideo: pVoice)
        }
    ))
    entries.append(.toggle(
        id: 253,
        section: .profile,
        symbol: "waveform.circle.fill",
        color: AyuGramRowColor.purple,
        title: "Записывает ГС или кружок",
        subtitle: "Уведомлять при записи голосового сообщения или видео",
        value: pVoice,
        onToggle: { val in
            D1mplenTrackerStore.shared.updateAlertSettings(for: cPeerId, trackPresence: pOnline, trackTyping: pTyping, trackVoiceAndVideo: val)
        }
    ))

    let aiEnabled = contact?.aiAutoReplyEnabled ?? false
    let aiDelay = contact?.aiAutoReplyDelaySeconds ?? 10
    let delayLabel = aiDelay == 0 ? "Сразу (без задержки)" : "\(aiDelay) сек."

    entries.append(.header(id: 280, section: .profile, text: "🤖 PIP AI АВТООТВЕТЧИК ДЛЯ ЭТОГО КОНТАКТА"))
    entries.append(.toggle(
        id: 281,
        section: .profile,
        symbol: "sparkles",
        color: AyuGramRowColor.orange,
        title: "Умный автоответчик от моего имени",
        subtitle: "ИИ читает контекст и отвечает в вашем стиле речи с имитацией набора текста",
        value: aiEnabled,
        onToggle: { val in
            D1mplenTrackerStore.shared.updateAiSettings(for: cPeerId, enabled: val, delaySeconds: aiDelay)
        }
    ))
    entries.append(.toggle(
        id: 282,
        section: .profile,
        symbol: "timer",
        color: AyuGramRowColor.teal,
        title: "Задержка перед ответом",
        subtitle: "Нажмите тумблер для смены: \(delayLabel)",
        value: aiDelay > 0,
        onToggle: { _ in
            let nextDelay: Int32 = aiDelay == 0 ? 5 : (aiDelay == 5 ? 15 : (aiDelay == 15 ? 30 : (aiDelay == 30 ? 60 : 0)))
            D1mplenTrackerStore.shared.updateAiSettings(for: cPeerId, enabled: aiEnabled, delaySeconds: nextDelay)
        }
    ))
    entries.append(.footer(id: 283, section: .profile, text: "Pip AI при входящем сообщении мгновенно включит индикатор «печатает...», выдержит выбранную паузу и отправит живой ответ точно в вашей манере."))

    if !queued.isEmpty {
        entries.append(.header(id: 300, section: .queued, text: "ОЧЕРЕДЬ «ОТПРАВИТЬ ПРИ ВХОДЕ В СЕТЬ»"))
        for (idx, item) in queued.enumerated() {
            entries.append(.queuedRow(id: 310 + idx, message: item))
        }
    }

    entries.append(.header(id: 400, section: .timeline, text: "ПОСЛЕДНИЕ СОБЫТИЯ"))
    let recentEvents = Array((contact?.events ?? []).prefix(25))
    if recentEvents.isEmpty {
        entries.append(.metric(
            id: 410,
            section: .timeline,
            symbol: "tray",
            color: AyuGramRowColor.gray,
            title: "Пока событий не зафиксировано",
            label: "",
            clickable: false,
            openProfile: false
        ))
    } else {
        for (idx, event) in recentEvents.enumerated() {
            entries.append(.eventRow(id: 420 + idx, event: event))
        }
    }

    entries.append(.header(id: 500, section: .actions, text: "УПРАВЛЕНИЕ"))
    entries.append(.actionRow(id: 510, title: "Открыть чат", destructive: false, actionKind: 1))
    entries.append(.actionRow(id: 520, title: "Очистить статистику", destructive: true, actionKind: 2))
    entries.append(.actionRow(id: 530, title: "Убрать из мониторинга", destructive: true, actionKind: 3))

    return entries
}

public func d1mplenContactStatsScreen(context: AccountContext, peerId: PeerId) -> ViewController {
    let rawId = peerId.toInt64()
    let _ = d1mplenRefreshTrackedPeer(account: context.account, peerId: peerId).startStandalone()
    let _ = TelegramEngine(account: context.account).peers.fetchAndUpdateCachedPeerData(peerId: peerId).startStandalone()

    let storeChanges = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let obs = NotificationCenter.default.addObserver(forName: D1mplenTrackerStore.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    let peerSignal = TelegramEngine(account: context.account).data.subscribe(
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
        TelegramEngine.EngineData.Item.Peer.CommonGroupCount(id: peerId)
    )

    var latestPeer: EnginePeer?
    weak var controllerRef: ViewController?

    let arguments = D1mplenStatsArguments(perform: { action in
        switch action {
        case .openProfile:
            guard let peer = latestPeer,
                  let info = context.sharedContext.makePeerInfoController(
                    context: context,
                    updatedPresentationData: nil,
                    peer: peer,
                    mode: .generic,
                    avatarInitiallyExpanded: false,
                    fromChat: false,
                    requestsContext: nil
                  ) else {
                return
            }
            (controllerRef?.navigationController as? NavigationController)?.pushViewController(info)
        case let .cancelQueued(id):
            D1mplenTrackerStore.shared.removeQueuedMessage(id: id)
        case .openChat:
            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peerId, messageId: nil)
        case .clearStats:
            D1mplenTrackerStore.shared.clearStats(for: rawId)
        case .removeTracking:
            D1mplenTrackerStore.shared.removeContact(rawId)
            if let vc = controllerRef {
                (vc.navigationController as? NavigationController)?.filterController(vc, animated: true)
            }
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, storeChanges, peerSignal)
    |> deliverOnMainQueue
    |> map { data, _, peerData -> (ItemListControllerState, (ItemListNodeState, D1mplenStatsArguments)) in
        let (peer, commonGroups) = peerData
        latestPeer = peer
        let contact = D1mplenTrackerStore.shared.contact(for: rawId)
        let now = Date().timeIntervalSince1970
        let analytics = D1mplenTrackerStore.shared.analytics(for: rawId, now: now)
        let queued = D1mplenTrackerStore.shared.queuedMessages(for: rawId)
        let title = peer?.debugDisplayTitle ?? contact?.displayName ?? "Статистика"
        let entries = d1mplenContactStatsEntries(
            contact: contact,
            peer: peer,
            commonGroups: commonGroups,
            analytics: analytics,
            queued: queued
        )
        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(data),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (state, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerRef = controller
    return controller
}
