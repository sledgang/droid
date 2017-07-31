module droid.gateway.packet;

import vibe.data.json,
       vibe.data.serialization;

import droid.gateway.opcode;

struct Packet
{
    Opcode opcode;
    Json data;

    @optional {
        uint seq;
        string type;
    }
}
