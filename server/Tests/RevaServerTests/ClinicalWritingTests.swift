// Purpose: Reject prose about a source while preserving direct care themes and meaningful qualifiers.
// Uses fictional text only; no provider requests or persisted profile edits.
import Testing
@testable import RevaServer

@Suite("Direct clinical themes")
struct ClinicalWritingTests {
    @Test func sourceNarrationIsRejected() throws {
        for text in [
            "The transcript discusses sock changing frequency and hygiene topics.",
            "The recording mentions poor general hygiene.",
            "The report describes possible foot fungus.",
            "Sock changes were discussed in the conversation.",
            "Care notes: this document covers hygiene.",
        ] {
            do {
                try ClinicalWriting.validateGeneratedText(text, label: "careNotes")
                Issue.record("Expected source narration to be rejected")
            } catch let error as ClinicalWriting.ValidationError {
                #expect(error.violation == .sourceFraming)
                #expect(error.field == "careNotes")
            }
        }
    }

    @Test func directThemesAndClinicalAttributionRemainValid() throws {
        for text in [
            "Frequent sock changes to prevent foot fungus, poor general hygiene",
            "Sock-changing frequency and hygiene",
            "Patient-reported difficulty with foot hygiene; possible fungal infection",
            "Question about whether more frequent sock changes could help",
            "September 1 report: no allergies; September 2 report: penicillin allergy (conflicting documentation)",
        ] {
            try ClinicalWriting.validateGeneratedText(text, label: "careNotes")
        }
    }
}
