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
    case pickAutoLikeEmoji
    case pickButtonSize
    case setupAiApiKey
}

private enum D1mplenScreenSlider: Equatable {
    case chatButtonSize
    case chatButtonAlpha
}

private final class D1mplenScreenArguments {
    let toggle: (D1mplenScreenToggle, Bool) -> Void
    let action: (D1mplenScreenAction) -> Void
    let updateSlider: (D1mplenScreenSlider, Int32) -> Void

    init(
        toggle: @escaping (D1mplenScreenToggle, Bool) -> Void,
        action: @escaping (D1mplenScreenAction) -> Void,
        updateSlider: @escaping (D1mplenScreenSlider, Int32) -> Void
    ) {
        self.toggle = toggle
        self.action = action
        self.updateSlider = updateSlider
    }
}

private enum D1mplenScreenEntry: ItemListNodeEntry {
    case header(id: Int, section: D1mplenScreenSection, text: String)
    case toggle(id: Int, section: D1mplenScreenSection, key: D1mplenScreenToggle, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool)
    case disclosure(id: Int, section: D1mplenScreenSection, action: D1mplenScreenAction, symbol: String, color: UIColor, title: String, label: String)
    case slider(id: Int, section: D1mplenScreenSection, setting: D1mplenScreenSlider, value: Int32)
    case footer(id: Int, section: D1mplenScreenSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _),
             let .footer(_, section, _),
             let .toggle(_, section, _, _, _, _, _, _),
             let .disclosure(_, section, _, _, _, _, _),
             let .slider(_, section, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .footer(id, _, _),
             let .toggle(id, _, _, _, _, _, _, _),
             let .disclosure(id, _, _, _, _, _, _),
             let .slider(id, _, _, _):
            return id
        }
    }

    static func ==(lhs: D1mplenScreenEntry, rhs: D1mplenScreenEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lhsId, lhsSection, lhsText), .header(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        case let (.toggle(lhsId, lhsSection, lhsKey, _, _, lhsTitle, lhsSubtitle, lhsValue),
                  .toggle(rhsId, rhsSection, rhsKey, _, _, rhsTitle, rhsSubtitle, rhsValue)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsKey == rhsKey && lhsTitle == rhsTitle && lhsSubtitle == rhsSubtitle && lhsValue == rhsValue
        case let (.disclosure(lhsId, lhsSection, lhsAction, _, _, lhsTitle, lhsLabel),
                  .disclosure(rhsId, rhsSection, rhsAction, _, _, rhsTitle, rhsLabel)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsAction == rhsAction && lhsTitle == rhsTitle && lhsLabel == rhsLabel
        case let (.slider(lhsId, lhsSection, lhsSetting, lhsValue),
                  .slider(rhsId, rhsSection, rhsSetting, rhsValue)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsSetting == rhsSetting && lhsValue == rhsValue
        case let (.footer(lhsId, lhsSection, lhsText), .footer(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        default:
            return false
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
        case let .slider(_, _, setting, value):
            return SliderPercentageItem(theme: presentationData.theme, strings: presentationData.strings, value: value, sectionId: self.section, updated: { val in
                arguments.updateSlider(setting, val)
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
    let currentAutoEmoji = extra.pipAutoLikeEmoji.isEmpty ? "👍" : extra.pipAutoLikeEmoji
    entries.append(.toggle(
        id: 110,
        section: .features,
        key: .autoLike,
        symbol: "hand.thumbsup.fill",
        color: AyuGramRowColor.pink,
        title: "Авто-лайк входящих",
        subtitle: "Ставить реакцию \(currentAutoEmoji) на каждое входящее сообщение от пользователей",
        value: extra.d1mplenAutoLike
    ))
    entries.append(.disclosure(
        id: 115,
        section: .features,
        action: .pickAutoLikeEmoji,
        symbol: "face.smiling.fill",
        color: AyuGramRowColor.orange,
        title: "Эмодзи для авто-лайка",
        label: currentAutoEmoji
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
        text: "Авто-лайк срабатывает только в личных чатах на входящие сообщения от людей (боты и каналы игнорируются). Вы можете выбрать абсолютно любой эмодзи для реакции."
    ))

    entries.append(.header(id: 150, section: .tracker, text: "ФУНКЦИИ PIP 2: РАДАР & НЕЙРОСЕТИ"))
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
        symbol: "crown.fill",
        color: AyuGramRowColor.orange,
        title: "Синхронный радар онлайна",
        label: "Cross-Radar"
    ))
    let aiProviderTitle: String
    switch extra.pipAiProvider {
    case 1: aiProviderTitle = "OpenAI GPT-4o"
    case 2: aiProviderTitle = "Google Gemini"
    case 3: aiProviderTitle = "Groq Llama"
    default: aiProviderTitle = "Llama 3.3 Free"
    }
    entries.append(.disclosure(
        id: 164,
        section: .tracker,
        action: .openAiChatFinder,
        symbol: "brain.head.profile",
        color: AyuGramRowColor.purple,
        title: "ИИ-Поиск чата по смыслу",
        label: aiProviderTitle
    ))
    entries.append(.disclosure(
        id: 166,
        section: .tracker,
        action: .setupAiApiKey,
        symbol: "key.fill",
        color: AyuGramRowColor.indigo,
        title: "Свой API-ключ ИИ",
        label: extra.pipAiApiKey.isEmpty ? "Не задан (Free)" : "Установлен ✅"
    ))
    entries.append(.footer(
        id: 170,
        section: .tracker,
        text: "Отслеживание онлайна/офлайна, набора текста и записи кружков/ГС, смены аватарки/имени/Bio и подробная статистика активности по выбранным людям."
    ))

    entries.append(.header(id: 180, section: .chatTools, text: "ФУНКЦИИ PIP 3: ПЛАВАЮЩАЯ КНОПКА & СПЕЦ-ИНСТРУМЕНТЫ"))
    entries.append(.toggle(
        id: 181,
        section: .chatTools,
        key: .chatMenuEnabled,
        symbol: "crown.fill",
        color: AyuGramRowColor.orange,
        title: "Плавающая кнопка Pip в чате",
        subtitle: "Быстрое меню инструментов и мониторинга прямо в диалоге",
        value: extra.d1mplenChatMenuEnabled && extra.pipChatButtonEnabled
    ))
    entries.append(.header(id: 1814, section: .chatTools, text: "РАЗМЕР ЗНАЧКА КОРОНЫ В ЧАТЕ (35% — 150%)"))
    entries.append(.slider(id: 1815, section: .chatTools, setting: .chatButtonSize, value: extra.pipChatButtonSizePercent))
    entries.append(.header(id: 1816, section: .chatTools, text: "ПРОЗРАЧНОСТЬ ЗНАЧКА КОРОНЫ (0% — 100%)"))
    entries.append(.slider(id: 1817, section: .chatTools, setting: .chatButtonAlpha, value: extra.pipChatButtonAlphaPercent))
    entries.append(.footer(id: 1818, section: .chatTools, text: "Плавно настраивайте размер и прозрачность значка Pip ползунками под ваш вкус. При 0% значок становится полностью невидимым."))
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
        text: "Когда Pip полностью выгружен из памяти (свайп вверх), iOS останавливает локальные процессы. Подключите бесплатное приложение Bark, чтобы получать пуши о сообщениях даже при закрытом приложении, либо включите «Фоновую службу» в настройках Pip → Стелс и приватность."
    ))

    return entries
}

private func presentInputPrompt(
    context: AccountContext,
    title: String,
    initialValue: String,
    placeholder: String,
    completion: @escaping (String) -> Void
) {
    let strings = context.sharedContext.currentPresentationData.with { $0.strings }
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addTextField { field in
        field.text = initialValue
        field.placeholder = placeholder
    }
    alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: nil))
    alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default, handler: { [weak alert] _ in
        let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            completion(text)
        }
    }))
    context.sharedContext.mainWindow?.presentNative(alert)
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
        case .pickAutoLikeEmoji:
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Выберите эмодзи для авто-лайка")]
            for emoji in ["👍", "❤️", "🔥", "🤡", "⚡", "👑", "😍", "🎉", "💩"] {
                items.append(ActionSheetButtonItem(title: "\(emoji)  \(emoji)", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    AyuGramSettings.shared.updateExtra { $0.pipAutoLikeEmoji = emoji }
                }))
            }
            items.append(ActionSheetButtonItem(title: "✏️ Ввести свой эмодзи…", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                presentInputPrompt(
                    context: context,
                    title: "Введите эмодзи для авто-лайка:",
                    initialValue: AyuGramSettings.shared.extra.pipAutoLikeEmoji,
                    placeholder: "Эмодзи",
                    completion: { value in
                        AyuGramSettings.shared.updateExtra { $0.pipAutoLikeEmoji = value }
                    }
                )
            }))
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controllerRef?.present(sheet, in: .window(.root))
        case .pickButtonSize:
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Размер плавающей кнопки Pip в чатах")]
            items.append(ActionSheetButtonItem(title: "Маленький (34 pt)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipChatButtonSize = 0 }
            }))
            items.append(ActionSheetButtonItem(title: "Средний (40 pt - стандарт)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipChatButtonSize = 1 }
            }))
            items.append(ActionSheetButtonItem(title: "Большой (48 pt)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipChatButtonSize = 2 }
            }))
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controllerRef?.present(sheet, in: .window(.root))
        case .setupAiApiKey:
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Провайдер и API-Ключ ИИ")]
            items.append(ActionSheetButtonItem(title: "✨ Бесплатный Llama 3.3 70B (без ключа)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipAiProvider = 0; $0.pipAiApiKey = "" }
            }))
            items.append(ActionSheetButtonItem(title: "🟢 OpenAI (GPT-4o / GPT-4o-mini)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipAiProvider = 1 }
                presentInputPrompt(
                    context: context,
                    title: "API-ключ OpenAI (sk-...):",
                    initialValue: AyuGramSettings.shared.extra.pipAiApiKey,
                    placeholder: "sk-...",
                    completion: { value in
                        AyuGramSettings.shared.updateExtra { $0.pipAiApiKey = value }
                    }
                )
            }))
            items.append(ActionSheetButtonItem(title: "🔵 Google Gemini (Gemini 2.0 Flash)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipAiProvider = 2 }
                presentInputPrompt(
                    context: context,
                    title: "API-ключ Google Gemini:",
                    initialValue: AyuGramSettings.shared.extra.pipAiApiKey,
                    placeholder: "AIza...",
                    completion: { value in
                        AyuGramSettings.shared.updateExtra { $0.pipAiApiKey = value }
                    }
                )
            }))
            items.append(ActionSheetButtonItem(title: "⚡ Groq (Llama 3.3 Ultra-Fast)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.pipAiProvider = 3 }
                presentInputPrompt(
                    context: context,
                    title: "API-ключ Groq (gsk_...):",
                    initialValue: AyuGramSettings.shared.extra.pipAiApiKey,
                    placeholder: "gsk_...",
                    completion: { value in
                        AyuGramSettings.shared.updateExtra { $0.pipAiApiKey = value }
                    }
                )
            }))
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controllerRef?.present(sheet, in: .window(.root))
        }
    }, updateSlider: { setting, value in
        switch setting {
        case .chatButtonSize:
            AyuGramSettings.shared.updateExtra { $0.pipChatButtonSizePercent = value }
        case .chatButtonAlpha:
            AyuGramSettings.shared.updateExtra { $0.pipChatButtonAlphaPercent = value }
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let barkConfigured = !(AyuGramPushRelay.barkKey ?? "").isEmpty
        let entries = d1mplenScreenEntries(
            extra: AyuGramSettings.shared.extra,
            tabBarSearchEnabled: SGSimpleSettings.shared.tabBarSearchEnabled,
            trackedCount: D1mplenTrackerStore.shared.trackedPeerIds().count,
            barkConfigured: barkConfigured
        )
        let leftButton = ItemListNavigationButton(
            content: .text(data.strings.Common_Back),
            style: .regular,
            enabled: true,
            action: { [weak controllerRef] in
                if let nav = controllerRef?.navigationController as? NavigationController {
                    let _ = nav.popViewController(animated: true)
                } else {
                    controllerRef?.dismiss()
                }
            }
        )
        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text("Pip Tools"),
            leftNavigationButton: leftButton,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(data),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (state, (listState, arguments as Any))
    }
    let controller = ItemListController(context: context, state: signal)
    controllerRef = controller
    return controller
}
