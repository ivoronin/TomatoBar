import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, startFun, skipRest
}

enum TBStateMachineStates: StateType {
    case idle, important, fun, rest
}
