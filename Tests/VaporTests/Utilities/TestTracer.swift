import Tracing

final class TestTracer: Tracer {
    typealias Span = TestSpan
    
    static let extractKey = "to-extract"
    var spans: [TestSpan] = []
    
    func startSpan(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> some TracerInstant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> TestSpan {
        let span = TestSpan(
            operationName,
            context: context()
        )
        self.spans.append(span)
        return span
    }
    
    func forceFlush() {
        return
    }
    
    func extract<Carrier, Extract>(_ carrier: Carrier, into context: inout ServiceContextModule.ServiceContext, using extractor: Extract) where Carrier == Extract.Carrier, Extract : Instrumentation.Extractor {
        context.extracted = extractor.extract(key: Self.extractKey, from: carrier)
        return
    }
    
    func inject<Carrier, Inject>(_ context: ServiceContextModule.ServiceContext, into carrier: inout Carrier, using injector: Inject) where Carrier == Inject.Carrier, Inject : Instrumentation.Injector {
        return
    }
}

final class TestSpan: Span {
    let context: ServiceContext
    var operationName: String
    var attributes: Tracing.SpanAttributes = .init()
    var isRecording: Bool = true
    
    private var status: SpanStatus?
    private var events: [SpanEvent] = []
    
    init (_ operationName: String, context: ServiceContext) {
        self.operationName = operationName
        self.context = context
    }
    
    func setStatus(_ status: SpanStatus) {
        self.status = status
    }
    
    func addEvent(_ event: SpanEvent) {
        events.append(event)
    }
    
    func recordError<Instant>(_ error: any Error, attributes: Tracing.SpanAttributes, at instant: @autoclosure () -> Instant) where Instant : Tracing.TracerInstant {
        return
    }
    
    func addLink(_ link: Tracing.SpanLink) {
        return
    }
    
    func end<Instant>(at instant: @autoclosure () -> Instant) where Instant : Tracing.TracerInstant {
        isRecording = false
    }
}

extension TestTracer: @unchecked Sendable {}
extension TestSpan: @unchecked Sendable {}

extension ServiceContext {
    var extracted: String? {
        get {
            self[ExtractedKey.self]
        } set {
            self[ExtractedKey.self] = newValue
        }
    }
    
    private enum ExtractedKey: ServiceContextKey {
        typealias Value = String
    }
}
