import CoreGraphics
import Testing
@testable import Aeroshot

@MainActor
struct DesignSystemTokenTests {
    @Test func spacingAndRadiusScalesAreStrictlyOrdered() {
        #expect(AeroTokens.Spacing.xxs < AeroTokens.Spacing.xs)
        #expect(AeroTokens.Spacing.xs < AeroTokens.Spacing.small)
        #expect(AeroTokens.Spacing.small < AeroTokens.Spacing.medium)
        #expect(AeroTokens.Spacing.medium < AeroTokens.Spacing.large)
        #expect(AeroTokens.Spacing.large < AeroTokens.Spacing.extraLarge)
        #expect(AeroTokens.Radius.small < AeroTokens.Radius.control)
        #expect(AeroTokens.Radius.control < AeroTokens.Radius.card)
        #expect(AeroTokens.Radius.card < AeroTokens.Radius.panel)
    }

    @Test func controlMetricsMeetCompactMacHitTarget() {
        #expect(AeroTokens.Control.minimumHitSize >= 28)
        #expect(AeroTokens.Control.compactHeight <= AeroTokens.Control.regularHeight)
        #expect(AeroTokens.Control.regularHeight < AeroTokens.Control.largeHeight)
        #expect(AeroControlSize.compact.height == AeroTokens.Control.compactHeight)
        #expect(AeroControlSize.large.height == AeroTokens.Control.largeHeight)
    }

    @Test func legacyMetricsRemainCompatible() {
        #expect(AeroTheme.controlRadiusS == 7)
        #expect(AeroTheme.cardRadius == 14)
        #expect(AeroTheme.controlHeight == 28)
        #expect(SettingsTheme.controlRadius == 10)
        #expect(SettingsTheme.panelRadius == 18)
        #expect(SettingsTheme.spacingXS == 4)
        #expect(SettingsTheme.spacingXL == 24)
    }

    @Test func reducedMotionAndTransparencyHaveDeterministicFallbacks() {
        let defaults = AeroAccessibilityPreferences()
        #expect(defaults.allowsMotion)
        #expect(defaults.allowsTransparency)
        #expect(!defaults.requiresStateSymbol)

        let protected = AeroAccessibilityPreferences(
            reduceMotion: true,
            increasedContrast: true,
            reduceTransparency: true,
            differentiateWithoutColor: true
        )
        #expect(!protected.allowsMotion)
        #expect(!protected.allowsTransparency)
        #expect(protected.requiresStateSymbol)
        #expect(protected.borderWidth(normal: 0.5) == 2)
    }

    @Test func semanticStatesAlwaysExposeTextAndSymbols() {
        for state in AeroSemanticState.allCases {
            #expect(!state.label.isEmpty)
            #expect(!state.symbol.isEmpty)
        }
        for status in AeroPermissionStatus.allCases {
            #expect(!status.label.isEmpty)
            #expect(!status.state.label.isEmpty)
            #expect(!status.state.symbol.isEmpty)
        }
    }

    @Test func progressValuesClampToTheAccessibleUnitInterval() {
        #expect(AeroProgress(label: "Export", value: -0.5).normalizedValue == 0)
        #expect(AeroProgress(label: "Export", value: 0.4).normalizedValue == 0.4)
        #expect(AeroProgress(label: "Export", value: 1.5).normalizedValue == 1)
        #expect(AeroProgress(label: "Export", value: nil).normalizedValue == nil)
    }

    @Test func feedbackSummariesIncludeStateWithoutDependingOnColor() {
        let toast = AeroToast(message: "Saved", state: .success)
        #expect(toast.accessibilitySummary == "Complete: Saved")

        let permission = AeroPermissionState(
            title: "Screen Recording",
            message: "Needed to capture your screen.",
            status: .required
        )
        #expect(permission.accessibilitySummary.contains("required"))
        #expect(AeroPermissionStatus.required.actionTitle != nil)
        #expect(AeroPermissionStatus.granted.actionTitle == nil)
    }
}
