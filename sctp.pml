mtype:msg = {
    INIT, INIT_ACK,
    COOKIE_ECHO, COOKIE_ACK, COOKIE_ERROR,
    ABORT, SHUTDOWN, SHUTDOWN_ACK, SHUTDOWN_COMPLETE,
    DATA, DATA_ACK
};
mtype:tag = { EX_TAG, UN_TAG, NO_TAG };
mtype:user_msg = { USER_ASSOCIATE, USER_SHUTDOWN, USER_ABORT };
mtype:timer_state = { TIMER_INIT, TIMER_COOKIE, TIMER_SHUTDOWN, TIMER_NONE }

#define State_Closed 0
#define State_CookieWait 1
#define State_CookieEchoed 2
#define State_Established 3
#define State_ShutdownReceived 4
#define State_ShutdownAckSent 5
#define State_ShutdownSent 6
#define State_ShutdownPending 7
#define State_MaxRetransmitCookie 8

/* LTL related */
// We save state to assert properties in LTL
int old_state[2];
int state[2];
// Timer
mtype:timer_state timer[2];


proctype User(int id; chan ToPeer) {
    do
    :: ToPeer! USER_ASSOCIATE
    :: ToPeer! USER_SHUTDOWN
    :: ToPeer! USER_ABORT
    od;
}

inline go_to_state(id) {
    if
    :: state[id] == State_Closed -> goto CLOSED
    :: state[id] == State_CookieWait -> goto COOKIE_WAIT
    :: state[id] == State_CookieEchoed -> goto COOKIE_ECHOED
    :: state[id] == State_Established -> goto ESTABLISHED
    :: state[id] == State_ShutdownReceived -> goto SHUTDOWN_RECEIVED
    :: state[id] == State_ShutdownAckSent -> goto SHUTDOWN_ACK_SENT
    :: state[id] == State_ShutdownSent -> goto SHUTDOWN_SENT
    :: state[id] == State_ShutdownPending -> goto SHUTDOWN_PENDING
    :: state[id] == State_MaxRetransmitCookie -> goto COOKIE_ECHOED
    fi;
}

proctype Peer(int id; chan ToPeer, FromPeer, FromUser) {
    mtype:tag itag, vtag
    go_to_state(id)
    CLOSED:
        old_state[id] = state[id]
        state[id] = State_Closed
        do
        :: FromPeer? COOKIE_ECHO,EX_TAG,NO_TAG
            -> ToPeer! COOKIE_ACK,EX_TAG,NO_TAG
            -> goto ESTABLISHED
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        :: FromUser? USER_ASSOCIATE
            -> ToPeer! INIT,NO_TAG,EX_TAG
            -> goto COOKIE_WAIT
        od;
    COOKIE_WAIT:
        old_state[id] = state[id]
        state[id] = State_CookieWait
        do
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> ToPeer! COOKIE_ECHO,EX_TAG,NO_TAG
            -> timer[id] = TIMER_COOKIE
            -> goto COOKIE_ECHOED
        od;
    COOKIE_ECHOED:
        old_state[id] = state[id]
        state[id] = State_CookieEchoed
        do
        :: FromPeer? COOKIE_ACK,EX_TAG,NO_TAG
            -> goto ESTABLISHED
        :: FromPeer? COOKIE_ERROR,EX_TAG,NO_TAG
            -> ToPeer! INIT,NO_TAG,EX_TAG
            -> goto COOKIE_WAIT
        :: timer[id] == TIMER_COOKIE ->
            -> ToPeer! COOKIE_ERROR,EX_TAG,NO_TAG
            -> old_state[id] = state[id]
            -> state[id] = State_MaxRetransmitCookie
            -> timer[id] = TIMER_NONE
            -> goto CLOSED
        od;
    ESTABLISHED:
        old_state[id] = state[id]
        state[id] = State_Established
        do
        :: FromPeer? SHUTDOWN,EX_TAG,NO_TAG
            -> goto SHUTDOWN_RECEIVED
        :: FromUser? USER_SHUTDOWN
            -> goto SHUTDOWN_PENDING
        od;
    SHUTDOWN_PENDING:
        old_state[id] = state[id]
        state[id] = State_ShutdownPending
        do
        :: ToPeer! SHUTDOWN,EX_TAG,NO_TAG
             -> goto SHUTDOWN_SENT
        od;
    SHUTDOWN_RECEIVED:
        old_state[id] = state[id]
        state[id] = State_ShutdownReceived
        ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG -> goto SHUTDOWN_ACK_SENT
        do
        :: ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG
             -> goto SHUTDOWN_ACK_SENT
        od;
    SHUTDOWN_SENT:
        old_state[id] = state[id]
        state[id] = State_ShutdownSent
        do
        :: FromPeer? SHUTDOWN,EX_TAG,NO_TAG
            -> ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG
            -> goto SHUTDOWN_ACK_SENT
        :: FromPeer? SHUTDOWN_ACK,EX_TAG,NO_TAG
            -> ToPeer! SHUTDOWN_COMPLETE,EX_TAG,NO_TAG
            -> goto CLOSED
        od;
    SHUTDOWN_ACK_SENT:
        old_state[id] = state[id]
        state[id] = State_ShutdownAckSent
        do
        :: FromPeer? SHUTDOWN_COMPLETE,EX_TAG,NO_TAG
            -> ToPeer! SHUTDOWN_COMPLETE,EX_TAG,NO_TAG
            -> goto CLOSED
        od;
}

chan UserA = [1] of { mtype:user_msg }
chan UserB = [1] of { mtype:user_msg }
chan AtoB = [1] of { mtype:msg, mtype:tag, mtype:tag }
chan BtoA = [1] of { mtype:msg, mtype:tag, mtype:tag }


init {
    state[0]     = State_Closed
    state[1]     = State_Closed
    old_state[0] = State_Closed
    old_state[1] = State_Closed
    timer[0]     = TIMER_NONE
    timer[1]     = TIMER_NONE

    run Peer(0, AtoB, BtoA, UserA);
    run Peer(1, BtoA, AtoB, UserB);
    UserA! USER_ASSOCIATE
}

#include "properties.pml"
