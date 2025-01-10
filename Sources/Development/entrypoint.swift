import Vapor
import Logging

@main
struct Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = await Application(env)
        do {
            try await configure(app)
            try await app.start()
            try await app.shutdown()
        } catch {
            try? await app.shutdown()
            throw error
        }
    }
}

