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

inline handle_ootb_packet(FromPeer, ToPeer) {
    // 1)  If the OOTB packet is to or from a non-unicast address, a
    //     receiver SHOULD silently discard the packet.
    //     -> In this model we only work with unicast address

    if
    // 2)  If the OOTB packet contains an ABORT chunk, the receiver MUST
    //     silently discard the OOTB packet and take no further action.
    :: FromPeer? ABORT,vtag,itag
        -> skip
    // 3)  If the packet contains an INIT chunk with a Verification Tag set
    //     to '0', process it as described in Section 5.1.  If, for whatever
    //     reason, the INIT cannot be processed normally and an ABORT has to
    //     be sent in response, the Verification Tag of the packet
    //     containing the ABORT chunk MUST be the Initiate Tag of the
    //     received INIT chunk, and the T bit of the ABORT chunk has to be
    //     set to 0, indicating that the Verification Tag is NOT reflected.
    :: FromPeer? INIT,NO_TAG,itag
        if
        :: ToPeer! INIT_ACK,itag,EX_TAG
            -> goto CLOSED
        :: ToPeer! ABORT,itag,NO_TAG
        fi;
    // 4)  If the packet contains a COOKIE ECHO in the first chunk, process
    //     it as described in Section 5.1.
    :: FromPeer? COOKIE_ECHO,vtag,NO_TAG
        -> ToPeer! COOKIE_ACK,vtag,NO_TAG
        -> goto ESTABLISHED
    // 5)  If the packet contains a SHUTDOWN ACK chunk, the receiver should
    //     respond to the sender of the OOTB packet with a SHUTDOWN
    //     COMPLETE.  When sending the SHUTDOWN COMPLETE, the receiver of
    //     the OOTB packet must fill in the Verification Tag field of the
    //     outbound packet with the Verification Tag received in the
    //     SHUTDOWN ACK and set the T bit in the Chunk Flags to indicate
    //     that the Verification Tag is reflected.
    :: FromPeer? SHUTDOWN_ACK,vtag,NO_TAG
        -> ToPeer! SHUTDOWN_COMPLETE,vtag,NO_TAG
    // 6)  If the packet contains a SHUTDOWN COMPLETE chunk, the receiver
    //     should silently discard the packet and take no further action.
    //     Otherwise,
    :: FromPeer? SHUTDOWN_COMPLETE,itag,vtag
        -> skip
    // 7)  If the packet contains a "Stale Cookie" ERROR or a COOKIE ACK,
    //     the SCTP packet should be silently discarded.  Otherwise,
    :: FromPeer? COOKIE_ACK,vtag,itag
        -> skip
    :: FromPeer? COOKIE_ERROR,vtag,itag
        -> skip
    // 8) The receiver SHOULD respond to the sender of the OOTB packet
    //    with an ABORT chunk. When sending the ABORT chunk, the receiver
    //    of the OOTB packet MUST fill in the Verification Tag field of
    //    the outbound packet with the value found in the Verification Tag
    //    field of the OOTB packet and set the T bit in the Chunk Flags to
    //    indicate that the Verification Tag is reflected. After sending
    //    this ABORT chunk, the receiver of the OOTB packet MUST discard the
    //    OOTB packet and MUST NOT take any further action.
    fi;
}


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
        // OOTB packet
        :: full(FromPeer) &&
            !(FromPeer? [INIT,NO_TAG,EX_TAG]) &&
            !(FromPeer? [COOKIE_ECHO,EX_TAG,NO_TAG])
            -> handle_ootb_packet(FromPeer, ToPeer)
        od;
    COOKIE_WAIT:
        old_state[id] = state[id]
        state[id] = State_CookieWait
        do
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> ToPeer! COOKIE_ECHO,EX_TAG,NO_TAG
            -> timer[id] = TIMER_COOKIE
            -> goto COOKIE_ECHOED
        // 5.2.1
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
        // Abort
        :: FromPeer? ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        :: FromUser? USER_ABORT
            -> ToPeer! ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        // OOTB packet
        :: full(FromPeer) &&
            !(FromPeer? [INIT_ACK,EX_TAG,EX_TAG]) &&
            !(FromPeer? [ABORT,EX_TAG,NO_TAG])
            -> handle_ootb_packet(FromPeer, ToPeer)
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
        // 5.2.1
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer? INIT_ACK,EX_TAG,EX_TAG
        // 5.2.3
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> skip
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
        // Abort
        :: FromPeer? ABORT, EX_TAG, NO_TAG
            -> goto CLOSED
        :: FromUser? USER_ABORT
            -> ToPeer! ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        // OOTB packet
        :: full(FromPeer) &&
            !(FromPeer? [COOKIE_ACK,EX_TAG,NO_TAG]) &&
            !(FromPeer? [COOKIE_ERROR,EX_TAG,NO_TAG]) &&
            !(FromPeer? [ABORT,EX_TAG,NO_TAG])
            -> handle_ootb_packet(FromPeer, ToPeer)
        od;
    ESTABLISHED:
        old_state[id] = state[id]
        state[id] = State_Established
        do
        :: FromPeer? SHUTDOWN,EX_TAG,NO_TAG
            -> goto SHUTDOWN_RECEIVED
        :: FromUser? USER_SHUTDOWN
            -> goto SHUTDOWN_PENDING
        // Abort
        :: FromPeer? ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        :: FromUser? USER_ABORT
            -> ToPeer! ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        // 5.2.2
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        // 5.2.3
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> skip
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
        // OOTB packet
        :: full(FromPeer) &&
            !(FromPeer? [SHUTDOWN,EX_TAG,NO_TAG]) &&
            !(FromPeer? [ABORT,EX_TAG,NO_TAG])
            -> handle_ootb_packet(FromPeer, ToPeer)
        od;
    SHUTDOWN_PENDING:
        old_state[id] = state[id]
        state[id] = State_ShutdownPending
        do
        :: ToPeer! SHUTDOWN,EX_TAG,NO_TAG
             -> goto SHUTDOWN_SENT
        // 5.2.2
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        // 5.2.3
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> skip
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
        od;
    SHUTDOWN_RECEIVED:
        old_state[id] = state[id]
        state[id] = State_ShutdownReceived
        ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG -> goto SHUTDOWN_ACK_SENT
        do
        :: ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG
             -> goto SHUTDOWN_ACK_SENT
        // 5.2.2
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
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
        // Abort
        :: FromPeer? ABORT, EX_TAG, NO_TAG
            -> goto CLOSED
        :: FromUser? USER_ABORT
            -> ToPeer! ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        // 5.2.2
        :: FromPeer? INIT,NO_TAG,EX_TAG
            -> ToPeer! INIT_ACK,EX_TAG,EX_TAG
        // 5.2.3
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
            -> skip
        // 5.2.4
        :: FromPeer? COOKIE_ECHO,vtag,itag
            -> skip
        od;
    SHUTDOWN_ACK_SENT:
        old_state[id] = state[id]
        state[id] = State_ShutdownAckSent
        do
        :: FromPeer? SHUTDOWN_COMPLETE,EX_TAG,NO_TAG
            -> ToPeer! SHUTDOWN_COMPLETE,EX_TAG,NO_TAG
            -> goto CLOSED
        // Abort
        :: FromPeer? ABORT, EX_TAG, NO_TAG
            -> goto CLOSED
        :: FromUser? USER_ABORT
            -> ToPeer! ABORT,EX_TAG,NO_TAG
            -> goto CLOSED
        // 5.2.3
        :: FromPeer? INIT_ACK,EX_TAG,EX_TAG
           -> skip
        // 5.2.4, influenced by the original implementation, this part is
        // a bit tricky and I don't have the time to go in depth so I just trust
        // the original authors with it
        :: FromPeer? COOKIE_ECHO,vtag,itag
            if
            :: vtag == EX_TAG  
                -> skip
            :: else -> ToPeer! SHUTDOWN_ACK,EX_TAG,NO_TAG
            fi;
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
    UserA! USER_SHUTDOWN
}

#include "properties.pml"
