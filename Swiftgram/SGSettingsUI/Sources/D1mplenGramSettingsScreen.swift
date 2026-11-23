import Foundation
import UIKit
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
}

private enum D1mplenScreenToggle: Equatable {
    case autoLike
    case tabBarSearch
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
        text: "Авто-лайк срабатывает только в личных чатах на входящие сообщения от людей (боты и каналы игнорируются). Кнопка поиска (лупа) в правом нижнем углу обновляется сразу при возврате в чаты."
    ))

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
