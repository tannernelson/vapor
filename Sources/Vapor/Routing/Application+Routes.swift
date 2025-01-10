extension Application {
    public var routes: Routes {
        get {
            if let existing = self.storage[RoutesKey.self] {
                return existing
            } else {
                let new = Routes()
                self.storage.setFirstTime(RoutesKey.self, to: new)
                return new
            }
        }
    }

    private struct RoutesKey: StorageKey {
        typealias Value = Routes
    }
}
