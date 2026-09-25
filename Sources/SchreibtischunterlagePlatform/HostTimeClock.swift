import Darwin
import Foundation

enum HostTimeClock {
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    static var now: CFTimeInterval {
        seconds(fromMachAbsoluteTime: mach_absolute_time())
    }

    static func seconds(
        fromMachAbsoluteTime value: UInt64
    ) -> CFTimeInterval {
        Double(value) * secondsPerTick
    }
}
