import Foundation
import Sentry

@MainActor
enum SentryObservability {
    private static var hasStarted = false

    static func start() {
        guard !hasStarted else {
            return
        }

        guard let dsn = configuredValue(
            environmentKey: "PROMPT_PRODUCER_SENTRY_DSN",
            bundleKey: "SentryDSN"
        ) else {
            AppLog.sentry.info("Sentry disabled because PROMPT_PRODUCER_SENTRY_DSN is not configured")
            return
        }

        hasStarted = true
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = configuredValue(
                environmentKey: "PROMPT_PRODUCER_SENTRY_ENVIRONMENT",
                bundleKey: "SentryEnvironment"
            ) ?? "development"
            options.releaseName = releaseName
            options.debug = ProcessInfo.processInfo.environment["PROMPT_PRODUCER_SENTRY_DEBUG"] == "true"
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.1
        }
        SentrySDK.configureScope { scope in
            scope.setTag(value: "swiftpm-macos", key: "build_system")
            scope.setTag(value: "prompt-producer", key: "app")
        }
        AppLog.sentry.info("Sentry observability started")
    }

    static func capture(_ error: Error, context: String) {
        guard hasStarted else {
            return
        }

        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "context")
        }
    }

    static func captureMessage(_ message: String, context: String) {
        guard hasStarted else {
            return
        }

        SentrySDK.capture(message: message) { scope in
            scope.setTag(value: context, key: "context")
        }
    }

    private static var releaseName: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "prompt-producer@\(version)+\(build)"
    }

    private static func configuredValue(environmentKey: String, bundleKey: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return environmentValue
        }

        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleValue, !bundleValue.isEmpty {
            return bundleValue
        }

        return nil
    }
}
