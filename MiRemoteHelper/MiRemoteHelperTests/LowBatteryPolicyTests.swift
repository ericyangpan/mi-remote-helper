import Testing
@testable import MiRemoteHelper

struct LowBatteryPolicyTests {
    @Test func usesStrictThresholds() {
        #expect(BatteryWarning.level(for: 20) == .normal)
        #expect(BatteryWarning.level(for: 19) == .low)
        #expect(BatteryWarning.level(for: 10) == .low)
        #expect(BatteryWarning.level(for: 9) == .critical)
        #expect(BatteryWarning.level(for: 0) == .critical)
    }

    @Test func avoidsRepeatedAlertsAcrossReconnectsAndFluctuations() {
        var policy = LowBatteryPolicy()
        #expect(policy.warning(percentage: 19, charging: false) == .low)
        policy.highestNotified = 1
        #expect(policy.warning(percentage: nil, charging: nil) == nil)
        #expect(policy.warning(percentage: 18, charging: nil) == nil)
        #expect(policy.warning(percentage: 20, charging: false) == nil)
        #expect(policy.warning(percentage: 19, charging: false) == nil)
        #expect(policy.warning(percentage: 9, charging: false) == .critical)
        policy.highestNotified = 2
        #expect(policy.warning(percentage: 11, charging: false) == nil)
        #expect(policy.warning(percentage: 9, charging: false) == nil)
    }

    @Test func suppressesChargingAndRearmsAfterRecovery() {
        var policy = LowBatteryPolicy(highestNotified: 2)
        #expect(policy.warning(percentage: 5, charging: true) == nil)
        #expect(policy.highestNotified == 0)
        #expect(policy.warning(percentage: 5, charging: false) == .critical)
        policy.highestNotified = 2
        #expect(policy.warning(percentage: 25, charging: false) == nil)
        #expect(policy.highestNotified == 0)
        #expect(policy.warning(percentage: 15, charging: false) == .low)
    }
}
