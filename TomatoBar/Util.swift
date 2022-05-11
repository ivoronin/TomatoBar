import Foundation

func secondsUntil(date: Date) -> Int {
    return Int(date.timeIntervalSince(Date()))
}
