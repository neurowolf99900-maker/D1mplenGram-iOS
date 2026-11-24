import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGSimpleSettings

private enum PipCrossRadarSection: Int32 {
    case targets
    case metrics
    case log
}

private struct PipOverlapSession: Equatable {
    let start: Double
    let end: Double
    let duration: Double
}

private enum PipCrossRadarEntry: ItemListNodeEntry {
    case header(id: Int, section: PipCrossRadarSection, text: String)
    case contactPicker(id: Int, slot: Int, name: String, isSelected: Bool)
    case metric(id: Int, symbol: String, color: UIColor, title: String, value: String)
    case overlapItem(id: Int, dateText: String, durationText: String)
    case empty(id: Int, text: String)
    case footer(id: Int, section: PipCrossRadarSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _),
             let .footer(_, section, _):
            return section.rawValue
        case .contactPicker:
            return PipCrossRadarSection.targets.rawValue
        case .metric:
            return PipCrossRadarSection.metrics.rawValue
        case .overlapItem, .empty:
            return PipCrossRadarSection.log.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .contactPicker(id, _, _, _),
             let .metric(id, _, _, _, _),
             let .overlapItem(id, _, _),
             let .empty(id, _),
             let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: PipCrossRadarEntry, rhs: PipCrossRadarEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PipCrossRadarArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .contactPicker(_, slot, name, isSelected):
            let icon = isSelected ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus"
            let color = slot == 1 ? AyuGramRowColor.blue : AyuGramRowColor.purple
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon(icon, color: color),
                title: "Объект \(slot)",
                label: name,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.pickContact(slot)
                }
            )
        case let .metric(_, symbol, color, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon(symbol, color: color),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {}
            )
        case let .overlapItem(_, dateText, durationText):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: ayuGramRowIcon("bolt.horizontal.fill", color: AyuGramRowColor.green),
                title: dateText,
                label: durationText,
                sectionId: self.section,
                style: .blocks,
                action: {}
            )
        case let .empty(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class PipCrossRadarArguments {
    let pickContact: (Int) -> Void

    init(pickContact: @escaping (Int) -> Void) {
        self.pickContact = pickContact
    }
}

private struct PipCrossRadarState: Equatable {
    var peerId1: Int64?
    var peerId2: Int64?
}

public func pipCrossRadarScreen(context: AccountContext) -> ViewController {
    let stateValue = ValuePromise<PipCrossRadarState>(PipCrossRadarState(), ignoreRepeated: true)
    let stateRef = Atomic<PipCrossRadarState>(value: PipCrossRadarState())

    let updateState: ((inout PipCrossRadarState) -> Void) -> Void = { f in
        stateValue.set(stateRef.modify { current in
            var copy = current
            f(&copy)
            return copy
        })
    }

    // Auto-select first two tracked contacts by default if available
    let initialTracked = D1mplenTrackerStore.shared.trackedPeerIds()
    if initialTracked.count >= 2 {
        updateState {
            $0.peerId1 = initialTracked[0]
            $0.peerId2 = initialTracked[1]
        }
    } else if initialTracked.count == 1 {
        updateState {
            $0.peerId1 = initialTracked[0]
        }
    }

    weak var controllerRef: ViewController?

    let arguments = PipCrossRadarArguments(
        pickContact: { slot in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let tracked = D1mplenTrackerStore.shared.trackedPeerIds()
            guard !tracked.isEmpty else {
                let alert = textAlertController(
                    context: context,
                    title: "Радар пуст",
                    text: "Сначала добавьте людей в мониторинг через профиль контакта (⚡ Отслеживать в Pip).",
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                )
                controllerRef?.present(alert, in: .window(.root))
                return
            }

            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            items.append(ActionSheetTextItem(title: "Выберите Объект \(slot)"))
            for rawId in tracked {
                let name = D1mplenTrackerStore.shared.displayName(for: rawId)
                items.append(ActionSheetButtonItem(title: name, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    updateState { state in
                        if slot == 1 {
                            state.peerId1 = rawId
                        } else {
                            state.peerId2 = rawId
                        }
                    }
                }))
            }
            items.append(ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            }))
            sheet.setItemGroups([ActionSheetItemGroup(items: items)])
            controllerRef?.present(sheet, in: .window(.root))
        }
    )

    let changes = Signal<Int, NoError> { subscriber in
        let obs = NotificationCenter.default.addObserver(forName: D1mplenTrackerStore.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> = combineLatest(context.sharedContext.presentationData, stateValue.get(), changes)
    |> deliverOnMainQueue
    |> map { presentationData, state, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [PipCrossRadarEntry] = []

        let name1 = state.peerId1.map { D1mplenTrackerStore.shared.displayName(for: $0) } ?? "Нажмите для выбора"
        let name2 = state.peerId2.map { D1mplenTrackerStore.shared.displayName(for: $0) } ?? "Нажмите для выбора"

        entries.append(.header(id: 100, section: .targets, text: "ЦЕЛИ ДЛЯ ПЕРЕКРЕСТНОГО АНАЛИЗА"))
        entries.append(.contactPicker(id: 110, slot: 1, name: name1, isSelected: state.peerId1 != nil))
        entries.append(.contactPicker(id: 120, slot: 2, name: name2, isSelected: state.peerId2 != nil))
        entries.append(.footer(id: 130, section: .targets, text: "Шпионский радар сравнивает точные таймкоды заходов обоих людей и рассчитывает вероятность их активного личного диалога."))

        if let id1 = state.peerId1, let id2 = state.peerId2, id1 != id2 {
            let sessions1 = D1mplenTrackerStore.shared.profile(for: id1)?.sessions ?? []
            let sessions2 = D1mplenTrackerStore.shared.profile(for: id2)?.sessions ?? []

            var overlaps: [PipOverlapSession] = []
            let now = Date().timeIntervalSince1970

            for s1 in sessions1 {
                for s2 in sessions2 {
                    let start = max(s1.start, s2.start)
                    let end = min(s1.end ?? now, s2.end ?? now)
                    let duration = end - start
                    if duration >= 15.0 {
                        overlaps.append(PipOverlapSession(start: start, end: end, duration: duration))
                    }
                }
            }

            overlaps.sort(by: { $0.start > $1.start })

            let totalOverlapSec = overlaps.reduce(0.0) { $0 + $1.duration }
            let totalMins = Int(totalOverlapSec / 60.0)
            let totalSecs = Int(totalOverlapSec) % 60

            var prob = 0
            if !overlaps.isEmpty {
                prob = min(98, max(12, overlaps.count * 14 + totalMins * 3))
            }

            entries.append(.header(id: 200, section: .metrics, text: "АНАЛИТИКА СОВПАДЕНИЙ"))
            entries.append(.metric(
                id: 210,
                symbol: "chart.line.uptrend.xyaxis",
                color: prob >= 70 ? AyuGramRowColor.red : (prob >= 40 ? AyuGramRowColor.orange : AyuGramRowColor.blue),
                title: "Вероятность личного общения",
                value: "\(prob)%"
            ))
            entries.append(.metric(
                id: 220,
                symbol: "link",
                color: AyuGramRowColor.indigo,
                title: "Синхронных сессий",
                value: "\(overlaps.count)"
            ))
            entries.append(.metric(
                id: 230,
                symbol: "clock.arrow.2.circlepath",
                color: AyuGramRowColor.teal,
                title: "Общее время синхрона",
                value: "\(totalMins)м \(totalSecs)с"
            ))

            entries.append(.header(id: 300, section: .log, text: "ИСХОДНЫЕ ТАЙМКОДЫ ПЕРЕСЕЧЕНИЙ"))
            if overlaps.isEmpty {
                entries.append(.empty(id: 310, text: "Синхронных заходов пока не зафиксировано. Оставьте радар активным: по мере накопления статистики здесь появятся точные временные интервалы."))
            } else {
                let df = DateFormatter()
                df.dateFormat = "dd.MM HH:mm"

                for (idx, ov) in overlaps.prefix(25).enumerated() {
                    let dateStr = df.string(from: Date(timeIntervalSince1970: ov.start))
                    let durStr = "\(Int(ov.duration / 60))м \(Int(ov.duration) % 60)с"
                    entries.append(.overlapItem(id: 310 + idx, dateText: "⚡ \(dateStr)", durationText: durStr))
                }
            }
        } else {
            entries.append(.header(id: 300, section: .log, text: "СТАТУС РАДАРА"))
            entries.append(.empty(id: 310, text: "Выберите двух разных пользователей из отслеживаемых контактов для запуска перекрестного анализа."))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Синхронный радар"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments as Any))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerRef = controller
    return controller
}
