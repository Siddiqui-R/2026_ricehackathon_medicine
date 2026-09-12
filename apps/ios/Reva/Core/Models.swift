// Purpose: Define persisted patient, record, visit and snapshot contracts.
// Inputs: Decoded JSON and user/domain values.
// Outputs: Codable value types and snapshot validation errors.
// Side effects: None; file references describe originals without opening them.

import Foundation

// MARK: - Persistent medical profile
// Quick-reference health fields; optional additions preserve decoding of older snapshots.
struct PatientProfile: Codable, Equatable {
    var id: String
    var name: String
    var dateOfBirth: String
    var initials: String
    var allergies: [String]
    var medications: [String]
    var conditions: [String]
    var isDemo: Bool
    var surgeriesAndImplants: [String]? = nil
    var careNotes: String? = nil
}

// MARK: - Versioned source record
// Keep original provenance, extracted wording, summary origin and optional symptom structure together.
struct MedicalRecord: Codable, Identifiable, Equatable {
    static let configurableKinds = ["Notes", "Labs", "Imaging", "Procedure", "Scan"]

    var id: String = UUID().uuidString
    var title: String
    var kind: String
    var provider: String
    var date: String
    var uploadedAt: String = RevaDate.now
    var tags: [String] = []
    var text: String
    var summary: String
    var sourceFilename: String?
    var mimeType: String?
    var pageCount: Int = 1
    var status: String = "ready"
    var notes: String = ""
    var isDemo: Bool = false
    var version: Int = 1
    var pageTexts: [String]?
    var sourceRecordingID: String? = nil
    var summaryModel: String? = nil
    var symptomEntry: SymptomEntry? = nil

    var symbol: String {
        switch kind {
        case "Labs": return "flask"
        case "Imaging": return "waveform.path.ecg.rectangle"
        case "Procedure": return "cross.case"
        case "Recording": return "waveform"
        case "Scan": return "doc.viewfinder"
        case "User symptom entry": return "heart.text.clipboard"
        default: return "doc.text"
        }
    }
    var summaryLabel: String {
        summaryModel.map { "AI summary · " + $0 }
            ?? (symptomEntry != nil ? "Your entry" : isDemo ? "Demo summary" : "Local excerpt")
    }
}

// MARK: - Report citation
// Identify exact source record/version and page; page zero denotes unpaginated record text.
struct SourceReference: Codable, Identifiable, Equatable {
    var recordID: String
    var page: Int
    var excerpt: String
    var sourceVersion: Int?
    var excerptOmitted: Bool? = nil
    var id: String { "\(recordID)-\(page)" }
    static let excerptOmissionNotice =
        "Selected passage; additional source text omitted. Open the original for full context."
    var omissionNotice: String? {
        guard let excerptOmitted else {
            return "This older excerpt may have been shortened. Regenerate the brief and review the original."
        }
        guard excerptOmitted else { return nil }
        return excerpt.isEmpty
            ? "No complete source line fits in this excerpt. Open the original for full context."
            : Self.excerptOmissionNotice
    }
    var locationLabel: String { page > 0 ? "p. \(page)" : "record text" }
}
// MARK: - Report section
// Group readable content with its source references without performing selection.
struct ReportSection: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var body: String
    var sources: [SourceReference]
}
// MARK: - Saved visit brief
// Persist the source signature, evidence sections and user-facing questions/notes.
// MARK: - Appointment context
// Keep appointment intent, source pins and user-owned questions with the optional generated brief.
struct VisitReport: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var visitID: String
    var createdAt: String = RevaDate.now
    var sourceSignature: String
    var sections: [ReportSection]
    var questions: [String]
    var notes: String
    var selectedRecordIDs: [String]
    var isDemo: Bool = true
    var generationModel: String? = nil
}
struct Visit: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var type: String
    var provider: String
    var clinic: String
    var date: String
    var timeZone: String = RevaDate.defaultTimeZoneIdentifier
    var concern: String
    var goal: String
    var questions: [String] = []
    var pinnedRecordIDs: [String] = []
    var notes: String = ""
    var status: String = "upcoming"
    var report: VisitReport?
}
// MARK: - Booking lifecycle value
// Separate simulated and live state while preserving the stable request identity.
struct BookingRequest: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var visitID: String
    var clinic: String
    var phone: String
    var reason: String
    var earliest: String
    var latest: String
    var timeZone: String
    var preferences: String
    var status: String = "draft"
    var scenario: String = "Appointment available"
    var createdAt: String = RevaDate.now
    var confirmedVisitID: String?
    var isLive: Bool? = nil
    var providerConversationID: String? = nil
    var providerTranscript: String? = nil
}
// MARK: - Audio-relative transcript segment
// Retain speaker text and offsets measured from the start of the source recording.
struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id: String
    var speaker: String
    var start: Double
    var end: Double
    var text: String
}
// MARK: - Visit recording and memory source
// Tie optional original audio, reviewed segments and transcription provenance to a visit.
struct VisitRecording: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var visitID: String
    var title: String
    var createdAt: String = RevaDate.now
    var duration: Double
    var audioFilename: String?
    var segments: [TranscriptSegment] = []
    var summary: String = ""
    var isSample: Bool = false
    var status: String = "saved"
    var transcriptionModel: String? = nil
}
// MARK: - Persistence aggregate
// Group related domain values for one atomic save and validate cross-object references.
struct AppSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var profile: PatientProfile
    var records: [MedicalRecord]
    var visits: [Visit]
    var bookings: [BookingRequest] = []
    var recordings: [VisitRecording] = []

    func validate() throws {
        guard schemaVersion == 1, !profile.id.isEmpty, !profile.name.isEmpty else {
            throw RevaError.invalid("This data version or profile is not supported.")
        }
        for ids in [records.map(\.id), visits.map(\.id), bookings.map(\.id), recordings.map(\.id)] {
            guard Set(ids).count == ids.count, !ids.contains("") else {
                throw RevaError.invalid("The data contains duplicate or empty identifiers.")
            }
        }
        let visitIDs = Set(visits.map(\.id))
        guard bookings.allSatisfy({ visitIDs.contains($0.visitID) }),
            recordings.allSatisfy({ visitIDs.contains($0.visitID) })
        else { throw RevaError.invalid("A booking or recording refers to a missing visit.") }
        let filenames = records.compactMap(\.sourceFilename) + recordings.compactMap(\.audioFilename)
        guard filenames.allSatisfy(Self.safeFilename) else {
            throw RevaError.invalid("An attachment filename is invalid.")
        }
    }
    static func safeFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.count <= 240 && !name.contains("/")
            && !name.contains("\\") && !name.contains("\0")
    }
}
// MARK: - Domain errors
// Carry user-readable validation failures without unrelated diagnostic payloads.
enum RevaError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
// MARK: - Date and duration conventions
// Default actual instants to US Central; keep date-only values independent of time zones.
enum RevaDate {
    static let defaultTimeZoneIdentifier = "America/Chicago"
    static let defaultTimeZone = TimeZone(identifier: defaultTimeZoneIdentifier)!
    // UTC is only a neutral carrier for calendar-only values such as record dates and birthdays.
    static let calendarDayTimeZone = TimeZone(secondsFromGMT: 0)!

    static var now: String { ISO8601DateFormatter().string(from: Date()) }
    static func parse(_ text: String) -> Date {
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: text) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 0)
        return day.date(from: text) ?? .distantPast
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func day(_ date: Date, zone: TimeZone = calendarDayTimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = zone
        return f.string(from: date)
    }
    static func today(at date: Date = Date()) -> String { day(date, zone: defaultTimeZone) }

    static func display(_ text: String, time: Bool = false, zone: String? = nil) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let dateOnly = text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        f.timeStyle = time && !dateOnly ? .short : .none
        f.timeZone =
            dateOnly ? calendarDayTimeZone : (zone.flatMap(TimeZone.init(identifier:)) ?? defaultTimeZone)
        return f.string(from: parse(text))
    }
    static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
