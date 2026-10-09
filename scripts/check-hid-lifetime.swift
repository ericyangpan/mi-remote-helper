// Compile alongside AppSettings.swift and VoiceKeyMapper.swift.
// Requires a paired, awake Xiaomi RC003. Reads mappings; never changes them.
import Foundation

@main
struct HIDLifetimeCheck {
    static func main() {
        let mapper = VoiceKeyMapper()
        let baseline = mapper.currentMappings()
        guard !baseline.isEmpty else {
            fputs("FAIL: no connected RC003 HID service; wake and connect the remote first.\n", stderr)
            exit(1)
        }
        for _ in 0..<100 {
            autoreleasepool {
                precondition(mapper.currentMappings() == baseline, "Mappings changed during read-only check")
                let temporaryMapper = VoiceKeyMapper()
                precondition(temporaryMapper.currentMappings() == baseline, "New HID connection returned different mappings")
            }
        }
        print("PASS: 200 read-only snapshots across retained and recreated HID connections; \(baseline.count) RC003 services; mappings unchanged.")
    }
}
