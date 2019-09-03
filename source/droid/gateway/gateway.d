module droid.gateway.gateway;

import core.time,
       std.functional,
       std.conv,
       std.stdio,
       std.typecons,
       std.random,
       std.experimental.logger,
       std.array,
       std.zlib;

import vibe.core.core,
       vibe.http.common,
       vibe.http.client,
       vibe.http.websockets,
       vibe.inet.url,
       vibe.data.json;

import droid.exception,
       droid.api,
       droid.gateway.opcode,
       droid.gateway.packet,
       droid.data.event_type,
       droid.gateway.compression;

final class Gateway
{
    // gateway url needs to be https to satisfy vibe's upgrade checks
    // Please do tell if this workaround isn't right!
    enum GATEWAY_URL = "https://gateway.discord.gg/?v=6&encoding=json";

    private alias OpcodeDelegate = void delegate(in ref Packet);
    private alias OpcodeHandlerMap = OpcodeDelegate[Opcode];

    private immutable OpcodeHandlerMap OPCODE_MAPPING;

    private string gatewayUrl_;
    private immutable CompressionType compressionType = CompressionType.ZLIB_STREAM;
    private Decompressor decompressor = null;

    private API api_;
    private WebSocket ws_;
    private Timer heartbeatTimer_;
    private bool heartbeatNeedsACK_;
    private Logger logger_;
    private bool shuttingDown = false;

    private uint lastSeqNum_;
    private string sessionId_;

    private ubyte reconnectionAttempts;

    private alias DispatchDelegate = void delegate(in ref Json);

    private DispatchDelegate[][EventType] dispatchHandlers_;

    this(API api, in string gatewayUrl = GATEWAY_URL, Logger logger = null)
    {
        OPCODE_MAPPING = buildOpcodeHandlersMap();

        gatewayUrl_ = gatewayUrl;
        api_ = api;
        logger_ = logger ? logger : defaultLogger;
    }

    void connect(in bool blocking = true, in bool reconnecting = false)
    {
        if (compressionType != CompressionType.NONE) {
            gatewayUrl_ = gatewayUrl_ ~ "&compress=" ~ compressionType;
            switch (compressionType) {
                case CompressionType.ZLIB_STREAM:
                    decompressor = new ZLibStream();
                    break;
                default:
                    throw new DroidException("Compression type not supported!");

            }
        }

        if (!tryConnect(gatewayUrl_)) {
            logger_.tracef("Could not connect to given gateway url %s, using API", gatewayUrl_);
            tryConnect(api_.getGatewayUrl(), true);
        }

        try {
            runTask(&this.handleEvents);

            if (sessionId_ && lastSeqNum_)
                resume();
            else
                identify();
        } catch (Exception e) {
            throw e;
        }

        if (blocking && !reconnecting) runEventLoop();
    }

    void subscribe(in EventType event, DispatchDelegate handler)
    {
        dispatchHandlers_[event] ~= handler;
    }

    private void identify()
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

    private void resume() {
        opcodeResumeHandle(Json([
          "token": Json(api_.token),
          "session_id": Json(sessionId_),
          "seq": Json(lastSeqNum_)
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
            auto data = "";

            if (decompressor)
                data = decompressor.read(ws_.receiveBinary());
            else
                data = ws_.receiveText();

            const packet = parseMessage(data);

            auto opcodeHandler = packet.opcode in OPCODE_MAPPING;
            if (opcodeHandler) {
                logger_.tracef("Handling opcode %s", to!string(packet.opcode));
                (*opcodeHandler)(packet);
            } else {
                logger_.tracef("Ignored opcode %s", to!string(packet.opcode));
            }
        }

        logger_.infof("Lost connection, close code %d (reason %s)", ws_.closeCode, ws_.closeReason);

        // User-initiated shutdown.
        if (shuttingDown) {
            exitEventLoop(true);
            return;
        }

        if (heartbeatTimer_)
            heartbeatTimer_.stop();

        reconnectionAttempts++;

        uint timeToWait = reconnectionAttempts * 4;

        if (timeToWait >= 100)
            timeToWait = 100 + uniform(3, 14);

        logger_.infof("Attempting to %s after %s seconds", sessionId_ ? "resume" : "reconnect", timeToWait);

        sleep(timeToWait.seconds);

        // Reconnect
        connect(true, true);
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
        aaBuf[Opcode.INVALID_SESSION] = toDelegate(&this.opcodeInvalidSessionHandle);

        aaBuf.rehash;
        return assumeUnique(aaBuf);
    }

    void send(Opcode opcode, Json data) {
        logger_.tracef("Sending op %s with the data of %s", cast(uint) opcode, data);
        ws_.send(Json(["op": Json(cast(uint) opcode), "d": data]).toString());
    }

    /* Opcode handlers below */
    private void opcodeDispatchHandle(in ref Packet packet)
    {
        // Just set the seq number for now
        if (packet.seq && packet.seq > lastSeqNum_)
            lastSeqNum_ = packet.seq;

        logger_.tracef("Got %s event in dispatch", packet.type);

        // We're only really interested in the READY callback here.
        if (packet.type == EventType.READY) {
            sessionId_ = packet.data["session_id"].get!string;
            logger_.tracef("Got session ID: %s", sessionId_);

            reconnectionAttempts = 0;
        } else if (packet.type == EventType.RESUMED) {
            opcodeResumedHandle(packet);
        }

        publish(packet);
    }

    private void publish(in ref Packet packet)
    {
        import std.algorithm.iteration : each;

        logger_.tracef("Publishing packet of type %s", packet.type);
        if (auto handlersPtr = packet.type in dispatchHandlers_) {
            (*handlersPtr).each!(handler => handler(packet.data));
        }
    }

    private void opcodeHelloHandle(in ref Packet packet)
    {
        const heartbeatInterval = packet.data["heartbeat_interval"].to!long;
        logger_.tracef("Got heartbeat interval set at %d ms", heartbeatInterval);

        heartbeatTimer_ = setTimer(dur!"msecs"(heartbeatInterval), toDelegate(&this.heartbeat), true);
    }

    private void opcodeHeartbeatACKHandle(in ref Packet /* ignored */)
    {
        logger_.tracef("Heartbeat ACK'd");

        heartbeatNeedsACK_ = false;
    }

    private void opcodeInvalidSessionHandle(in ref Packet /* ignored */) {
        logger_.tracef("Invalid Session - Reconnecting....");

        // Reset the connection so they don't try and resume again.
        if (sessionId_)
            sessionId_ = null;

        ws_.close();
    }

    private void opcodeResumedHandle(in ref Packet /* ignored */) {
        logger_.tracef("Resumed, all lost events should have been replayed.");
    }

    private void opcodeIdentifyHandle(in Json json)
    {
        logger_.tracef("Sending IDENTIFY");

        ws_.send(Json(["op": Json(cast(uint) Opcode.IDENTIFY), "d": json]).toString());
    }

    private void opcodeResumeHandle(in Json json) {
        logger_.tracef("Sending RESUME");

        send(Opcode.RESUME, json);
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
