import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI
import SGSimpleSettings

private enum PipFinderSection: Int32 {
    case input
    case action
    case result
    case recent
}

private struct PipChatCandidate {
    let peerId: EnginePeer.Id
    let title: String
    let username: String?
}

private enum PipFinderEntry: ItemListNodeEntry {
    case header(id: Int, section: PipFinderSection, text: String)
    case input(id: Int, text: String, placeholder: String)
    case action(id: Int, title: String, subtitle: String?, inProgress: Bool)
    case match(id: Int, peerId: EnginePeer.Id, peer: EnginePeer?, title: String, username: String?, reason: String)
    case noMatch(id: Int, text: String)
    case footer(id: Int, section: PipFinderSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _),
             let .footer(_, section, _):
            return section.rawValue
        case .input:
            return PipFinderSection.input.rawValue
        case .action:
            return PipFinderSection.action.rawValue
        case .match, .noMatch:
            return PipFinderSection.result.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _),
             let .input(id, _, _),
             let .action(id, _, _, _),
             let .match(id, _, _, _, _, _),
             let .noMatch(id, _),
             let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: PipFinderEntry, rhs: PipFinderEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PipFinderArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .input(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: true),
                returnKeyType: .search,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { value in
                    args.updateQuery(value)
                },
                action: {
                    args.performSearch()
                },
                dismissKeyboardOnEnter: true
            )
        case let .action(_, title, subtitle, inProgress):
            let label = inProgress ? "Поиск…" : "Найти 🔍"
            return ItemListActionItem(
                presentationData: presentationData,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if !inProgress {
                        args.performSearch()
                    }
                }
            )
        case let .match(_, peerId, peer, title, username, reason):
            let detail = (username.flatMap { "@" + $0 + "\n" } ?? "") + reason
            return ItemListDisclosureItem(
                presentationData: presentationData,
                context: args.context,
                iconPeer: peer,
                title: title,
                label: "Перейти 💬",
                additionalDetailLabel: detail,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.openChat(peerId)
                }
            )
        case let .noMatch(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class PipFinderArguments {
    let context: AccountContext
    let updateQuery: (String) -> Void
    let performSearch: () -> Void
    let openChat: (EnginePeer.Id) -> Void

    init(
        context: AccountContext,
        updateQuery: @escaping (String) -> Void,
        performSearch: @escaping () -> Void,
        openChat: @escaping (EnginePeer.Id) -> Void
    ) {
        self.context = context
        self.updateQuery = updateQuery
        self.performSearch = performSearch
        self.openChat = openChat
    }
}

private struct PipFinderMatch: Equatable {
    let peerId: EnginePeer.Id
    let peer: EnginePeer?
    let title: String
    let username: String?
    let reason: String

    static func == (lhs: PipFinderMatch, rhs: PipFinderMatch) -> Bool {
        return lhs.peerId == rhs.peerId && lhs.title == rhs.title && lhs.username == rhs.username && lhs.reason == rhs.reason
    }
}

private struct PipFinderState: Equatable {
    var query: String = ""
    var inProgress: Bool = false
    var match: PipFinderMatch? = nil
    var hasSearched: Bool = false
}

func pipAiComplete(system: String, prompt: String, maxTokens: Int = 300, completion: @escaping (String?) -> Void) {
    let extra = AyuGramSettings.shared.extra
    let customKey = extra.pipAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !customKey.isEmpty {
        let provider = extra.pipAiProvider
        var endpoint = "https://api.openai.com/v1/chat/completions"
        var model = "gpt-4o-mini"
        if provider == 2 {
            endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            model = "gemini-2.0-flash"
        } else if provider == 3 {
            endpoint = "https://api.groq.com/openai/v1/chat/completions"
            model = "llama-3.3-70b-versatile"
        }
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + customKey, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var reply: String? = nil
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                reply = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async {
                completion(reply)
            }
        }.resume()
    } else {
        ayuGramAssistantComplete(system: system, prompt: prompt, maxTokens: maxTokens, locale: "ru") { text, _ in
            completion(text)
        }
    }
}

public func pipSemanticChatFinderController(context: AccountContext) -> ViewController {
    let stateValue = ValuePromise<PipFinderState>(PipFinderState(), ignoreRepeated: true)
    let stateRef = Atomic<PipFinderState>(value: PipFinderState())

    let updateState: ((inout PipFinderState) -> Void) -> Void = { f in
        stateValue.set(stateRef.modify { current in
            var copy = current
            f(&copy)
            return copy
        })
    }

    var openChatImpl: ((EnginePeer.Id) -> Void)?

    let arguments = PipFinderArguments(
        context: context,
        updateQuery: { q in
            updateState { $0.query = q }
        },
        performSearch: {
            let current = stateRef.with { $0 }
            let query = current.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, !current.inProgress else { return }

            updateState {
                $0.inProgress = true
                $0.hasSearched = true
                $0.match = nil
            }

            // Collect top 40 chats
            let _ = (context.engine.messages.chatListPeers(group: .root, filterPredicate: nil, count: 40)
            |> take(1)
            |> deliverOnMainQueue).start(next: { peers, _ in
                var candidates: [PipChatCandidate] = []
                var promptLines: [String] = []

                for (idx, p) in peers.prefix(35).enumerated() {
                    let title = p.debugDisplayTitle
                    let username = p.addressName
                    candidates.append(PipChatCandidate(peerId: p.id, title: title, username: username))
                    let u = username.map { "@" + $0 } ?? "no_username"
                    promptLines.append("[\(idx + 1)] ID: \(p.id.toInt64()) | Title: \(title) | \(u)")
                }

                if candidates.isEmpty {
                    updateState {
                        $0.inProgress = false
                        $0.match = nil
                    }
                    return
                }

                let system = """
                You are Pip AI Smart Chat Finder inside Telegram.
                You are given a list of user chats with their titles and usernames.
                Analyze the user query describing what happened or who they spoke with, and determine which chat candidate best matches.
                Respond with valid JSON only in this exact format:
                {"matched_id": 12345, "reason": "Короткое объяснение на русском, почему подходит этот контакт"}
                If no chat matches, return:
                {"matched_id": 0, "reason": "Подходящий чат не найден"}
                """

                let userPrompt = "User Query: \"\(query)\"\n\nAvailable Chats:\n" + promptLines.joined(separator: "\n")

                pipAiComplete(system: system, prompt: userPrompt, maxTokens: 250) { response in
                    Queue.mainQueue().async {
                        updateState { state in
                            state.inProgress = false
                            guard let text = response, !text.isEmpty else {
                                state.match = nil
                                return
                            }

                            // Extract JSON or number
                            var matchedId: Int64 = 0
                            var reasonText = "Найдено по смыслу запроса"

                            if let data = text.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                if let idNum = obj["matched_id"] as? NSNumber {
                                    matchedId = idNum.int64Value
                                } else if let idStr = obj["matched_id"] as? String, let idParsed = Int64(idStr) {
                                    matchedId = idParsed
                                }
                                if let r = obj["reason"] as? String, !r.isEmpty {
                                    reasonText = r
                                }
                            } else {
                                // Fallback: find candidate whose title or username is mentioned in text
                                for c in candidates {
                                    if text.contains(c.title) || (c.username != nil && text.contains(c.username!)) {
                                        matchedId = c.peerId.toInt64()
                                        reasonText = text
                                        break
                                    }
                                }
                            }

                            if matchedId != 0, let cand = candidates.first(where: { $0.peerId.toInt64() == matchedId }) {
                                let peerObj = peers.first(where: { $0.id == cand.peerId })
                                state.match = PipFinderMatch(peerId: cand.peerId, peer: peerObj, title: cand.title, username: cand.username, reason: reasonText)
                            } else {
                                state.match = nil
                            }
                        }
                    }
                }
            })
        },
        openChat: { peerId in
            openChatImpl?(peerId)
        }
    )

    weak var controllerRef: ViewController?

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> = combineLatest(context.sharedContext.presentationData, stateValue.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [PipFinderEntry] = []

        entries.append(.header(id: 100, section: .input, text: "ОПИСАНИЕ ЧАТА ДЛЯ НЕЙРОСЕТИ"))
        entries.append(.input(id: 110, text: state.query, placeholder: "Например: договаривались о курсовой по матану"))
        entries.append(.footer(id: 120, section: .input, text: "Опишите суть диалога, тему встречи или детали того, о чём вы переписывались. Бесплатный ИИ Pip сопоставит контекст и найдёт нужного человека."))

        entries.append(.header(id: 200, section: .action, text: "ПОИСК"))
        entries.append(.action(id: 210, title: state.inProgress ? "Нейросеть ищет совпадение…" : "✨ Найти чат через ИИ (Llama 3.3)", subtitle: nil, inProgress: state.inProgress))

        if state.hasSearched {
            entries.append(.header(id: 300, section: .result, text: "РЕЗУЛЬТАТ ПОИСКА"))
            if let match = state.match {
                entries.append(.match(
                    id: 310,
                    peerId: match.peerId,
                    peer: match.peer,
                    title: match.title,
                    username: match.username,
                    reason: match.reason
                ))
                entries.append(.footer(id: 320, section: .result, text: "Нажмите на строку выше, чтобы моментально перейти в найденный чат."))
            } else if !state.inProgress {
                entries.append(.noMatch(id: 310, text: "Нейросеть не смогла найти подходящий диалог по вашему описанию. Попробуйте уточнить детали или ключевые слова."))
            }
        }

        let leftButton = ItemListNavigationButton(
            content: .text(presentationData.strings.Common_Back),
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

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("ИИ-Поиск чата"),
            leftNavigationButton: leftButton,
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
    openChatImpl = { [weak controller] peerId in
        context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peerId, messageId: nil)
        (controller?.navigationController as? NavigationController)?.filterController(controller!, animated: true)
    }
    return controller
}
