module droid.gateway.gateway;

import core.time,
       std.functional,
       std.conv;

import vibe.core.core,
       vibe.core.log,
       vibe.http.common,
       vibe.http.client,
       vibe.http.websockets,
       vibe.inet.url,
       vibe.data.json;

import droid.exception,
       droid.api,
       droid.gateway.opcode;

private struct OpcodeHandler
{
    Opcode opcode;
}

final class Gateway
{
    enum GATEWAY_URL = "wss://gateway.discord.gg/?v=6&encoding=json";

    private alias OpcodeDelegate = void delegate(in Json);
    private alias OpcodeHandlerMap = OpcodeDelegate[Opcode];

    private immutable OpcodeHandlerMap OPCODE_MAPPING;

    private API api_;
    private WebSocket ws_;
    private Timer heartbeatTimer_;
    private uint lastSeqNum_;
    private bool heartbeatNeedsACK_;

    this(API api)
    {
        OPCODE_MAPPING = buildOpcodeHandlersMap();
        api_ = api;
    }

    void connect(in bool blocking = true, in string gatewayUrl = GATEWAY_URL)
    {
        if (!tryConnect(gatewayUrl)) {
            tryConnect(api_.fetch(HTTPMethod.GET, "/gateway")["url"].get!string, true);
        }

        try {
            runTask(&this.handleEvents);

            identify();
        } catch (Exception e) {
            throw e;
        }

        if (blocking) runEventLoop();
    }

    void identify()
    {
        import std.system : os;

        version (Windows) {
            immutable osName = "windows";
        } else {
            version (linux) {
                immutable osName = "linux";
            } else {
                immutable osName = "unknown";
            }
        }

        opcodeIdentifyHandle(Json([
            "token": Json(api_.token),
            "properties": Json([
                "$os": Json(osName),
                "$browser": Json("droid"),
                "$device": Json("droid")
            ])
        ]));
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

            const opcode = cast(Opcode) (*opPtr).get!uint;
            auto opcodeHandler = opcode in OPCODE_MAPPING;
            if (opcodeHandler) {
                logDebug("handling opcode %s", to!string(opcode));
                (*opcodeHandler)(parsedJson);
            } else {
                logDebug("ignored opcode %s", to!string(opcode));
            }
        }

        logInfo("[GATEWAY] lost connection, close code %d (reason %s)", ws_.closeCode, ws_.closeReason);
        exitEventLoop(true);
    }

    private void heartbeat()
    {
        if (heartbeatNeedsACK_) {
            ws_.close();
            throw new DroidException("did not receive ACK for heartbeat -- zombie connection");
        }

        logDebug("heartbeating");

        ws_.send(Json(["op": Json(cast(uint) Opcode.HEARTBEAT), "d": Json(lastSeqNum_)]).toString());
        heartbeatNeedsACK_ = true;
    }

    private immutable(OpcodeHandlerMap) buildOpcodeHandlersMap()
    {
        import std.exception : assumeUnique;

        OpcodeHandlerMap aaBuf;

        aaBuf[Opcode.DISPATCH]      = toDelegate(&this.opcodeDispatchHandle);
        aaBuf[Opcode.HELLO]         = toDelegate(&this.opcodeHelloHandle);
        aaBuf[Opcode.HEARTBEAT_ACK] = toDelegate(&this.opcodeHeartbeatACKHandle);

        aaBuf.rehash;
        return assumeUnique(aaBuf);
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

    private void opcodeIdentifyHandle(in Json json)
    {
        logDebug("sending identify");

        ws_.send(Json(["op": Json(cast(uint) Opcode.IDENTIFY), "d": json]).toString());
    }
}
