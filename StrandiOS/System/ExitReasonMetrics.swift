import Foundation
import MetricKit

/// Why iOS ended NOOP's process, from MetricKit's daily exit counts (fork diagnostic).
///
/// The strap log shows a fresh launch whenever iOS relaunches NOOP for the strap, but not why the previous
/// process ended, and the device keeps no crash or jetsam report for a quiet background termination. On
/// 2026-09-18 NOOP was relaunched every 20–40 minutes with no report of any kind, which is how a re-score
/// pass was left unfinished overnight. `MXAppExitMetric` counts every exit by cause (memory limit, memory
/// pressure, CPU limit, watchdog, suspended while holding a locked file, background-task timeout, crash),
/// delivered about once a day for the previous 24 hours. Each payload is written to the strap log and kept
/// in UserDefaults (`lastReportKey`) so it can be read from a pulled preferences file.
final class ExitReasonMetrics: NSObject, MXMetricManagerSubscriber {
    static let lastReportKey = "noop.metrickit.lastExitReport"

    private let log: (String) -> Void

    init(log: @escaping (String) -> Void) {
        self.log = log
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit { MXMetricManager.shared.remove(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            let line = Self.logLine(background: exits.backgroundExitData, foreground: exits.foregroundExitData,
                                    from: payload.timeStampBegin, to: payload.timeStampEnd)
            log(line)
            UserDefaults.standard.set(line, forKey: Self.lastReportKey)
        }
    }

    static func logLine(background b: MXBackgroundExitData, foreground f: MXForegroundExitData,
                        from: Date, to: Date) -> String {
        let span = ISO8601DateFormatter().string(from: from) + "…" + ISO8601DateFormatter().string(from: to)
        return "app exits \(span) background: normal=\(b.cumulativeNormalAppExitCount) "
            + "memoryLimit=\(b.cumulativeMemoryResourceLimitExitCount) memoryPressure=\(b.cumulativeMemoryPressureExitCount) "
            + "cpuLimit=\(b.cumulativeCPUResourceLimitExitCount) watchdog=\(b.cumulativeAppWatchdogExitCount) "
            + "lockedFile=\(b.cumulativeSuspendedWithLockedFileExitCount) "
            + "taskTimeout=\(b.cumulativeBackgroundTaskAssertionTimeoutExitCount) "
            + "badAccess=\(b.cumulativeBadAccessExitCount) abnormal=\(b.cumulativeAbnormalExitCount) "
            + "illegalInstruction=\(b.cumulativeIllegalInstructionExitCount) | foreground: "
            + "normal=\(f.cumulativeNormalAppExitCount) memoryLimit=\(f.cumulativeMemoryResourceLimitExitCount) "
            + "watchdog=\(f.cumulativeAppWatchdogExitCount) badAccess=\(f.cumulativeBadAccessExitCount) "
            + "abnormal=\(f.cumulativeAbnormalExitCount)"
    }

    /// This process's physical memory footprint and what iOS says is left before its limit, in MB, for the
    /// strap log after each completed sync. Termination for memory leaves no report, so the trend before a
    /// relaunch is the only record of how close the process was.
    static func memoryLine() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = kr == KERN_SUCCESS ? "\(info.phys_footprint / 1_048_576)" : "n/a"
        return "memory footprint=\(footprint)MB available=\(os_proc_available_memory() / 1_048_576)MB"
    }
}
