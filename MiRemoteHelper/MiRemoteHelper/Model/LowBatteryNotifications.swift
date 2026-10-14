import Foundation
import UserNotifications

enum BatteryWarning: Int {
    case normal = 0, low = 1, critical = 2

    static func level(for percentage: Int) -> Self {
        percentage < 10 ? .critical : percentage < 20 ? .low : .normal
    }
}

struct LowBatteryPolicy {
    var highestNotified: Int = 0

    mutating func warning(percentage: Int?, charging: Bool?) -> BatteryWarning? {
        if charging == true || (percentage.map { $0 >= 25 } ?? false) {
            highestNotified = 0
            return nil
        }
        guard let percentage else { return nil }
        let warning = BatteryWarning.level(for: percentage)
        return warning.rawValue > highestNotified ? warning : nil
    }
}

/// Only local battery notifications; no audio or text-field access.
final class LowBatteryNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private var policy: LowBatteryPolicy
    private var pending: DispatchWorkItem?
    private var revision: UInt64 = 0
    private static let preferenceKey = "battery.highestNotifiedWarning"
    private static let notificationID = "remote.low-battery"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policy = LowBatteryPolicy(highestNotified: defaults.integer(forKey: Self.preferenceKey))
        super.init()
        center.delegate = self
    }

    func update(percentage: Int?, charging: Bool?) {
        revision &+= 1
        let generation = revision
        pending?.cancel()
        let warning = policy.warning(percentage: percentage, charging: charging)
        defaults.set(policy.highestNotified, forKey: Self.preferenceKey)
        if charging == true || (percentage.map { $0 >= 25 } ?? false) {
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        }
        guard let warning, let percentage else { return }
        // Level and charging arrive separately. Let both readings settle first.
        let work = DispatchWorkItem { [weak self] in
            self?.authorizeAndSend(warning, percentage: percentage, generation: generation)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func authorizeAndSend(_ warning: BatteryWarning, percentage: Int, generation: UInt64) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self, self.revision == generation else { return }
                if settings.authorizationStatus == .notDetermined {
                    self.center.requestAuthorization(options: [.alert]) { [weak self] allowed, _ in
                        DispatchQueue.main.async {
                            guard let self, allowed, self.revision == generation else { return }
                            self.send(warning, percentage: percentage, generation: generation)
                        }
                    }
                } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    self.send(warning, percentage: percentage, generation: generation)
                }
            }
        }
    }

    private func send(_ warning: BatteryWarning, percentage: Int, generation: UInt64) {
        let content = UNMutableNotificationContent()
        content.title = warning == .critical
            ? String.appLocalized("Remote battery critically low") : String.appLocalized("Remote battery low")
        content.body = String.appLocalized("Battery at \(percentage)%. Charge your remote.")
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.revision == generation else {
                    self.center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
                    return
                }
                if error == nil {
                    self.policy.highestNotified = warning.rawValue
                    self.defaults.set(warning.rawValue, forKey: Self.preferenceKey)
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
