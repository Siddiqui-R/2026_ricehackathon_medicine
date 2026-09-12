import Foundation

/// The user's own observations, retained separately from the readable record text.
struct SymptomEntry: Codable, Equatable {
    var observedAt: String = RevaDate.now
    var timeZone: String = TimeZone.current.identifier
    var symptom: String = ""
    var severity: String? = nil
    var duration: String = ""
    var details: String = ""
    var triggers: String = ""
    var whatHelped: String = ""

    static let severities = ["mild", "moderate", "severe"]

    func validated(now: Date = Date()) throws -> SymptomEntry {
        func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        var value = self
        value.symptom = trimmed(symptom)
        guard !value.symptom.isEmpty else { throw RevaError.invalid("Enter the symptom you noticed.") }
        guard value.symptom.count <= 120, !value.symptom.contains(where: \.isNewline) else {
            throw RevaError.invalid("Keep the symptom under 120 characters on one line. Add the rest in Details.")
        }
        value.observedAt = trimmed(observedAt)
        value.timeZone = trimmed(timeZone)
        guard let date = Self.timestamp(value.observedAt), TimeZone(identifier: value.timeZone) != nil else {
            throw RevaError.invalid("Choose a valid occurrence date, time, and time zone.")
        }
        guard date <= now.addingTimeInterval(300) else {
            throw RevaError.invalid("Choose when the symptom occurred, rather than a future time.")
        }
        let severity = severity.map { trimmed($0).lowercased() }
        value.severity = severity?.isEmpty == false ? severity : nil
        guard value.severity.map(Self.severities.contains) ?? true else {
            throw RevaError.invalid("Choose Mild, Moderate, Severe, or Not specified.")
        }
        value.duration = trimmed(duration)
        value.details = trimmed(details)
        value.triggers = trimmed(triggers)
        value.whatHelped = trimmed(whatHelped)
        guard value.details.count <= 12_000,
              [value.duration, value.triggers, value.whatHelped].allSatisfy({ $0.count <= 2_000 }) else {
            throw RevaError.invalid("Keep Details under 12,000 characters and each extra detail under 2,000 characters.")
        }
        return value
    }

    /// Exact labelled observations become the searchable, quotable source. Unset fields stay absent.
    var recordText: String {
        var lines = ["User symptom entry", "Self-reported by the user.", "Symptom: " + symptom,
                     "Occurred at: \(observedAt) (\(timeZone))"]
        if let severity { lines.append("Severity: " + severity.capitalized) }
        if !duration.isEmpty { lines.append("Duration: " + duration) }
        if !details.isEmpty { lines += ["Details:", details] }
        if !triggers.isEmpty { lines += ["Possible triggers:", triggers] }
        if !whatHelped.isEmpty { lines += ["What helped:", whatHelped] }
        return lines.joined(separator: "\n")
    }

    /// A concise display of supplied fields, without assigning a diagnosis or inferring severity.
    var localSummary: String {
        var lines = ["Symptom: " + symptom]
        if let severity { lines.append("Severity: " + severity.capitalized) }
        if !duration.isEmpty { lines.append("Duration: " + duration) }
        return lines.joined(separator: "\n")
    }

    func makeRecord(existingRecord: MedicalRecord? = nil, now: Date = Date()) throws -> MedicalRecord {
        let entry = try validated(now: now)
        if let existingRecord, existingRecord.symptomEntry == nil {
            throw RevaError.invalid("This source is not a symptom entry. Create a new entry to keep its original text intact.")
        }
        var record = existingRecord ?? MedicalRecord(title: entry.symptom, kind: "User symptom entry",
            provider: "Self-reported", date: entry.observedAt, text: entry.recordText, summary: entry.localSummary)
        record.title = entry.symptom
        record.kind = "User symptom entry"
        record.provider = "Self-reported"
        // The record list uses calendar dates; derive that day in the time zone of the observation.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: entry.timeZone)
        formatter.dateFormat = "yyyy-MM-dd"
        record.date = formatter.string(from: Self.timestamp(entry.observedAt)!)
        record.tags = Array(Set(record.tags + ["symptoms", "self-reported"])).sorted()
        record.text = entry.recordText
        record.summary = entry.localSummary
        record.summaryModel = nil
        record.symptomEntry = entry
        record.status = "ready"
        record.isDemo = false
        record.pageTexts = nil
        record.pageCount = 1
        return record
    }

    private static func timestamp(_ text: String) -> Date? {
        // Require a full ISO instant. Check the calendar day too: ISO parsers can normalize February 30.
        let pattern = #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let calendar = DateFormatter()
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)
        calendar.dateFormat = "yyyy-MM-dd"
        calendar.isLenient = false
        let day = String(text.prefix(10))
        guard let dateOnly = calendar.date(from: day), calendar.string(from: dateOnly) == day else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
    }
}
