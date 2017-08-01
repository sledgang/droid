module droid.client;

import std.typecons,
       std.variant;

import droid.gateway,
       droid.api,
       droid.cache;

struct Config
{
    string token;
    API api = null;
    Gateway gateway = null;
    Cache cache = null;

    static Config mergeWithDefaults(Config other)
    {
        auto api     =     other.api is null ? new DefaultAPI(other.token) : other.api;
        auto gateway = other.gateway is null ? new Gateway(api)            : other.gateway;

        return Config(
            other.token,
            api,
            gateway,
            other.cache is null ? new MemoryCache() : other.cache
        );
    }
}

class Client
{
    private API api_;
    private Gateway gateway_;
    private DiscordCache cache_;

    this(Config config)
    {
        setupFromConfig(Config.mergeWithDefaults(config));
    }

    this(in string token)
    {
        this(tokenizedConfig(token));
    }

    void run(bool blocking = true)
    {
        gateway_.connect(blocking);
    }

    void block()
    {
        import vibe.core.core : runEventLoop;

        runEventLoop();
    }

    final inout(API) api() @property @safe inout pure
    {
        return api_;
    }

    final inout(Gateway) gateway() @property @safe inout pure
    {
        return gateway_;
    }

    final inout(DiscordCache) cache() @property @safe inout pure
    {
        return cache_;
    }

    private void setupFromConfig(Config config)
    {
        api_     = config.api;
        gateway_ = config.gateway;
        cache_   = new DiscordCache(config.cache, api_);
    }

    private Config tokenizedConfig(in string token) const
    {
        auto conf = Config();

        conf.token = token;

        return conf;
    }
}
