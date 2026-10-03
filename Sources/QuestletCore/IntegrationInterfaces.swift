import Foundation

public enum IntegrationErrorCode: String, Codable, Sendable {
    case invalidInput, authentication, permission, notFound, unsupportedTransition
    case configuration, connection, rateLimited, timeout, cancelled, invalidResponse, remoteFailure
}
public enum RemoteEffect: String, Codable, Sendable { case notApplied, unknown }
public struct IntegrationFailure: Error, Codable, Sendable {
    public let code: IntegrationErrorCode
    public let message: String
    public let effect: RemoteEffect
    public var retryAfterSeconds: Int?
    public init(code: IntegrationErrorCode, message: String, effect: RemoteEffect = .notApplied, retryAfterSeconds: Int? = nil) {
        self.code = code; self.message = message; self.effect = effect; self.retryAfterSeconds = retryAfterSeconds
    }
}
public enum JiraMutation: Codable, Sendable {
    case setDates(startDate: String, endDate: String)
    case setStatus(TaskStatus)
    case appendComment(localCommentID: UUID, body: String)
    public var isComment: Bool { if case .appendComment = self { return true }; return false }
    public var category: String { switch self { case .setDates: "dates"; case .setStatus: "status"; case .appendComment: "comment" } }
}
public struct JiraRequest: Codable, Sendable {
    public let requestID: UUID
    public let ticketKey: String
    public let mutation: JiraMutation
    public init(requestID: UUID = UUID(), ticketKey: String, mutation: JiraMutation) {
        self.requestID = requestID; self.ticketKey = ticketKey; self.mutation = mutation
    }
}
public struct JiraReceipt: Sendable {
    public let requestID: UUID
    public let ticketKey: String
    public let simulated: Bool
    public let remoteCommentID: String?
    public init(requestID: UUID, ticketKey: String, simulated: Bool, remoteCommentID: String? = nil) {
        self.requestID = requestID; self.ticketKey = ticketKey; self.simulated = simulated; self.remoteCommentID = remoteCommentID
    }
}
public protocol JiraTicketModule: Sendable {
    func execute(_ request: JiraRequest) async -> Result<JiraReceipt, IntegrationFailure>
}
public struct SRDRequest: Sendable {
    public let requestID: UUID
    public let prd: String
    public let title: String
    public let parentPageLink: String
    public init(requestID: UUID = UUID(), prd: String, title: String, parentPageLink: String) {
        self.requestID = requestID; self.prd = prd; self.title = title; self.parentPageLink = parentPageLink
    }
}
public struct RPRequest: Sendable {
    public let requestID: UUID
    public let roles: [String]
    public let prdURL: URL
    public init(requestID: UUID = UUID(), roles: [String], prdURL: URL) { self.requestID = requestID; self.roles = roles; self.prdURL = prdURL }
}
public struct WikiReceipt: Sendable {
    public let requestID: UUID
    public let wikiURL: URL
    public let simulated: Bool
    public init(requestID: UUID, wikiURL: URL, simulated: Bool) { self.requestID = requestID; self.wikiURL = wikiURL; self.simulated = simulated }
}
public protocol SRDGenerationModule: Sendable { func generate(_ request: SRDRequest) async -> Result<WikiReceipt, IntegrationFailure> }
public protocol RPGenerationModule: Sendable { func generate(_ request: RPRequest) async -> Result<WikiReceipt, IntegrationFailure> }
