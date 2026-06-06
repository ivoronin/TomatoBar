import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest, startRest
}

enum TBStateMachineStates: StateType {
    case idle, work, rest
}
