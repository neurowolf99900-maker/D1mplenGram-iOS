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
    case tracker
    case chatTools
    case notifications
    case notificationTypes
    case backgroundPush
}

private enum D1mplenScreenToggle: Equatable {
    case autoLike
    case tabBarSearch
    case chatMenuEnabled
    case videoToRoundEnabled
    case fakeStatusEnabled
    case massReactionsEnabled
    case textAnimEnabled
    case sendWhenOnlineEnabled
    case selfDestructEnabled
    case cleanMyMessagesEnabled
    case commandsEnabled
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
    case terminatedNotice
}

private enum D1mplenScreenAction: Equatable {
    case openTracker
    case setupBark
    case openCrossRadar
    case openAiChatFinder
}

private final class D1mplenScreenArguments {
    let toggle: (D1mplenScreenToggle, Bool) -> Void
    let action: (D1mplenScreenAction) -> Void

    init(
        toggle: @escaping (D1mplenScreenToggle, Bool) -> Void,
        action: @escaping (D1mplenScreenAction) -> Void
    ) {
        self.toggle = toggle
        self.action = action
    }
}

private enum D1mplenScreenEntry: ItemListNodeEntry {
    case header(id: Int, section: D1mplenScreenSection, text: String)
    case toggle(id: Int, section: D1mplenScreenSection, key: D1mplenScreenToggle, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool)
    case disclosure(id: Int, section: D1mplenScreenSection, action: D1mplenScreenAction, symbol: String, color: UIColor, title: String, label: String)
    case footer(id: Int, section: D1mplenScreenSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _),
             let .footer(_, section, _),
             let .toggle(_, section, _, _, _, _, _, _),
             let .disclosure(_, section, _, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .footer(id, _, _),
             let .toggle(id, _, _, _, _, _, _, _),
             let .disclosure(id, _, _, _, _, _, _):
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
        case let .disclosure(_, _, action, symbol, color, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: color), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.action(action)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func d1mplenScreenEntries(
    extra: AyuGramExtraSettings,
    tabBarSearchEnabled: Bool,
    trackedCount: Int,
    barkConfigured: Bool
) -> [D1mplenScreenEntry] {
    var entries: [D1mplenScreenEntry] = []

    entries.append(.header(id: 100, section: .features, text: "ФУНКЦИИ PIP: АВТОМАТИЗАЦИЯ"))
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

    entries.append(.header(id: 150, section: .tracker, text: "ФУНКЦИИ PIP 2: РАДАР & ДЕТЕКТИВ"))
    entries.append(.disclosure(
        id: 160,
        section: .tracker,
        action: .openTracker,
        symbol: "antenna.radiowaves.left.and.right",
        color: AyuGramRowColor.green,
        title: "Мониторинг контактов и статистика",
        label: trackedCount > 0 ? "\(trackedCount)" : "Выкл"
    ))
    entries.append(.disclosure(
        id: 162,
        section: .tracker,
        action: .openCrossRadar,
        symbol: "person.2.wave.2.fill",
        color: AyuGramRowColor.indigo,
        title: "Синхронный радар онлайна",
        label: "Cross-Radar"
    ))
    entries.append(.disclosure(
        id: 164,
        section: .tracker,
        action: .openAiChatFinder,
        symbol: "brain.head.profile",
        color: AyuGramRowColor.purple,
        title: "ИИ-Поиск чата по смыслу",
        label: "Llama 3.3"
    ))
    entries.append(.footer(
        id: 170,
        section: .tracker,
        text: "Отслеживание онлайна/офлайна, набора текста и записи кружков/ГС, смены аватарки/имени/Bio и подробная статистика активности по выбранным людям."
    ))

    entries.append(.header(id: 180, section: .chatTools, text: "ФУНКЦИИ PIP 3: СПЕЦ-ИНСТРУМЕНТЫ ЧАТА"))
    entries.append(.toggle(
        id: 181,
        section: .chatTools,
        key: .chatMenuEnabled,
        symbol: "bolt.circle.fill",
        color: AyuGramRowColor.orange,
        title: "Кнопка «⚡ D1mplen» в чате",
        subtitle: "Быстрая шторка с инструментами и кнопкой «В мониторинг»",
        value: extra.d1mplenChatMenuEnabled
    ))
    entries.append(.toggle(
        id: 182,
        section: .chatTools,
        key: .videoToRoundEnabled,
        symbol: "record.circle",
        color: AyuGramRowColor.purple,
        title: "Видео в кружочек (из чатов)",
        subtitle: "Пункт «Отправить как кружок» в меню любого видео в чате",
        value: extra.d1mplenVideoToRoundEnabled
    ))
    entries.append(.toggle(
        id: 183,
        section: .chatTools,
        key: .fakeStatusEnabled,
        symbol: "theatermasks.fill",
        color: AyuGramRowColor.indigo,
        title: "Фейк-статусы с таймером",
        subtitle: "Печатает / кружок / голосовое на заданное время без сообщений",
        value: extra.d1mplenFakeStatusEnabled
    ))
    entries.append(.toggle(
        id: 184,
        section: .chatTools,
        key: .massReactionsEnabled,
        symbol: "heart.fill",
        color: AyuGramRowColor.red,
        title: "Масс-реакции",
        subtitle: "Авто-реакции на последние N сообщений (5–100+ или своё число)",
        value: extra.d1mplenMassReactionsEnabled
    ))
    entries.append(.toggle(
        id: 185,
        section: .chatTools,
        key: .textAnimEnabled,
        symbol: "sparkles",
        color: AyuGramRowColor.pink,
        title: "Анимации отправки текста",
        subtitle: "Печатная машинка по словам, % загрузки, сердцебиение и стили",
        value: extra.d1mplenTextAnimEnabled
    ))
    entries.append(.toggle(
        id: 186,
        section: .chatTools,
        key: .sendWhenOnlineEnabled,
        symbol: "clock.badge.checkmark.fill",
        color: AyuGramRowColor.teal,
        title: "Отправка при входе в сеть",
        subtitle: "Очередь сообщений — улетят в секунду, когда человек зайдёт онлайн",
        value: extra.d1mplenSendWhenOnlineEnabled
    ))
    entries.append(.toggle(
        id: 187,
        section: .chatTools,
        key: .selfDestructEnabled,
        symbol: "timer",
        color: AyuGramRowColor.orange,
        title: "Таймер самоуничтожения",
        subtitle: "Автоудаление вашего сообщения у обоих через заданные секунды",
        value: extra.d1mplenSelfDestructEnabled
    ))
    entries.append(.toggle(
        id: 188,
        section: .chatTools,
        key: .cleanMyMessagesEnabled,
        symbol: "broom.fill",
        color: AyuGramRowColor.red,
        title: "Очистка последних сообщений",
        subtitle: "Быстрое удаление ваших последних N сообщений у всех",
        value: extra.d1mplenCleanMyMessagesEnabled
    ))
    entries.append(.toggle(
        id: 189,
        section: .chatTools,
        key: .commandsEnabled,
        symbol: "terminal.fill",
        color: AyuGramRowColor.blue,
        title: "Локальные .-команды",
        subtitle: "Перехват до отправки: собеседник никогда не увидит саму команду",
        value: extra.d1mplenCommandsEnabled
    ))
    entries.append(.footer(
        id: 199,
        section: .chatTools,
        text: "Команды начинаются с точки и не отправляются в чат: .menu, .fake type/round/voice [сек], .like [число] [эмодзи], .type [текст], .timer [сек] [текст], .online [текст], .clean [число]."
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

    entries.append(.header(id: 400, section: .backgroundPush, text: "ФОН И PUSH-УВЕДОМЛЕНИЯ"))
    entries.append(.disclosure(
        id: 410,
        section: .backgroundPush,
        action: .setupBark,
        symbol: "iphone.radiowaves.left.and.right",
        color: barkConfigured ? AyuGramRowColor.green : AyuGramRowColor.orange,
        title: "Настроить Bark Push (фоновые пуши)",
        label: barkConfigured ? "Вкл" : "Выкл"
    ))
    entries.append(.toggle(
        id: 420,
        section: .backgroundPush,
        key: .terminatedNotice,
        symbol: "bell.slash.fill",
        color: AyuGramRowColor.gray,
        title: "Предупреждение при закрытии приложения",
        subtitle: "Уведомлять при выгрузке из памяти («уведомления приостановлены»)",
        value: extra.d1mplenTerminatedNotice
    ))
    entries.append(.footer(
        id: 430,
        section: .backgroundPush,
        text: "Когда D1mplenGram полностью выгружен из памяти (свайп вверх), iOS останавливает локальные процессы. Подключите бесплатное приложение Bark, чтобы получать пуши о сообщениях даже при закрытом приложении, либо включите «Фоновую службу» в настройках AyuGram → Ghost и приватность."
    ))

    return entries
}

public func d1mplenGramSettingsScreen(context: AccountContext) -> ViewController {
    weak var controllerRef: ViewController?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer1 = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        let observer2 = NotificationCenter.default.addObserver(forName: D1mplenTrackerStore.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
        }
    }
    let arguments = D1mplenScreenArguments(toggle: { key, value in
        switch key {
        case .autoLike:
            AyuGramSettings.shared.updateExtra { $0.d1mplenAutoLike = value }
        case .tabBarSearch:
            SGSimpleSettings.shared.tabBarSearchEnabled = value
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: AyuGramSettings.shared)
        case .chatMenuEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenChatMenuEnabled = value }
        case .videoToRoundEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenVideoToRoundEnabled = value }
        case .fakeStatusEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenFakeStatusEnabled = value }
        case .massReactionsEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenMassReactionsEnabled = value }
        case .textAnimEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenTextAnimEnabled = value }
        case .sendWhenOnlineEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenSendWhenOnlineEnabled = value }
        case .selfDestructEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenSelfDestructEnabled = value }
        case .cleanMyMessagesEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenCleanMyMessagesEnabled = value }
        case .commandsEnabled:
            AyuGramSettings.shared.updateExtra { $0.d1mplenCommandsEnabled = value }
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
        case .terminatedNotice:
            AyuGramSettings.shared.updateExtra { $0.d1mplenTerminatedNotice = value }
        }
    }, action: { action in
        switch action {
        case .openTracker:
            controllerRef?.push(d1mplenTrackerSettingsScreen(context: context))
        case .openCrossRadar:
            controllerRef?.push(pipCrossRadarScreen(context: context))
        case .openAiChatFinder:
            controllerRef?.push(pipSemanticChatFinderController(context: context))
        case .setupBark:
            ayuGramSetUpBark(context: context, present: { viewController in
                controllerRef?.present(viewController, in: .window(.root))
            })
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, D1mplenScreenArguments)) in
        let barkConfigured = !(AyuGramPushRelay.barkKey ?? "").isEmpty
        let entries = d1mplenScreenEntries(
            extra: AyuGramSettings.shared.extra,
            tabBarSearchEnabled: SGSimpleSettings.shared.tabBarSearchEnabled,
            trackedCount: D1mplenTrackerStore.shared.trackedPeerIds().count,
            barkConfigured: barkConfigured
        )
        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text("Pip Tools"),
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
