import Foundation

public struct D1mplenPresenceSession: Codable, Equatable {
    public var start: Double
    public var end: Double?

    public init(start: Double, end: Double? = nil) {
        self.start = start
        self.end = end
    }
}

public enum D1mplenTrackerEventKind: String, Codable, Equatable {
    case online
    case offline
    case avatarChanged
    case nameChanged
    case usernameChanged
    case bioChanged
    case typingStarted
    case recordingRound
    case recordingVoice
    case uploadingMedia
    case note

    public var isProfileChange: Bool {
        switch self {
        case .avatarChanged, .nameChanged, .usernameChanged, .bioChanged:
            return true
        default:
            return false
        }
    }

    public var isTypingActivity: Bool {
        switch self {
        case .typingStarted, .recordingRound, .recordingVoice, .uploadingMedia:
            return true
        default:
            return false
        }
    }

    public var displayEmoji: String {
        switch self {
        case .online:
            return "🟢"
        case .offline:
            return "⚫"
        case .avatarChanged:
            return "🖼"
        case .nameChanged:
            return "🪪"
        case .usernameChanged:
            return "🔗"
        case .bioChanged:
            return "📝"
        case .typingStarted:
            return "✍️"
        case .recordingRound:
            return "🎥"
        case .recordingVoice:
            return "🎤"
        case .uploadingMedia:
            return "📎"
        case .note:
            return "📡"
        }
    }

    public var displayTitle: String {
        switch self {
        case .online:
            return "В сети"
        case .offline:
            return "Вышел из сети"
        case .avatarChanged:
            return "Смена аватарки"
        case .nameChanged:
            return "Смена имени"
        case .usernameChanged:
            return "Смена @username"
        case .bioChanged:
            return "Смена Bio"
        case .typingStarted:
            return "Печатает сообщение"
        case .recordingRound:
            return "Записывает кружочек"
        case .recordingVoice:
            return "Записывает голосовое"
        case .uploadingMedia:
            return "Отправляет медиа"
        case .note:
            return "Событие"
        }
    }
}

public struct D1mplenTrackerEvent: Codable, Equatable {
    public var id: String
    public var timestamp: Double
    public var kind: D1mplenTrackerEventKind
    public var detail: String

    public init(id: String = UUID().uuidString, timestamp: Double = Date().timeIntervalSince1970, kind: D1mplenTrackerEventKind, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
    }
}

public struct D1mplenTrackedContact: Codable, Equatable {
    public var peerId: Int64
    public var displayName: String
    public var username: String?
    public var about: String?
    public var avatarId: String?
    public var commonGroupsCount: Int32?
    public var addedAt: Double
    public var isCurrentlyOnline: Bool
    public var lastSeenAt: Double?
    public var lastTypingAt: Double?
    public var typingCount: Int
    public var hasProfileBaseline: Bool
    public var hasAboutBaseline: Bool
    public var sessions: [D1mplenPresenceSession]
    public var events: [D1mplenTrackerEvent]

    public init(
        peerId: Int64,
        displayName: String,
        username: String? = nil,
        about: String? = nil,
        avatarId: String? = nil,
        commonGroupsCount: Int32? = nil,
        addedAt: Double = Date().timeIntervalSince1970,
        isCurrentlyOnline: Bool = false,
        lastSeenAt: Double? = nil,
        lastTypingAt: Double? = nil,
        typingCount: Int = 0,
        hasProfileBaseline: Bool = false,
        hasAboutBaseline: Bool = false,
        sessions: [D1mplenPresenceSession] = [],
        events: [D1mplenTrackerEvent] = []
    ) {
        self.peerId = peerId
        self.displayName = displayName
        self.username = username
        self.about = about
        self.avatarId = avatarId
        self.commonGroupsCount = commonGroupsCount
        self.addedAt = addedAt
        self.isCurrentlyOnline = isCurrentlyOnline
        self.lastSeenAt = lastSeenAt
        self.lastTypingAt = lastTypingAt
        self.typingCount = typingCount
        self.hasProfileBaseline = hasProfileBaseline
        self.hasAboutBaseline = hasAboutBaseline
        self.sessions = sessions
        self.events = events
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.peerId = try c.decode(Int64.self, forKey: .peerId)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Контакт"
        self.username = try c.decodeIfPresent(String.self, forKey: .username)
        self.about = try c.decodeIfPresent(String.self, forKey: .about)
        self.avatarId = try c.decodeIfPresent(String.self, forKey: .avatarId)
        self.commonGroupsCount = try c.decodeIfPresent(Int32.self, forKey: .commonGroupsCount)
        self.addedAt = try c.decodeIfPresent(Double.self, forKey: .addedAt) ?? Date().timeIntervalSince1970
        self.isCurrentlyOnline = try c.decodeIfPresent(Bool.self, forKey: .isCurrentlyOnline) ?? false
        self.lastSeenAt = try c.decodeIfPresent(Double.self, forKey: .lastSeenAt)
        self.lastTypingAt = try c.decodeIfPresent(Double.self, forKey: .lastTypingAt)
        self.typingCount = try c.decodeIfPresent(Int.self, forKey: .typingCount) ?? 0
        self.hasProfileBaseline = try c.decodeIfPresent(Bool.self, forKey: .hasProfileBaseline) ?? false
        self.hasAboutBaseline = try c.decodeIfPresent(Bool.self, forKey: .hasAboutBaseline) ?? false
        self.sessions = try c.decodeIfPresent([D1mplenPresenceSession].self, forKey: .sessions) ?? []
        self.events = try c.decodeIfPresent([D1mplenTrackerEvent].self, forKey: .events) ?? []
    }
}

public struct D1mplenQueuedOnlineMessage: Codable, Equatable {
    public var id: String
    public var peerId: Int64
    public var text: String
    public var silent: Bool
    public var createdAt: Double

    public init(
        id: String = UUID().uuidString,
        peerId: Int64,
        text: String,
        silent: Bool = false,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.peerId = peerId
        self.text = text
        self.silent = silent
        self.createdAt = createdAt
    }
}

public struct D1mplenContactAnalytics: Equatable {
    public let todayOnlineSeconds: TimeInterval
    public let totalOnlineSeconds: TimeInterval
    public let averageDailySeconds: TimeInterval
    public let sessionCount: Int
    public let averageSessionSeconds: TimeInterval
    public let averageFirstSeenSecondsOfDay: TimeInterval?
    public let averageLastSeenSecondsOfDay: TimeInterval?
    public let peakHour: Int?
    public let unsentTypingAttempts: Int
    public let profileChangesCount: Int

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours)ч \(minutes)м"
        }
        if minutes > 0 {
            return "\(minutes)м \(secs)с"
        }
        return "\(secs)с"
    }

    public static func formatTimeOfDay(_ secondsFromMidnight: TimeInterval) -> String {
        let clamped = max(0, min(86399, Int(secondsFromMidnight.rounded())))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

private struct D1mplenTrackerState: Codable {
    var contacts: [D1mplenTrackedContact] = []
    var queuedMessages: [D1mplenQueuedOnlineMessage] = []
}

public final class D1mplenTrackerStore {
    public static let shared = D1mplenTrackerStore()
    public static let didChangeNotification = Notification.Name("D1mplenGram.TrackerStoreDidChange")

    private let lock = NSLock()
    private let fileURL: URL
    private var state: D1mplenTrackerState

    private init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = baseDir.appendingPathComponent("D1mplenGram", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent("tracker_store.json", isDirectory: false)
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(D1mplenTrackerState.self, from: data) {
            self.state = decoded
        } else {
            self.state = D1mplenTrackerState()
        }
    }

    private func saveAndNotifyLocked() {
        if let data = try? JSONEncoder().encode(self.state) {
            try? data.write(to: self.fileURL, options: .atomic)
            var url = self.fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: D1mplenTrackerStore.didChangeNotification, object: nil)
        }
    }

    public func trackedPeerIds() -> [Int64] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.contacts.map(\.peerId)
    }

    public func isTracked(_ peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.contacts.contains { $0.peerId == peerId }
    }

    public func contact(for peerId: Int64) -> D1mplenTrackedContact? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.contacts.first { $0.peerId == peerId }
    }

    public func allContacts() -> [D1mplenTrackedContact] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.contacts.sorted { lhs, rhs in
            if lhs.isCurrentlyOnline != rhs.isCurrentlyOnline {
                return lhs.isCurrentlyOnline && !rhs.isCurrentlyOnline
            }
            return (lhs.lastSeenAt ?? lhs.addedAt) > (rhs.lastSeenAt ?? rhs.addedAt)
        }
    }

    public func setTrackedPeers(_ peers: [(peerId: Int64, displayName: String, username: String?)]) {
        self.lock.lock()
        var existingById: [Int64: D1mplenTrackedContact] = [:]
        for item in self.state.contacts {
            existingById[item.peerId] = item
        }
        var updated: [D1mplenTrackedContact] = []
        var seen = Set<Int64>()
        for entry in peers where !seen.contains(entry.peerId) {
            seen.insert(entry.peerId)
            if var current = existingById[entry.peerId] {
                if !entry.displayName.isEmpty {
                    current.displayName = entry.displayName
                }
                if entry.username != nil {
                    current.username = entry.username
                }
                updated.append(current)
            } else {
                var fresh = D1mplenTrackedContact(
                    peerId: entry.peerId,
                    displayName: entry.displayName.isEmpty ? "Контакт \(entry.peerId)" : entry.displayName,
                    username: entry.username
                )
                fresh.events.insert(
                    D1mplenTrackerEvent(kind: .note, detail: "Контакт добавлен в мониторинг"),
                    at: 0
                )
                updated.append(fresh)
            }
        }
        self.state.contacts = updated
        self.saveAndNotifyLocked()
        self.lock.unlock()
    }

    public func addOrUpdateContact(peerId: Int64, displayName: String, username: String? = nil) {
        self.lock.lock()
        if let index = self.state.contacts.firstIndex(where: { $0.peerId == peerId }) {
            if !displayName.isEmpty {
                self.state.contacts[index].displayName = displayName
            }
            if let username, !username.isEmpty {
                self.state.contacts[index].username = username
            }
        } else {
            var fresh = D1mplenTrackedContact(
                peerId: peerId,
                displayName: displayName.isEmpty ? "Контакт \(peerId)" : displayName,
                username: username
            )
            fresh.events.insert(
                D1mplenTrackerEvent(kind: .note, detail: "Контакт добавлен в мониторинг"),
                at: 0
            )
            self.state.contacts.append(fresh)
        }
        self.saveAndNotifyLocked()
        self.lock.unlock()
    }

    public func removeContact(_ peerId: Int64) {
        self.lock.lock()
        self.state.contacts.removeAll { $0.peerId == peerId }
        self.saveAndNotifyLocked()
        self.lock.unlock()
    }

    public func clearStats(for peerId: Int64) {
        self.lock.lock()
        if let index = self.state.contacts.firstIndex(where: { $0.peerId == peerId }) {
            self.state.contacts[index].sessions = []
            self.state.contacts[index].events = [
                D1mplenTrackerEvent(kind: .note, detail: "Статистика очищена")
            ]
            self.state.contacts[index].typingCount = 0
            self.state.contacts[index].lastTypingAt = nil
            self.state.contacts[index].isCurrentlyOnline = false
            self.saveAndNotifyLocked()
        }
        self.lock.unlock()
    }

    public func updatePresence(
        peerId: Int64,
        displayName: String,
        isOnline: Bool,
        statusUntil: Int32?,
        now: Double = Date().timeIntervalSince1970
    ) -> (becameOnline: Bool, becameOffline: Bool) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let index = self.state.contacts.firstIndex(where: { $0.peerId == peerId }) else {
            return (false, false)
        }

        var contact = self.state.contacts[index]
        if !displayName.isEmpty {
            contact.displayName = displayName
        }

        var becameOnline = false
        var becameOffline = false
        var changed = false

        if isOnline {
            if !contact.isCurrentlyOnline {
                contact.isCurrentlyOnline = true
                contact.lastSeenAt = now
                contact.sessions.append(D1mplenPresenceSession(start: now, end: nil))
                if contact.sessions.count > 500 {
                    contact.sessions.removeFirst(contact.sessions.count - 500)
                }
                Self.appendEvent(&contact, kind: .online, detail: "Зашёл в сеть", now: now)
                becameOnline = true
                changed = true
            } else {
                contact.lastSeenAt = now
            }
        } else {
            if let statusUntil, statusUntil > 0 {
                let candidate = Double(statusUntil)
                if candidate > (contact.lastSeenAt ?? 0) && candidate <= now + 5.0 {
                    contact.lastSeenAt = candidate
                }
            }
            if contact.isCurrentlyOnline {
                let endTs: Double
                if let statusUntil, statusUntil > 0, Double(statusUntil) <= now + 5.0 {
                    endTs = Double(statusUntil)
                } else {
                    endTs = now
                }
                for i in contact.sessions.indices.reversed() {
                    if contact.sessions[i].end == nil {
                        contact.sessions[i].end = max(contact.sessions[i].start + 1.0, endTs)
                        break
                    }
                }
                contact.isCurrentlyOnline = false
                contact.lastSeenAt = max(contact.lastSeenAt ?? 0, endTs)
                Self.appendEvent(&contact, kind: .offline, detail: "Вышел из сети", now: now)
                becameOffline = true
                changed = true
            }
        }

        self.state.contacts[index] = contact
        if changed {
            self.saveAndNotifyLocked()
        }
        return (becameOnline, becameOffline)
    }

    public func recordProfileSnapshot(
        peerId: Int64,
        displayName: String,
        username: String?,
        aboutKnown: Bool,
        about: String?,
        avatarId: String?,
        commonGroupsCount: Int32?,
        now: Double = Date().timeIntervalSince1970
    ) -> [(kind: D1mplenTrackerEventKind, detail: String)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let index = self.state.contacts.firstIndex(where: { $0.peerId == peerId }) else {
            return []
        }

        var contact = self.state.contacts[index]
        var detected: [(kind: D1mplenTrackerEventKind, detail: String)] = []
        var modified = false

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = Self.normalizeOptional(username)
        let normalizedAbout = Self.normalizeOptional(about)

        if !contact.hasProfileBaseline {
            if !normalizedName.isEmpty {
                contact.displayName = normalizedName
            }
            contact.username = normalizedUsername
            contact.avatarId = avatarId
            contact.hasProfileBaseline = true
            if let commonGroupsCount {
                contact.commonGroupsCount = commonGroupsCount
            }
            if aboutKnown {
                contact.about = normalizedAbout
                contact.hasAboutBaseline = true
            }
            self.state.contacts[index] = contact
            self.saveAndNotifyLocked()
            return []
        }

        if !normalizedName.isEmpty && normalizedName != contact.displayName {
            let detail = "«\(contact.displayName)» → «\(normalizedName)»"
            contact.displayName = normalizedName
            Self.appendEvent(&contact, kind: .nameChanged, detail: detail, now: now)
            detected.append((.nameChanged, detail))
            modified = true
        }

        if normalizedUsername != contact.username {
            let oldStr = contact.username.map { "@\($0)" } ?? "скрыт"
            let newStr = normalizedUsername.map { "@\($0)" } ?? "скрыт"
            let detail = "\(oldStr) → \(newStr)"
            contact.username = normalizedUsername
            Self.appendEvent(&contact, kind: .usernameChanged, detail: detail, now: now)
            detected.append((.usernameChanged, detail))
            modified = true
        }

        if avatarId != contact.avatarId {
            let detail: String
            if avatarId == nil {
                detail = "Удалил фото профиля"
            } else if contact.avatarId == nil {
                detail = "Установил новое фото профиля"
            } else {
                detail = "Обновил аватарку"
            }
            contact.avatarId = avatarId
            Self.appendEvent(&contact, kind: .avatarChanged, detail: detail, now: now)
            detected.append((.avatarChanged, detail))
            modified = true
        }

        if aboutKnown {
            if !contact.hasAboutBaseline {
                contact.about = normalizedAbout
                contact.hasAboutBaseline = true
                modified = true
            } else if normalizedAbout != contact.about {
                let oldBio = contact.about ?? "пусто"
                let newBio = normalizedAbout ?? "пусто"
                let detail = "«\(Self.truncate(oldBio, limit: 48))» → «\(Self.truncate(newBio, limit: 48))»"
                contact.about = normalizedAbout
                Self.appendEvent(&contact, kind: .bioChanged, detail: detail, now: now)
                detected.append((.bioChanged, detail))
                modified = true
            }
        }

        if let commonGroupsCount, commonGroupsCount != contact.commonGroupsCount {
            contact.commonGroupsCount = commonGroupsCount
            modified = true
        }

        if modified {
            self.state.contacts[index] = contact
            self.saveAndNotifyLocked()
        }
        return detected
    }

    public func recordActivity(
        peerId: Int64,
        kind: D1mplenTrackerEventKind,
        detail: String,
        now: Double = Date().timeIntervalSince1970
    ) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let index = self.state.contacts.firstIndex(where: { $0.peerId == peerId }) else {
            return false
        }

        var contact = self.state.contacts[index]
        if let lastEvent = contact.events.first(where: { $0.kind == kind }), now - lastEvent.timestamp < 12.0 {
            return false
        }

        contact.lastTypingAt = now
        contact.typingCount += 1
        Self.appendEvent(&contact, kind: kind, detail: detail, now: now)
        self.state.contacts[index] = contact
        self.saveAndNotifyLocked()
        return true
    }

    public func analytics(for peerId: Int64, now: Double = Date().timeIntervalSince1970) -> D1mplenContactAnalytics? {
        self.lock.lock()
        let contact = self.state.contacts.first { $0.peerId == peerId }
        self.lock.unlock()
        guard let contact else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: now)).timeIntervalSince1970

        var todaySeconds: TimeInterval = 0
        var totalSeconds: TimeInterval = 0
        var dailyTotals: [Date: TimeInterval] = [:]
        var dailyFirstOffset: [Date: TimeInterval] = [:]
        var dailyLastOffset: [Date: TimeInterval] = [:]
        var hourHistogram = Array(repeating: 0, count: 24)

        for session in contact.sessions {
            let startTs = session.start
            let endTs = max(startTs, min(session.end ?? now, now))
            let dur = max(0, endTs - startTs)
            totalSeconds += dur

            let startDate = Date(timeIntervalSince1970: startTs)
            let day = calendar.startOfDay(for: startDate)
            let dayStartTs = day.timeIntervalSince1970
            let offsetStart = max(0, min(86399, startTs - dayStartTs))
            let offsetEnd = max(0, min(86399, endTs - dayStartTs))

            if dayStartTs >= todayStart {
                todaySeconds += dur
            }
            dailyTotals[day, default: 0] += dur
            if let existingFirst = dailyFirstOffset[day] {
                dailyFirstOffset[day] = min(existingFirst, offsetStart)
            } else {
                dailyFirstOffset[day] = offsetStart
            }
            if let existingLast = dailyLastOffset[day] {
                dailyLastOffset[day] = max(existingLast, offsetEnd)
            } else {
                dailyLastOffset[day] = offsetEnd
            }

            let hour = calendar.component(.hour, from: startDate)
            if hour >= 0 && hour < 24 {
                hourHistogram[hour] += max(1, Int(dur / 60.0) + 1)
            }
        }

        let dayCount = max(1, dailyTotals.count)
        let avgDaily = dailyTotals.isEmpty ? 0 : (dailyTotals.values.reduce(0, +) / Double(dayCount))
        let avgSession = contact.sessions.isEmpty ? 0 : (totalSeconds / Double(contact.sessions.count))
        let avgFirst: TimeInterval? = dailyFirstOffset.isEmpty ? nil : (dailyFirstOffset.values.reduce(0, +) / Double(dailyFirstOffset.count))
        let avgLast: TimeInterval? = dailyLastOffset.isEmpty ? nil : (dailyLastOffset.values.reduce(0, +) / Double(dailyLastOffset.count))
        let peakHour: Int? = hourHistogram.enumerated().max(by: { $0.element < $1.element }).flatMap { $0.element > 0 ? $0.offset : nil }
        let profileChangesCount = contact.events.filter { $0.kind.isProfileChange }.count

        return D1mplenContactAnalytics(
            todayOnlineSeconds: todaySeconds,
            totalOnlineSeconds: totalSeconds,
            averageDailySeconds: avgDaily,
            sessionCount: contact.sessions.count,
            averageSessionSeconds: avgSession,
            averageFirstSeenSecondsOfDay: avgFirst,
            averageLastSeenSecondsOfDay: avgLast,
            peakHour: peakHour,
            unsentTypingAttempts: contact.typingCount,
            profileChangesCount: profileChangesCount
        )
    }

    // MARK: - Send When Online Queue

    @discardableResult
    public func enqueueOnlineMessage(peerId: Int64, text: String, silent: Bool = false) -> D1mplenQueuedOnlineMessage {
        self.lock.lock()
        let item = D1mplenQueuedOnlineMessage(peerId: peerId, text: text, silent: silent)
        self.state.queuedMessages.append(item)
        self.saveAndNotifyLocked()
        self.lock.unlock()
        return item
    }

    public func queuedMessages(for peerId: Int64) -> [D1mplenQueuedOnlineMessage] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.queuedMessages.filter { $0.peerId == peerId }
    }

    public func allQueuedMessages() -> [D1mplenQueuedOnlineMessage] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.queuedMessages
    }

    public func popQueuedMessages(for peerId: Int64) -> [D1mplenQueuedOnlineMessage] {
        self.lock.lock()
        let matched = self.state.queuedMessages.filter { $0.peerId == peerId }
        if !matched.isEmpty {
            self.state.queuedMessages.removeAll { $0.peerId == peerId }
            self.saveAndNotifyLocked()
        }
        self.lock.unlock()
        return matched
    }

    public func removeQueuedMessage(id: String) {
        self.lock.lock()
        let before = self.state.queuedMessages.count
        self.state.queuedMessages.removeAll { $0.id == id }
        if self.state.queuedMessages.count != before {
            self.saveAndNotifyLocked()
        }
        self.lock.unlock()
    }

    public func clearQueuedMessages(for peerId: Int64) {
        self.lock.lock()
        let before = self.state.queuedMessages.count
        self.state.queuedMessages.removeAll { $0.peerId == peerId }
        if self.state.queuedMessages.count != before {
            self.saveAndNotifyLocked()
        }
        self.lock.unlock()
    }

    private static func appendEvent(_ contact: inout D1mplenTrackedContact, kind: D1mplenTrackerEventKind, detail: String, now: Double) {
        contact.events.insert(D1mplenTrackerEvent(timestamp: now, kind: kind, detail: detail), at: 0)
        if contact.events.count > 300 {
            contact.events.removeLast(contact.events.count - 300)
        }
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        if value.count <= limit {
            return value
        }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }
}
