import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipWork, skipRest, pause, resume, discardPause
}

enum TBStateMachineStates: StateType {
    case idle, work, rest, paused
}
