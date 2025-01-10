/// Provides a way to hook into lifecycle events of a Vapor application. You can register
/// your handlers with the ``Application`` to be notified when the application
/// is about to start up, has started up and is about to shutdown
///
/// For example
/// ```swift
///  struct LifecycleLogger: LifecycleHander {
///    func willBoot(_ application: Application) async throws {
///        application.logger.info("Application about to boot up")
///    }
///
///    func didBoot(_ application: Application) async throws {
///        application.logger.info("Application has booted up")
///    }
///
///    func shutdown(_ application: Application) async {
///        application.logger.info("Will shutdown")
///    }
///  }
/// ```
///
/// You can then register your handler with the application:
///
/// ```swift
/// application.lifecycle.use(LifecycleLogger())
/// ```
///
public protocol LifecycleHandler: Sendable {
    /// Called when the application is about to boot up
    func willBoot(_ application: Application) async throws
    /// Called when the application has booted up
    func didBoot(_ application: Application) async throws
    /// Called when the application is about to shutdown
    func shutdown(_ application: Application) async
}

extension LifecycleHandler {
    public func willBoot(_ application: Application) async throws { }
    public func didBoot(_ application: Application) async throws { }
    public func shutdown(_ application: Application) async { }
}
