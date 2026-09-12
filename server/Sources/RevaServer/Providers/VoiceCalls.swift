// Purpose: Place explicitly consented scheduling calls while preventing automatic duplicate attempts.
// Inputs: Authenticated owner, stable call request ID/payload, server agent/number settings, and durable storage.
// Outputs: Provider conversation status/transcript or a safe uncertain/conflict/storage error.
// Side effects: Persists intent before dialing, calls/polls ElevenLabs, and retains receipts across restarts.
// Boundary: Receipts are independent of snapshot deletion and PostgreSQL mode. Call completion never confirms a visit.

import Foundation
import Vapor

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// MARK: - Consent-bearing call contract and scheduling bounds
struct VoiceBookingCallRequest: Content, Sendable, Equatable {
    let requestID: String
    let clinic: String
    let phone: String
    let reason: String
    let earliest: String
    let latest: String
    let timeZone: String
    let preferences: String
    let patientName: String
    let consent: Bool

    func validate() throws {
        guard consent else {
            throw Abort(.badRequest, reason: "Explicit consent is required before placing a real call.")
        }
        guard Validation.safeID(requestID) else {
            throw Abort(
                .badRequest,
                reason:
                    "requestID must be a stable safe identifier (1–80 ASCII letters, numbers, hyphens or underscores)."
            )
        }
        let digits = Array(phone.utf8)
        guard (3...16).contains(digits.count), digits.first == 43, (49...57).contains(digits[1]),
            digits.dropFirst(2).allSatisfy({ (48...57).contains($0) })
        else {
            throw Abort(
                .badRequest,
                reason: "Use an exact E.164 phone number, such as +13125550123, without spaces or extensions."
            )
        }
        for (value, limit) in [(clinic, 200), (reason, 2_000), (patientName, 200)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= limit else {
                throw Abort(
                    .badRequest, reason: "Provide a clinic, patient name, and concise appointment reason.")
            }
        }
        guard preferences.count <= 2_000, timeZone.count <= 100, TimeZone(identifier: timeZone) != nil,
            earliest.count <= 50, latest.count <= 50,
            let start = Self.date(earliest), let end = Self.date(latest), start <= end
        else {
            throw Abort(
                .badRequest,
                reason:
                    "Provide valid ISO 8601 appointment bounds, a valid time zone, and concise preferences.")
        }
    }

    private static func date(_ value: String) -> Date? {
        let format = ISO8601DateFormatter()
        if let date = format.date(from: value) { return date }
        format.formatOptions.insert(.withFractionalSeconds)
        return format.date(from: value)
    }
}

// MARK: - Public call status and transcript responses
struct VoiceBookingCallResponse: Content, Sendable, Equatable {
    let conversationID: String
    let status: String
    let provider: String
}

struct VoiceBookingCallDetails: Content, Sendable, Equatable {
    let conversationID: String
    let status: String
    let provider: String
    let transcript: String
}

// MARK: - Durable owner-scoped call state machine
/// One service/server instance per durable directory. Receipts must survive deployments/restarts.
/// Intent is synced before the outbound HTTP request. Replays/uncertain attempts never redial.
/// State deletion does not delete receipts: removing them would remove duplicate-call protection.
/// No provider outcome creates or confirms a Reva appointment; the caller must review it manually.
/// Official APIs:
/// https://elevenlabs.io/docs/api-reference/integrations/twilio/outbound-call
/// https://elevenlabs.io/docs/api-reference/conversations/get
actor VoiceCallService {
    private let configuration: ProviderConfiguration
    private let transport: VoiceHTTPTransport
    private let directory: URL
    private var directoryLock: VoiceReceiptDirectoryLock?
    private static let provider = "ElevenLabs"
    private static let providerStatuses: Set<String> = [
        "initiated", "in-progress", "processing", "done", "failed",
    ]

    init(configuration: ProviderConfiguration, directory: URL, transport: VoiceHTTPTransport = .live) {
        self.configuration = configuration
        self.directory = directory.appendingPathComponent("voice-call-receipts", isDirectory: true)
        self.transport = transport
    }

    // MARK: - Validate authorization and reject changed or uncertain replays
    func start(owner: String, call: VoiceBookingCallRequest) async throws -> VoiceBookingCallResponse {
        guard configuration.bookingConfigured, configuration.liveCallsEnabled,
            let key = configuration.elevenLabsAPIKey, let agent = configuration.elevenLabsAgentID,
            let number = configuration.elevenLabsPhoneNumberID
        else {
            throw Abort(
                .serviceUnavailable,
                reason:
                    "Live calling is disabled. Configure private server tokens, ElevenLabs key/agent/phone-number IDs, and REVA_ENABLE_LIVE_CALLS=true."
            )
        }
        try call.validate()
        try validateOwner(owner)
        if let existing = try read(owner: owner, requestID: call.requestID) {
            guard existing.request == call else {
                throw Abort(
                    .conflict,
                    reason:
                        "This requestID already belongs to a different call request. It will not dial again.")
            }
            guard let id = existing.conversationID else { throw uncertainReplay() }
            return VoiceBookingCallResponse(
                conversationID: id, status: existing.status, provider: Self.provider)
        }
        // MARK: - Persist intent before the first suspension or external dial
        // Another task can enter this actor during transport awaits, so the persisted intent must already exist.
        try Task.checkCancellation()
        var receipt = VoiceCallReceipt(
            owner: owner, request: call, status: "intent", conversationID: nil, createdAt: Date())
        try write(receipt)  // Must complete durably before entering an await/provider side effect.

        // MARK: - Build a fixed-agent outbound call from reviewed scheduling fields
        // The configured agent must use these variables in its reviewed scheduling prompt.
        // No arbitrary host, phone-number provider ID, or agent override comes from the client.
        let payload = ElevenOutboundPayload(
            agent_id: agent, agent_phone_number_id: number, to_number: call.phone,
            conversation_initiation_client_data: ElevenInitiationData(dynamic_variables: [
                "request_id": call.requestID, "clinic_name": call.clinic, "patient_name": call.patientName,
                "appointment_reason": call.reason, "earliest": call.earliest, "latest": call.latest,
                "time_zone": call.timeZone, "preferences": call.preferences,
            ]), call_recording_enabled: false)
        var request = URLRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/convai/twilio/outbound-call")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        // MARK: - Commit a conversation receipt or retain a fail-closed uncertain intent
        do {
            let raw = try await transport.send(request)
            let bytes = try VoiceProviderLimits.responseData(raw)
            let response = try JSONDecoder().decode(ElevenOutboundResponse.self, from: bytes)
            if let id = response.conversation_id, Self.safeConversationID(id) { receipt.conversationID = id }
            guard response.success, receipt.conversationID != nil else { throw uncertainReplay() }
            receipt.status = "initiated"
            try write(receipt)
            return VoiceBookingCallResponse(
                conversationID: receipt.conversationID!, status: receipt.status, provider: Self.provider)
        } catch {
            // A timeout, unexpected body, or failed receipt update does not establish that no call occurred.
            receipt.status = "uncertain"
            try? write(receipt)  // If this fails, the already durable intent still blocks every replay.
            throw Abort(
                .badGateway,
                reason:
                    "The call outcome could not be confirmed. This request will not dial again. Check ElevenLabs before authorizing any new call."
            )
        }
    }

    // MARK: - Poll an existing owner receipt without placing a call
    func details(owner: String, requestID: String) async throws -> VoiceBookingCallDetails {
        try validateOwner(owner)
        guard Validation.safeID(requestID) else {
            throw Abort(.badRequest, reason: "Invalid call request ID.")
        }
        guard var receipt = try read(owner: owner, requestID: requestID) else {
            throw Abort(.notFound, reason: "No call request exists for this owner.")
        }
        guard let id = receipt.conversationID else {
            return VoiceBookingCallDetails(
                conversationID: "", status: "uncertain", provider: Self.provider, transcript: "")
        }
        // Disabling new calls does not prevent the owner from checking a previously submitted call.
        guard configuration.paidAccessAllowed, let key = configuration.elevenLabsAPIKey else {
            throw Abort(
                .serviceUnavailable,
                reason: "Configure the private ElevenLabs server key to retrieve this call.")
        }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/convai/conversations/" + id)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: VoiceHTTPResponse
        do { response = try await transport.send(request) } catch {
            throw Abort(
                .badGateway,
                reason:
                    "Call status could not be retrieved. The original call request was preserved; polling will not place another call."
            )
        }
        let data = try VoiceProviderLimits.responseData(response)
        let details: ElevenConversationResponse
        do { details = try JSONDecoder().decode(ElevenConversationResponse.self, from: data) } catch {
            throw Abort(.badGateway, reason: "ElevenLabs returned invalid conversation data.")
        }
        guard details.conversation_id == id, Self.providerStatuses.contains(details.status),
            details.transcript.count <= 10_000
        else {
            throw Abort(.badGateway, reason: "ElevenLabs returned an unexpected conversation or status.")
        }
        // MARK: - Validate and bound the returned conversation text
        var transcript = ""
        for turn in details.transcript {
            guard let message = turn.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            guard turn.time_in_call_secs.isFinite, turn.time_in_call_secs >= 0,
                turn.time_in_call_secs <= 24 * 60 * 60
            else {
                throw Abort(.badGateway, reason: "ElevenLabs returned invalid conversation timestamps.")
            }
            let role = turn.role == "agent" ? "Agent" : turn.role == "user" ? "User" : "Speaker"
            let seconds = Int(turn.time_in_call_secs)
            let stamp = String(format: "%d:%02d", seconds / 60, seconds % 60)
            let line = "[\(stamp)] \(role): \(message)\n\n"
            let remaining = max(0, VoiceProviderLimits.transcriptCharacters - 100 - transcript.count)
            if line.count > remaining {
                transcript +=
                    String(line.prefix(remaining))
                    + "\n[Transcript shortened. Review the complete conversation in ElevenLabs.]"
                break
            }
            transcript += line
        }
        receipt.status = details.status
        try write(receipt)
        return VoiceBookingCallDetails(
            conversationID: id, status: details.status, provider: Self.provider,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Safe lookup identifiers and explicit uncertain-replay failures
    private func validateOwner(_ owner: String) throws {
        guard Validation.safeID(owner) else {
            throw Abort(.unauthorized, reason: "A valid owner is required.")
        }
    }

    private func uncertainReplay() -> Abort {
        Abort(
            .conflict,
            reason:
                "A durable call intent already exists, but its outcome is uncertain. This request will not dial again; review ElevenLabs before any new call."
        )
    }

    private static func safeConversationID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200
            && value.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
                    || $0 == 95
            }
    }

    // MARK: - Acquire one writer before reading or creating receipts
    private func ensureDirectory() throws {
        guard directoryLock == nil else { return }
        do {
            guard directory.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            directoryLock = try VoiceReceiptDirectoryLock(directory: directory)
        } catch {
            throw Abort(
                .serviceUnavailable,
                reason:
                    "Call receipt storage is unavailable or already in use by another server instance. No new call was placed."
            )
        }
    }

    private func file(owner: String, requestID: String) -> URL {
        directory.appendingPathComponent(owner, isDirectory: true).appendingPathComponent(requestID + ".json")
    }

    // MARK: - Verify persisted receipt identity and state before trusting it
    private func read(owner: String, requestID: String) throws -> VoiceCallReceipt? {
        try ensureDirectory()
        let url = file(owner: owner, requestID: requestID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 64 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let receipt = try JSONDecoder().decode(VoiceCallReceipt.self, from: Data(contentsOf: url))
            guard receipt.version == 1, receipt.owner == owner, receipt.request.requestID == requestID,
                ["intent", "uncertain", "initiated", "in-progress", "processing", "done", "failed"].contains(
                    receipt.status),
                receipt.conversationID.map(Self.safeConversationID) ?? true
            else { throw CocoaError(.fileReadCorruptFile) }
            return receipt
        } catch {
            throw Abort(
                .serviceUnavailable,
                reason:
                    "The existing call receipt cannot be verified. No new call will be placed; inspect receipt storage."
            )
        }
    }

    // MARK: - Commit receipt contents and directory entries before returning
    // Failures preserve the previous receipt or durable intent and must never authorize a new automatic attempt.
    private func write(_ receipt: VoiceCallReceipt) throws {
        try ensureDirectory()
        let target = file(owner: receipt.owner, requestID: receipt.request.requestID)
        let ownerDirectory = target.deletingLastPathComponent()
        let temporary = ownerDirectory.appendingPathComponent(".pending-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(
                at: ownerDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(receipt)
            guard
                FileManager.default.createFile(
                    atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            defer { try? FileManager.default.removeItem(at: temporary) }
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard rename(temporary.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            // Persist both the receipt rename and a newly created owner-directory entry before dialing.
            for folder in [ownerDirectory, directory, directory.deletingLastPathComponent()] {
                let descriptor = open(folder.path, O_RDONLY)
                guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
                let result = fsync(descriptor)
                close(descriptor)
                guard result == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            throw Abort(
                .serviceUnavailable,
                reason:
                    "The durable call receipt could not be saved. Do not retry with a new request ID until the provider outcome is checked."
            )
        }
    }
}

// MARK: - Persistent replay record independent of patient snapshot storage
private struct VoiceCallReceipt: Codable, Sendable {
    var version = 1
    let owner: String
    let request: VoiceBookingCallRequest
    var status: String
    var conversationID: String?
    let createdAt: Date
}

// MARK: - Cross-process exclusion for call receipts
private final class VoiceReceiptDirectoryLock: @unchecked Sendable {
    private let descriptor: Int32
    init(directory: URL) throws {
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }
        self.descriptor = descriptor
    }
    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

// MARK: - Provider-specific wire schemas kept behind the Reva contract
private struct ElevenOutboundPayload: Encodable {
    let agent_id: String
    let agent_phone_number_id: String
    let to_number: String
    let conversation_initiation_client_data: ElevenInitiationData
    let call_recording_enabled: Bool
}
private struct ElevenInitiationData: Encodable { let dynamic_variables: [String: String] }
private struct ElevenOutboundResponse: Decodable {
    let success: Bool
    let conversation_id: String?
}
private struct ElevenConversationResponse: Decodable {
    let conversation_id: String
    let status: String
    let transcript: [ElevenConversationTurn]
}
private struct ElevenConversationTurn: Decodable {
    let role: String
    let time_in_call_secs: Double
    let message: String?
}
