// swiftlint:disable missing_docs
import Foundation
import SwiftState

public typealias TomatoBarStateMachine = StateMachine<TomatoBarState, TomatoBarEvent>
public typealias TomatoBarContext = TomatoBarStateMachine.Context

public enum TomatoBarEvent: EventType {
    case startStop, timerFired
}

public enum TomatoBarState: StateType {
    case ready, idle, work, rest
}
