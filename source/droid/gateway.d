module droid.gateway;

import core.time,
       std.functional;

import vibe.core.core,
       vibe.core.log,
       vibe.http.common,
       vibe.http.client,
       vibe.http.websockets,
       vibe.inet.url,
       vibe.data.json;

import droid.exception,
       droid.api;

final class Gateway
{
    enum GATEWAY_URL = "wss://gateway.discord.gg/?v=6&encoding=json";

    private alias OpcodeDelegate = void delegate(in Json);

    private immutable OpcodeDelegate[uint] OPCODE_MAPPING;

    private API api_;
    private WebSocket ws_;
    private Timer heartbeatTimer_;
    private uint lastSeqNum_;
    private bool heartbeatNeedsACK_;

    this(API api)
    {
        OPCODE_MAPPING = {
            // create at runtime because toDelegate can't be used in compile-time
            import std.exception : assumeUnique;

            OpcodeDelegate[uint] bufAA;

            bufAA[0]  = toDelegate(&this.opcodeDispatchHandle);
            bufAA[10] = toDelegate(&this.opcodeHelloHandle);
            bufAA[11] = toDelegate(&this.opcodeHeartbeatACKHandle);

            bufAA.rehash;
            return assumeUnique(bufAA);
        }();

        api_ = api;
    }

    void connect(in string gatewayUrl = GATEWAY_URL)
    {
        if (!tryConnect(gatewayUrl)) {
            tryConnect(api_.fetch(HTTPMethod.GET, "/gateway")["url"].str, true);
        }

        handleEvents();
    }

    private bool tryConnect(in string gatewayUrl, in bool throwEx = false)
    {
        ws_ = connectWebSocket(URL(gatewayUrl));
        if (!ws_.connected) {
            if (throwEx) {
                throw new DroidException("could not connect to the websocket at " ~ gatewayUrl ~ "!");
            }

            return false;
        }

        return true;
    }

    private void handleEvents()
    {
        assert(ws_ && ws_.connected);

        while (ws_.waitForData()) {
            const parsedJson = parseJsonString(ws_.receiveText());
            const opPtr = "op" in parsedJson;
            assert(opPtr !is null);

            const opcode = (*opPtr).get!uint;
            auto opcodeHandler = opcode in OPCODE_MAPPING;
            if (opcodeHandler) {
                logDebug("handling opcode %d", opcode);
                (*opcodeHandler)(parsedJson);
            } else {
                logDebug("ignored opcode %d", opcode);
            }
        }
    }

    private void heartbeat()
    {
        if (heartbeatNeedsACK_) {
            ws_.close();
            throw new DroidException("did not receive ACK for heartbeat -- zombie connection");
        }

        logDebug("heartbeating");

        ws_.send(Json(["op": Json(1), "d": Json(lastSeqNum_)]).toString());
        heartbeatNeedsACK_ = true;
    }

    /* Opcode handlers below */
    private void opcodeDispatchHandle(in Json json)
    {
        // Just set the seq number for now
        lastSeqNum_ = json["s"].to!uint;
    }

    private void opcodeHelloHandle(in Json json)
    {
        const heartbeatInterval = json["d"]["heartbeat_interval"].to!long;
        logDebug("heartbeat interval: %s", heartbeatInterval);

        heartbeatTimer_ = setTimer(dur!"msecs"(heartbeatInterval), toDelegate(&this.heartbeat), true);
    }

    private void opcodeHeartbeatACKHandle(in Json)
    {
        logDebug("heartbeat ack'd");

        heartbeatNeedsACK_ = false;
    }
}
