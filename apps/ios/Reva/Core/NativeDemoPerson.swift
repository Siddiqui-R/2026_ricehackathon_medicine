// Demo identities match the browser examples; each native workspace has its own persistence directory.
import Foundation

enum NativeDemoPerson: String, CaseIterable, Identifiable {
    case jordan, maya, alex
    var id: String { rawValue }
    var name: String {
        switch self {
        case .jordan: return "Jordan Avery"
        case .maya: return "Maya Patel"
        case .alex: return "Alex Chen"
        }
    }
    var initials: String {
        switch self {
        case .jordan: return "JA"
        case .maya: return "MP"
        case .alex: return "AC"
        }
    }
    var detail: String {
        switch self {
        case .jordan: return "Primary care and symptom follow-up"
        case .maya: return "Headache patterns and neurology preparation"
        case .alex: return "Knee recovery and physical therapy"
        }
    }
    func snapshot(from base: AppSnapshot) -> AppSnapshot {
        guard self != .jordan else { return base }
        let maya = self == .maya
        let profile = PatientProfile(
            id: "demo-profile-" + rawValue, name: name,
            dateOfBirth: maya ? "1997-03-22" : "1983-11-08", initials: initials,
            allergies: maya ? ["No known allergies recorded"] : ["Adhesive tape — skin irritation"],
            medications: [],
            conditions: maya ? ["Recurring headaches"] : ["Left knee recovery after ACL reconstruction"],
            isDemo: true, surgeriesAndImplants: maya ? [] : ["Left ACL reconstruction, July 2026"],
            careNotes: maya
                ? "Discuss headache frequency and its effect on work."
                : "Review recovery goals and return to usual activities.")
        let entries: [(String, String, [String])] =
            maya
            ? [
                (
                    "Headache pattern — September",
                    "Headaches occurred on three afternoons this week. Bright office lighting was bothersome. Resting in a quiet room helped. Duration ranged from one to three hours.",
                    ["headache", "neurology", "symptoms"]
                ),
                (
                    "Sleep and daily routine",
                    "Sleep has varied between six and eight hours. Two headache days followed late nights. No consistent food-related pattern has been identified.",
                    ["headache", "sleep", "routine"]
                ),
                (
                    "Previous headache appointment",
                    "A prior primary-care visit discussed recurring headaches. The patient was asked to bring a record of timing, duration and associated symptoms to the next appointment.",
                    ["headache", "primary care", "follow-up"]
                ),
            ]
            : [
                (
                    "Knee recovery notes",
                    "Left ACL reconstruction was completed in July 2026. The next orthopedic visit will review recovery progress and questions about returning to usual activities.",
                    ["knee", "surgery", "orthopedics"]
                ),
                (
                    "Physical therapy update",
                    "Physical therapy sessions have focused on mobility and strength. The patient reports that stairs are becoming easier, with stiffness after long periods sitting.",
                    ["knee", "physical therapy", "mobility"]
                ),
                (
                    "Activity and symptoms",
                    "The left knee feels stiff in the morning and after sitting. The patient wants to discuss walking distance and the recovery timeline at the next visit.",
                    ["knee", "stiffness", "symptoms"]
                ),
            ]
        let records = entries.enumerated().map { index, item in
            MedicalRecord(
                id: "demo-\(rawValue)-record-\(index + 1)", title: item.0, kind: "Notes",
                provider: index == 2 && maya
                    ? "Dr. Leah Brooks"
                    : index == 1 && !maya ? "Cedar Physical Therapy" : "Personal health notes",
                date: "2026-09-0\(9 - index)", uploadedAt: "2026-09-12T12:00:00Z", tags: item.2,
                text: item.1, summary: item.1, isDemo: true)
        }
        let visit = Visit(
            id: "demo-\(rawValue)-visit", title: maya ? "Headache follow-up" : "Knee recovery follow-up",
            type: maya ? "Neurology" : "Orthopedics", provider: maya ? "Dr. Leah Brooks" : "Dr. Evan Park",
            clinic: maya ? "Maple Neurology" : "Cedar Orthopedics", date: "2026-09-17T10:00:00-05:00",
            concern: maya ? "Recurring headaches affecting work" : "Knee stiffness during recovery",
            goal: maya
                ? "Understand headache patterns and discuss next steps"
                : "Review recovery progress and activity goals",
            questions: maya
                ? [
                    "What details should I track about my headaches?",
                    "What should we discuss about their effect on work?",
                ]
                : [
                    "How is my recovery progressing?",
                    "What should I discuss with my physical therapist next?",
                ],
            pinnedRecordIDs: [records[0].id])
        return AppSnapshot(profile: profile, records: records, visits: [visit])
    }
}
