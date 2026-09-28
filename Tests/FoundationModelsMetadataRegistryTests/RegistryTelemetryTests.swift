@testable import FoundationModelsMetadataRegistry
import InMemoryTracing
import Testing
import Tracing

/// ``RegistryTelemetry/tracer(explicit:)`` gives the explicit tracer when a
/// caller sets one, and else reads the tracer of the call site at the call.
///
/// No test of this suite bootstraps a tracing backend. `withTracer(_:_:)`
/// binds a tracer to the task, and `InstrumentationSystem.tracer` reads that
/// task-local tracer first.
@Suite("RegistryTelemetry.tracer(explicit:)")
struct RegistryTelemetryTests {
    @Test("An explicit tracer is the tracer that the call uses")
    func usesTheExplicitTracer() {
        let tracer = RegistryTelemetry.tracer(explicit: InMemoryTracer())

        #expect(tracer is InMemoryTracer)
    }

    @Test("Without an explicit tracer, the call reads the tracer of the task at the call")
    func readsTheTaskTracerAtTheCall() {
        let tracer = withTracer(InMemoryTracer()) {
            RegistryTelemetry.tracer(explicit: nil)
        }

        #expect(tracer is InMemoryTracer)
    }
}
