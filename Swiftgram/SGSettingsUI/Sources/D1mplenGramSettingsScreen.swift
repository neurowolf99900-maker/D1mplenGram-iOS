import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGSimpleSettings

private enum D1mplenScreenSection: Int32 {
    case features
    case notifications
    case notificationTypes
}

private enum D1mplenScreenToggle: Equatable {
    case autoLike
    case tabBarSearch
    case notifyEnabled
    case notifyDeletes
    case notifyEdits
    case notifyText
    case notifyRoundVideo
    case notifyVoice
    case notifyPhoto
    case notifyVideo
    case notifyStickerGif
    case notifyOther
}

private final class D1mplenScreenArguments {
    let toggle: (D1mplenScreenToggle, Bool) -> Void

    init(toggle: @escaping (D1mplenScreenToggle, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum D1mplenScreenEntry: ItemListNodeEntry {
    case header(id: Int, section: D1mplenScreenSection, text: String)
    case toggle(id: Int, section: D1mplenScreenSection, key: D1mplenScreenToggle, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool)
    case footer(id: Int, section: D1mplenScreenSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _, _, _):
            return id
        }
    }

    static func <(lhs: D1mplenScreenEntry, rhs: D1mplenScreenEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! D1mplenScreenArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, key, symbol, color, title, subtitle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: color), title: title, text: subtitle, value: value, enabled: true, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func d1mplenScreenEntries(extra: AyuGramExtraSettings, tabBarSearchEnabled: Bool) -> [D1mplenScreenEntry] {
    var entries: [D1mplenScreenEntry] = []

    entries.append(.header(id: 100, section: .features, text: "D1MPLENGRAM"))
    entries.append(.toggle(
        id: 110,
        section: .features,
        key: .autoLike,
        symbol: "hand.thumbsup.fill",
        color: AyuGramRowColor.pink,
        title: "Авто-лайк входящих",
        subtitle: "Ставить 👍 на каждое входящее сообщение от пользователей",
        value: extra.d1mplenAutoLike
    ))
    entries.append(.toggle(
        id: 120,
        section: .features,
        key: .tabBarSearch,
        symbol: "magnifyingglass",
        color: AyuGramRowColor.blue,
        title: "Кнопка поиска (лупа)",
        subtitle: "Круглая кнопка поиска в правом нижнем углу панели вкладок",
        value: tabBarSearchEnabled
    ))
    entries.append(.footer(
        id: 130,
        section: .features,
        text: "Авто-лайк срабатывает только в личных чатах на входящие сообщения от людей (боты и каналы игнорируются). Кнопка поиска (лупа) остаётся видимой на всех вкладках, включая Настройки."
    ))

    entries.append(.header(id: 200, section: .notifications, text: "УВЕДОМЛЕНИЯ (ЛИЧНЫЕ ЧАТЫ)"))
    entries.append(.toggle(
        id: 210,
        section: .notifications,
        key: .notifyEnabled,
        symbol: "bell.badge.fill",
        color: AyuGramRowColor.orange,
        title: "Уведомления об удалениях и изменениях",
        subtitle: "Показывать в ЛС, кто, что и когда удалил или изменил",
        value: extra.d1mplenNotifyEnabled
    ))
    if extra.d1mplenNotifyEnabled {
        entries.append(.toggle(
            id: 220,
            section: .notifications,
            key: .notifyDeletes,
            symbol: "trash.fill",
            color: AyuGramRowColor.red,
            title: "Удаления сообщений",
            subtitle: nil,
            value: extra.d1mplenNotifyDeletes
        ))
        entries.append(.toggle(
            id: 230,
            section: .notifications,
            key: .notifyEdits,
            symbol: "pencil",
            color: AyuGramRowColor.orange,
            title: "Изменения сообщений",
            subtitle: nil,
            value: extra.d1mplenNotifyEdits
        ))

        entries.append(.header(id: 300, section: .notificationTypes, text: "ТИПЫ СООБЩЕНИЙ"))
        entries.append(.toggle(
            id: 310,
            section: .notificationTypes,
            key: .notifyText,
            symbol: "text.bubble.fill",
            color: AyuGramRowColor.blue,
            title: "Текст",
            subtitle: nil,
            value: extra.d1mplenNotifyText
        ))
        entries.append(.toggle(
            id: 320,
            section: .notificationTypes,
            key: .notifyRoundVideo,
            symbol: "record.circle.fill",
            color: AyuGramRowColor.purple,
            title: "Кружки (видеосообщения)",
            subtitle: nil,
            value: extra.d1mplenNotifyRoundVideo
        ))
        entries.append(.toggle(
            id: 330,
            section: .notificationTypes,
            key: .notifyVoice,
            symbol: "waveform",
            color: AyuGramRowColor.teal,
            title: "Голосовые сообщения",
            subtitle: nil,
            value: extra.d1mplenNotifyVoice
        ))
        entries.append(.toggle(
            id: 340,
            section: .notificationTypes,
            key: .notifyPhoto,
            symbol: "photo.fill",
            color: AyuGramRowColor.green,
            title: "Фото",
            subtitle: nil,
            value: extra.d1mplenNotifyPhoto
        ))
        entries.append(.toggle(
            id: 350,
            section: .notificationTypes,
            key: .notifyVideo,
            symbol: "video.fill",
            color: AyuGramRowColor.indigo,
            title: "Видео",
            subtitle: nil,
            value: extra.d1mplenNotifyVideo
        ))
        entries.append(.toggle(
            id: 360,
            section: .notificationTypes,
            key: .notifyStickerGif,
            symbol: "face.smiling.fill",
            color: AyuGramRowColor.orange,
            title: "Стикеры и GIF",
            subtitle: nil,
            value: extra.d1mplenNotifyStickerGif
        ))
        entries.append(.toggle(
            id: 370,
            section: .notificationTypes,
            key: .notifyOther,
            symbol: "doc.fill",
            color: AyuGramRowColor.gray,
            title: "Файлы и прочее",
            subtitle: nil,
            value: extra.d1mplenNotifyOther
        ))
        entries.append(.footer(
            id: 380,
            section: .notificationTypes,
            text: "Уведомления приходят только для личных чатов с пользователями (боты, каналы и Избранное игнорируются). Показывается имя, тип/текст сообщения и точное время. Нажатие откроет нужный чат."
        ))
    } else {
        entries.append(.footer(
            id: 240,
            section: .notifications,
            text: "Включите, чтобы получать уведомления об удалении или редактировании текста, кружков, голосовых и медиа в личных чатах."
        ))
    }

    return entries
}

public func d1mplenGramSettingsScreen(context: AccountContext) -> ViewController {
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let arguments = D1mplenScreenArguments(toggle: { key, value in
        switch key {
        case .autoLike:
            AyuGramSettings.shared.updateExtra { $0.d1mplenAutoLike = value }
        case .tabBarSearch:
            SGSimpleSettings.shared.tabBarSearchEnabled = value
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: AyuGramSettings.shared)
        case .notifyEnabled:
            if value {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyEnabled = value }
        case .notifyDeletes:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyDeletes = value }
        case .notifyEdits:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyEdits = value }
        case .notifyText:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyText = value }
        case .notifyRoundVideo:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyRoundVideo = value }
        case .notifyVoice:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyVoice = value }
        case .notifyPhoto:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyPhoto = value }
        case .notifyVideo:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyVideo = value }
        case .notifyStickerGif:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyStickerGif = value }
        case .notifyOther:
            AyuGramSettings.shared.updateExtra { $0.d1mplenNotifyOther = value }
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, D1mplenScreenArguments)) in
        let entries = d1mplenScreenEntries(
            extra: AyuGramSettings.shared.extra,
            tabBarSearchEnabled: SGSimpleSettings.shared.tabBarSearchEnabled
        )
        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text("D1mplenGram"),
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
    return ItemListController(context: context, state: signal)
}
