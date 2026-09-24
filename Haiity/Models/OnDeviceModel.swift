import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device model can be used right now.
///
/// Foundation Models needs iOS 26 **and** an eligible device with Apple
/// Intelligence switched on **and** a downloaded model. The app deploys to
/// iOS 17, so every caller must be able to ask this question without naming an
/// iOS 26 type — otherwise the answer leaks `if #available` into every view
/// and every generator, and an ineligible device gets a dead button.
///
/// This enum is the single translation point. The settings UI switches on it,
/// the writers refuse it, and the tests can walk every branch without a model.
enum OnDeviceModelAvailability: Equatable, Sendable {
    /// Ready to use.
    case available
    /// The system is older than iOS 26, so the framework does not exist.
    case unsupportedSystem
    /// The device has no Neural Engine capable of running the model.
    case deviceNotEligible
    /// Eligible hardware, but Apple Intelligence is switched off.
    case appleIntelligenceOff
    /// Eligible and enabled, but the model is still downloading.
    case modelNotReady

    /// Everything except `available` needs an explanation in the UI. The
    /// distinction matters: "switch on Apple Intelligence" is something the
    /// person can do, "this iPhone is too old" is not.
    var needsUserAction: Bool { self == .appleIntelligenceOff }
}

enum OnDeviceModel {

    /// The one place the framework is touched for availability. Everything else
    /// in the app asks this instead of branching on the system version.
    static var availability: OnDeviceModelAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .unsupportedSystem }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:            return .deviceNotEligible
            case .appleIntelligenceNotEnabled:  return .appleIntelligenceOff
            case .modelNotReady:                return .modelNotReady
            @unknown default:                   return .modelNotReady
            }
        }
        #else
        return .unsupportedSystem
        #endif
    }

    static var isAvailable: Bool { availability == .available }
}
