import Foundation
import NIOCore
import NIOConcurrencyHelpers

/// Simple in-memory sessions implementation.
public actor MemorySessions: SessionDriver, Sendable {
    
    private var sessions: [SessionID: SessionData]
    
    public init() {
        self.sessions = .init()
    }
    
    public func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
        let sessionID = self.generateID()
        self.sessions[sessionID] = data
        return sessionID
    }
    
    public func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
        self.sessions[sessionID]
    }
    
    public func updateSession(_ sessionID: SessionID, to data: SessionData, for request: Request) async throws -> SessionID {
        self.sessions[sessionID] = data
        return sessionID
    }
    
    public func deleteSession(_ sessionID: SessionID, for request: Request) async throws {
        self.sessions[sessionID] = nil
    }
    
    private func generateID() -> SessionID {
        return .init(string: [UInt8].random(count: 32).base64String())
    }
}
