import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest
}

enum TBStateMachineStates: StateType {
    case idle, work, rest
}
