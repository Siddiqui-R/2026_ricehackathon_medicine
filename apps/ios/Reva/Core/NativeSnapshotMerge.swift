// Three-way account merging retains independent edits and labels conflicting originals for recovery.
import CryptoKit
import Foundation

enum NativeSnapshotMerge {
    private typealias Object = [String: Any]
    private static func bytes(_ value: Any?) -> Data {
        (try? JSONSerialization.data(
            withJSONObject: value ?? NSNull(), options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
    }
    private static func equal(_ left: Any?, _ right: Any?) -> Bool { bytes(left) == bytes(right) }
    private static func object<T: Encodable>(_ value: T) throws -> Object {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! Object
    }
    private static func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        try JSONDecoder().decode(
            type, from: JSONSerialization.data(withJSONObject: value, options: .sortedKeys))
    }
    private static func fingerprint(_ value: Any) -> String {
        SHA256.hash(data: bytes(value)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    private static func combine(_ base: Any?, _ local: Any?, _ remote: Any?, conflict: inout Bool) -> Any? {
        if equal(local, remote) || equal(base, local) { return remote }
        if equal(base, remote) { return local }
        if let left = local as? [String], let right = remote as? [String] {
            let original = Set(base as? [String] ?? [])
            var seen = Set<String>()
            return (right + left).filter {
                seen.insert($0).inserted
                    && (!original.contains($0) || (left.contains($0) && right.contains($0)))
            }
        }
        if let left = local as? Object, let right = remote as? Object {
            let original = base as? Object ?? [:]
            var result: Object = [:]
            for key in Set(left.keys).union(right.keys) {
                if key == "version", let a = left[key] as? Int, let b = right[key] as? Int {
                    result[key] = max(a, b)
                } else if key == "aiMedicalHistory" {
                    result[key] = equal(original[key], right[key]) ? left[key] : right[key]
                } else {
                    result[key] = combine(original[key], left[key], right[key], conflict: &conflict)
                }
            }
            return result
        }
        conflict = true
        return remote
    }
    private static func collection(
        _ base: [Object], _ local: [Object], _ remote: [Object], recovered: inout Int
    ) -> [Object] {
        let original = Dictionary(uniqueKeysWithValues: base.map { ($0["id"] as! String, $0) })
        let here = Dictionary(uniqueKeysWithValues: local.map { ($0["id"] as! String, $0) })
        let there = Dictionary(uniqueKeysWithValues: remote.map { ($0["id"] as! String, $0) })
        var result: [String: Object] = [:]
        for id in Set(here.keys).union(there.keys).sorted() {
            let before = original[id]
            guard let left = here[id], let right = there[id] else {
                let remaining = here[id] ?? there[id]!
                if before == nil || !equal(before, remaining) { result[id] = remaining }
                continue
            }
            var conflict = false
            var merged = combine(before, left, right, conflict: &conflict) as! Object
            if merged["version"] != nil, !equal(merged, left), !equal(merged, right) {
                merged["version"] = max(left["version"] as? Int ?? 0, right["version"] as? Int ?? 0) + 1
            }
            result[id] = merged
            if conflict {
                var copy = left
                let copyID = "sync-copy-" + fingerprint([id, left] as [Any])
                copy["id"] = copyID
                if let title = copy["title"] as? String {
                    copy["title"] = title + " (saved on another device)"
                }
                if var report = copy["report"] as? Object {
                    report["id"] = copyID + "-report"
                    report["visitID"] = copyID
                    copy["report"] = report
                }
                if here[copyID] == nil && there[copyID] == nil { recovered += 1 }
                result[copyID] = copy
            }
        }
        return result.keys.sorted().compactMap { result[$0] }
    }
    private static func manual(_ profile: PatientProfile) -> PatientProfile {
        var copy = profile
        for field in MedicalProfileField.allCases {
            let generated = Set(
                field.facts(profile.aiMedicalHistory?.facts ?? NativeMedicalProfile.emptyFacts).map {
                    NativeMedicalProfile.key($0.text)
                })
            field.set(
                field.values(profile).filter { !generated.contains(NativeMedicalProfile.key($0)) }, in: &copy)
        }
        copy.aiMedicalHistory = nil
        return copy
    }
    private static func mergeProfile(
        _ base: PatientProfile?, _ local: PatientProfile, _ remote: PatientProfile, conflict: inout Bool
    ) throws -> PatientProfile {
        let generated =
            base?.aiMedicalHistory != nil || local.aiMedicalHistory != nil || remote.aiMedicalHistory != nil
        let before = try base.map { try object(generated ? manual($0) : $0) }
        let value = combine(
            before, try object(generated ? manual(local) : local),
            try object(generated ? manual(remote) : remote), conflict: &conflict)!
        var merged = try decode(value, as: PatientProfile.self)
        let history =
            remote.aiMedicalHistory == nil
            ? local.aiMedicalHistory
            : local.aiMedicalHistory == nil
                ? remote.aiMedicalHistory
                : base?.aiMedicalHistory == remote.aiMedicalHistory
                    ? local.aiMedicalHistory : remote.aiMedicalHistory
        guard var history else { return merged }
        var omitted: [String: [String]] = [:]
        var sources: [String: [String]] = [:]
        for field in MedicalProfileField.allCases {
            var texts = Set<String>()
            var ids = Set<String>()
            for profile in [local, remote] {
                texts.formUnion(profile.aiMedicalHistory?.suppressed?[field.rawValue] ?? [])
                ids.formUnion(profile.aiMedicalHistory?.suppressedRecordIDs?[field.rawValue] ?? [])
                let kept = Set(field.values(profile).map(NativeMedicalProfile.key))
                for fact in field.facts(profile.aiMedicalHistory?.facts ?? NativeMedicalProfile.emptyFacts)
                where !kept.contains(NativeMedicalProfile.key(fact.text)) {
                    texts.insert(NativeMedicalProfile.key(fact.text))
                    ids.formUnion(fact.recordIDs)
                }
            }
            omitted[field.rawValue] = texts.sorted()
            sources[field.rawValue] = ids.sorted()
        }
        let result = NativeProfileResult(
            allergies: history.facts.allergies, medications: history.facts.medications,
            conditions: history.facts.conditions, surgeriesAndImplants: history.facts.surgeriesAndImplants,
            careNotes: history.facts.careNotes, model: history.model)
        history.facts = NativeMedicalProfile.emptyFacts
        history.suppressed = omitted
        history.suppressedRecordIDs = sources
        merged.aiMedicalHistory = history
        return NativeMedicalProfile.apply(
            result, to: merged, signature: history.sourceSignature, at: history.generatedAt)
    }
    static func merge(base: AppSnapshot?, local: AppSnapshot, remote: AppSnapshot) throws -> (
        snapshot: AppSnapshot, recovered: Int
    ) {
        try local.validate()
        try remote.validate()
        try base?.validate()
        guard local.profile.id == remote.profile.id, base == nil || base?.profile.id == local.profile.id
        else {
            throw RevaError.invalid("The server returned a different account. Your local records were kept.")
        }
        let before = try base.map(object) ?? [:]
        let here = try object(local)
        let there = try object(remote)
        var result = there
        var recovered = 0
        var profileConflict = false
        result["profile"] = try object(
            mergeProfile(base?.profile, local.profile, remote.profile, conflict: &profileConflict))
        for key in ["records", "visits", "bookings", "recordings"] {
            result[key] = collection(
                before[key] as? [Object] ?? [], here[key] as? [Object] ?? [], there[key] as? [Object] ?? [],
                recovered: &recovered)
        }
        var snapshot = try decode(result, as: AppSnapshot.self)
        func copiedID<T: Encodable & Identifiable>(_ value: T) throws -> String where T.ID == String {
            "sync-copy-" + fingerprint([value.id, try object(value)] as [Any])
        }
        for original in local.recordings {
            let copyID = try copiedID(original)
            if let index = snapshot.recordings.firstIndex(where: { $0.id == copyID }),
                let visit = local.visits.first(where: { $0.id == original.visitID })
            {
                let visitCopy = try copiedID(visit)
                if snapshot.visits.contains(where: { $0.id == visitCopy }) {
                    snapshot.recordings[index].visitID = visitCopy
                }
            }
        }
        for original in local.records {
            let copyID = try copiedID(original)
            if let index = snapshot.records.firstIndex(where: { $0.id == copyID }),
                let recording = local.recordings.first(where: { $0.id == original.sourceRecordingID })
            {
                let recordingCopy = try copiedID(recording)
                if snapshot.recordings.contains(where: { $0.id == recordingCopy }) {
                    snapshot.records[index].sourceRecordingID = recordingCopy
                }
            }
        }
        if profileConflict {
            var values = try object(local.profile)
            values.removeValue(forKey: "aiMedicalHistory")
            let id = "sync-profile-" + fingerprint(values)
            if !snapshot.records.contains(where: { $0.id == id }) {
                snapshot.records.append(
                    MedicalRecord(
                        id: id, title: "Medical profile saved on another device", kind: "Sync recovery",
                        provider: "", date: RevaDate.now, tags: ["sync recovery"],
                        text: "Original profile values preserved after simultaneous edits.\n\n"
                            + String(decoding: bytes(values), as: UTF8.self),
                        summary: "A preserved copy of conflicting profile edits. Review before using.",
                        status: "needs review",
                        notes: "This recovery copy is not a medical report or new clinical evidence.",
                        isDemo: local.profile.isDemo))
                recovered += 1
            }
        }
        // Preserve parent visits when an edit or a recording races a deletion.
        for id in snapshot.recordings.map(\.visitID) + snapshot.bookings.map(\.visitID)
        where !id.isEmpty && !snapshot.visits.contains(where: { $0.id == id }) {
            if let visit = (local.visits + remote.visits + (base?.visits ?? [])).first(where: { $0.id == id })
            {
                snapshot.visits.append(visit)
            }
        }
        let ids = Set(snapshot.records.map(\.id))
        for index in snapshot.visits.indices {
            snapshot.visits[index].pinnedRecordIDs.removeAll { !ids.contains($0) }
        }
        try snapshot.validate()
        return (snapshot, recovered)
    }
}
