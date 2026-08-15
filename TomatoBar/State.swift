import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, pauseResume, timerFired, skipRest
}

enum TBStateMachineStates: StateType {
    case idle, work, paused, rest
}
