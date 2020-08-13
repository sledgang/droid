/**
 * A client to interact with the API
 *
 * Copyright: © 2019, sledgang
 * Author: sledgang
 */
module droid.client;

import std.typecons,
       std.variant;

import vibe.data.json;

import droid.gateway,
       droid.api,
       droid.cache,
       droid.data;


/**
 * A config to change various settings
 */
struct Config
{
		/**
		 * The token to use for API requests and the gateway connection.
		 * Note: If using a bot user, the token must be prefaced with "Bot " to make API requests!
		 */
    string token;

    API api = null;

		/// The gateway class to use when connecting to Discord
    Gateway gateway = null;

		/// The cache to use for storing data
    Cache cache = null;

    static Config mergeWithDefaults(Config other)
    {
        auto api     =     other.api is null ? new API(other.token) : other.api;
        auto gateway = other.gateway is null ? new Gateway(api)     : other.gateway;

        return Config(
            other.token,
            api,
            gateway,
            other.cache is null ? new MemoryCache() : other.cache
        );
    }
}

/// A basic client that is used to interact with the API and connect to the gateway
class Client
{
    private API api_;
    private Gateway gateway_;
    private DiscordCache cache_;

		/// Creates a Client instance with a custom configuration
    this(Config config)
    {
        setupFromConfig(Config.mergeWithDefaults(config));
    }

		/// Creates a Client instance with the specified token
    this(in string token)
    {
        this(tokenizedConfig(token));
    }


		/// Starts a gateway connection to Discord
    void run(bool blocking = true)
    {
        gateway_.connect(blocking);
    }

    void block()
    {
        import vibe.core.core : runEventLoop;

        runEventLoop();
    }

		/// Changes your status on Discord
    void changePresence(int idleSince, string status, Activity activity) {
      this.gateway_.send(Opcode.STATUS_UPDATE, Json([
            "since": idleSince > 0 ? Json(idleSince) : Json(null),
            "game": Json([
              "name": Json(activity.name),
              "type": Json(activity.type),
              "url": activity.isStreaming() ? Json(activity.url) : Json(null)
            ]),
            "status": Json(status),
            "afk": Json(false)
      ]));
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
