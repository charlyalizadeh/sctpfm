/* === Property 1 == */
// A peer in Closed either stays still or transitions to Established or Cookie_Wait
ltl P1 {
    always
    (
        (state[0] == State_Closed)
        -> 
        (X (state[0] == State_Closed ||
           state[0] == State_Established ||
           state[0] == State_CookieWait)
        )
    )
}

/* === Property 2 == */
//ltl P2 {
//   always
//   (
//        eventually
//        (
//            (state[0] == State_Closed && state[1] == State_Closed) ||
//            (state[0] == State_Established && state[1] == State_Established) ||
//            (old_state[0] != state[0] || old_state[1] != state[1])
//        )
//   )
//}


/* === Property 3 == */
// One of the following always eventually happens: the
// peers are both in Closed, the peers are both in Established,
// or one of the peers changes state
ltl P3_0 {
    always (
        old_state[0] == State_ShutdownAckSent && old_state[0] != state[0]
        ->
        state[0] == State_Closed
    )
}
ltl P3_1 {
    always (
        old_state[1] == State_ShutdownAckSent && old_state[1] != state[1]
        ->
        state[1] == State_Closed
    )
}

/* === Property 4 == */
// If a peer is in Cookie_Echoed then its cookie timer
// is actively ticking.
ltl P4_0 {
    always(state[0] == State_CookieEchoed -> timer[0] == TIMER_COOKIE)
}
ltl P4_1 {
    always(state[1] == State_CookieEchoed -> timer[1] == TIMER_COOKIE)
}

/* === Property 5 === */
// The peers are never both in Shutdown_Received.
ltl P5 {
    always(
        state[0] == State_ShutdownReceived || state[0] == State_ShutdownReceived
        ->
        state[0] != state[1]
    )
}

/* === Property 6 === */
// If a peer transitions out of Shutdown_Received then it
// must transition into either Shutdown_Ack_Sent or Closed.
ltl P6_0 {
    always(
        old_state[0] != state[0] && old_state[0] == State_ShutdownReceived
        ->
        state[0] == State_ShutdownAckSent || state[0] == State_Closed
    )
}
ltl P6_1 {
    always(
        old_state[1] != state[1] && old_state[1] == State_ShutdownReceived
        ->
        state[1] == State_ShutdownAckSent || state[1] == State_Closed
    )
}

/* === Property 7 === */
// If Peer A is in Cookie_Echoed then B must not be in
// Shutdown_Received. 
ltl P7_0 {
    always(
        state[0] == State_CookieEchoed
        ->
        state[1] != State_ShutdownReceived
    )
}
ltl P7_1 {
    always(
        state[1] == State_CookieEchoed
        ->
        state[0] != State_ShutdownReceived
    )
}
