module droid.gateway.gateway;

import core.time,
       std.functional,
       std.conv,
       std.stdio,
       std.typecons,
       std.experimental.logger;

import vibe.core.core,
       vibe.http.common,
       vibe.http.client,
       vibe.http.websockets,
       vibe.inet.url,
       vibe.data.json;

import droid.exception,
       droid.api,
       droid.gateway.opcode,
       droid.gateway.packet;

final class Gateway
{
    enum GATEWAY_URL = "wss://gateway.discord.gg/?v=6&encoding=json";

    private alias OpcodeDelegate = void delegate(in Packet);
    private alias OpcodeHandlerMap = OpcodeDelegate[Opcode];

    private immutable OpcodeHandlerMap OPCODE_MAPPING;

    private API api_;
    private WebSocket ws_;
    private Timer heartbeatTimer_;
    private uint lastSeqNum_;
    private bool heartbeatNeedsACK_;
    private Logger logger_;

    this(API api, Logger logger = null)
    {
        OPCODE_MAPPING = buildOpcodeHandlersMap();
        api_ = api;
        logger_ = logger ? logger : defaultLogger;
    }

    void connect(in bool blocking = true, in string gatewayUrl = GATEWAY_URL)
    {
        if (!tryConnect(gatewayUrl)) {
            logger_.tracef("Could not connect to given gateway url %s, using API", gatewayUrl);
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
                throw new DroidException("Could not connect to the websocket at " ~ gatewayUrl ~ "!");
            }

            return false;
        }

        return true;
    }

    private void handleEvents()
    {
        assert(ws_ && ws_.connected);

        while (ws_.waitForData()) {
            const packet = parseMessage(ws_.receiveText());

            auto opcodeHandler = packet.opcode in OPCODE_MAPPING;
            if (opcodeHandler) {
                logger_.tracef("Handling opcode %s", to!string(packet.opcode));
                (*opcodeHandler)(packet);
            } else {
                logger_.tracef("Ignored opcode %s", to!string(packet.opcode));
            }
        }

        logger_.infof("Lost connection, close code %d (reason %s)", ws_.closeCode, ws_.closeReason);
        exitEventLoop(true);
    }

    private Packet parseMessage(in string data)
    {
        return deserializeJson!Packet(parseJsonString(data));
    }

    private void heartbeat()
    {
        if (heartbeatNeedsACK_) {
            ws_.close();
            throw new DroidException("Did not receive ACK for heartbeat -- zombie connection");
        }

        logger_.tracef("Heartbeating");

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
    private void opcodeDispatchHandle(in Packet packet)
    {
        // Just set the seq number for now
        lastSeqNum_ = packet.seq;
    }

    private void opcodeHelloHandle(in Packet packet)
    {
        const heartbeatInterval = packet.data["heartbeat_interval"].to!long;
        logger_.tracef("Got heartbeat interval set at %d ms", heartbeatInterval);

        heartbeatTimer_ = setTimer(dur!"msecs"(heartbeatInterval), toDelegate(&this.heartbeat), true);
    }

    private void opcodeHeartbeatACKHandle(in Packet /* ignored */)
    {
        logger_.tracef("Heartbeat ACK'd");

        heartbeatNeedsACK_ = false;
    }

    private void opcodeIdentifyHandle(in Json json)
    {
        logger_.tracef("Sending IDENTIFY");

        ws_.send(Json(["op": Json(cast(uint) Opcode.IDENTIFY), "d": json]).toString());
    }
    /* End opcode handlers */

    private auto defaultLogger() @property
    {
        return new class (stderr) FileLogger
        {
            import std.concurrency : Tid;
            import std.datetime.systime : SysTime;

            @disable this();

            this(in string fn, const LogLevel lv = LogLevel.all) @safe
            {
                super(fn, lv);
            }

            this(File file, const LogLevel lv = LogLevel.all) @safe
            {
                super(file, lv);
            }

            override protected void beginLogMsg(string file, int line, string funcName,
                string prettyFuncName, string moduleName, LogLevel logLevel,
                Tid threadId, SysTime timestamp, Logger logger)
                @safe
            {
                import std.format : formattedWrite;

                super.beginLogMsg(
                    file, line, funcName, prettyFuncName, moduleName,
                    logLevel, threadId, timestamp, logger
                );

                formattedWrite(super.file.lockingTextWriter(), "[GATEWAY] ");
            }
        };
    }
}
