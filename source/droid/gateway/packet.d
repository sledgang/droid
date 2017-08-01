module droid.gateway.packet;

import vibe.data.json,
       vibe.data.serialization;

import droid.gateway.opcode,
       droid.data.event_type;

struct Packet
{
    @name("op") Opcode opcode;
    @name("d") Json data;

    @optional {
        @name("s") uint seq;
        @name("t") EventType type;
    }
}
