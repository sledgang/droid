module droid.api;

import std.conv,
       std.typecons,
       std.variant,
       std.datetime,
       std.experimental.logger,
       core.time,
       core.sync.mutex;

import vibe.http.client,
       vibe.data.json,
       vibe.core.sync;

import droid.droidversion,
       droid.data;

class API
{
    enum DEFAULT_BASE_URL   = "https://discordapp.com/api/v7";
    enum DEFAULT_USER_AGENT = "DiscordBot (https://github.com/sledgang/droid, " ~ VERSION ~ ")";

    alias RateLimitTuple = Tuple!(string, "route", string, "major");
    enum DEFAULT_RL_KEY = `tuple!("route", "major")(__FUNCTION__, "")`;

    private immutable string baseUrl_;
    private immutable string token_;
    private immutable string tokenProper_;
    private immutable string userAgent_;

    private shared Mutex[RateLimitTuple] rateLimitMutexMap_;
    private shared Mutex globalRateLimitMutex_;
    private Logger logger_;

    this(
        in string token,
        in string baseUrl = DEFAULT_BASE_URL,
        in string userAgent = DEFAULT_USER_AGENT,
        Logger logger = null
    )
    {
        token_                = token;
        tokenProper_          = makeTokenProper(token);
        baseUrl_              = baseUrl;
        userAgent_            = userAgent;
        globalRateLimitMutex_ = cast(shared) new TaskMutex();
        logger_               = logger ? logger : defaultLogger;
    }

    string getGatewayUrl()
    {
        return fetch(mixin(DEFAULT_RL_KEY), HTTPMethod.GET, "/gateway")["url"].get!string;
    }

    User getUser(Snowflake id)
    {
        return deserializeDataObject!User(
            fetch(mixin(DEFAULT_RL_KEY), HTTPMethod.GET, "/users/" ~ id.to!string)
        );
    }

    Json sendMessage(Snowflake channelId, string content) {
      return fetch(
        mixin(DEFAULT_RL_KEY),
        HTTPMethod.POST,
        "/channels/" ~ channelId.to!string ~ "/messages",
        Nullable!Json(Json([
          "content": Json(content)
        ]))
      );
    }

    Json fetch(
        in RateLimitTuple rl,
        in HTTPMethod method,
        in string path,
        in Nullable!Json postData = Nullable!Json()
    )
    in
    {
        if (method == HTTPMethod.GET) assert(postData.isNull);
    }
    body
    {
        return makeRequest(
            rl,
            method,
            makeAPIUrl(path),
            (scope req) {
                if (!postData.isNull) {
                    req.writeJsonBody(postData.get());
                }
            },
            (scope res) {
                auto j = res.readJson();
                logger_.tracef("fetch %s: %s", path, j.toPrettyString());
                return j;
            }
        );
    }

    final inout(string) token() @property @safe @nogc inout pure
    {
        return token_;
    }

    private Json makeRequest(
        in RateLimitTuple rl,
        in HTTPMethod method,
        in string url,
        scope void delegate(scope HTTPClientRequest) requester,
        scope Json delegate(scope HTTPClientResponse) responder
    )
    {
        import core.time : msecs;
        import vibe.core.core : sleep;

        shared Mutex mutex = void;
        if (auto rlPtr = rl in rateLimitMutexMap_) {
            mutex = *rlPtr;
        } else {
            mutex = cast(shared) new TaskMutex();
            rateLimitMutexMap_[rl] = mutex;
        }

        synchronized (mutex) {
            Json toReturn;
            auto requestDone = false;

            while (!requestDone) {
                requestHTTP(
                    url,
                    (scope req) {
                        req.method = method;

                        req.headers["Authorization"] = tokenProper_;
                        req.headers["User-Agent"]    = userAgent_;

                        requester(req);
                    },
                    (scope res) {
                        if (willBeRatelimited(res)) {
                            const timeout = calculateTimeout(res);
                            logger_.infof("Handling ratelimiting, sleeping for %s.", timeout);

                            if ("X-RateLimit-Global" in res.headers) {
                                // This only ever happens in a 429, so we good to synchronize here.
                                synchronized (globalRateLimitMutex_) sleep(timeout);
                            } else {
                                sleep(timeout);
                            }
                        }

                        if (res.statusCode == 429) {
                            // Need to retry the request, due to being b1nzy'd.
                            logger_.info("Retrying request due to b1nzy.");
                        } else {
                            requestDone = true;
                            toReturn = responder(res);
                        }
                    }
                );
            }

            return toReturn;
        }
    }

    pragma(inline, true)
    private Duration calculateTimeout(in HTTPClientResponse res) @safe const
    {
        if (const retryAfterPtr = "Retry-After" in res.headers) {
            return to!long(*retryAfterPtr).msecs;
        }

        const dateHeaderTime  = parseRFC822DateTime(res.headers["Date"]);
        const resetHeaderTime = SysTime.fromUnixTime(to!long(res.headers["X-RateLimit-Reset"]));

        return resetHeaderTime - dateHeaderTime;
    }

    pragma(inline, true)
    private bool willBeRatelimited(in HTTPClientResponse res) @safe const pure
    {
        return res.statusCode == 429 || res.headers["X-RateLimit-Remaining"] == "0";
    }

    pragma(inline, true)
    private string makeTokenProper(in string token) @safe const pure
    {
        import std.algorithm.searching : startsWith;

        return token.startsWith("Bot", "Bearer") ? token : "Bot " ~ token;
    }

    pragma(inline, true)
    private string makeAPIUrl(in string path)
    {
        import std.array : join;

        return baseUrl_ ~ path;
    }

    private auto defaultLogger() @property
    {
        import std.stdio : File, stderr;

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

                formattedWrite(super.file.lockingTextWriter(), "[API] ");
            }
        };
    }
}
