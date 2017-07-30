module droid.cache.discord;

import droid.cache.interfaces,
       droid.api,
       droid.data;

final class DiscordCache : Cache
{
    private Cache backingCache_;
    private API api_;

    this(Cache backingCache, API api)
    {
        backingCache_ = backingCache;
        api_ = api;
    }

    User user(in Snowflake id)
    {
        return backingCache_.fetch(createKey!User(id), _ => Cache.Entry(api_.getUser(id))).get!User;
    }

    override Cache.Entry read(in string id) const
    {
        return backingCache_.read(id);
    }

    string write(in string id, Cache.Entry item)
    {
        return backingCache_.write(id, item);
    }

    Cache.Entry fetch(in string id, Cache.Entry delegate(in string id) fallbackDelegate)
    {
        return backingCache_.fetch(id, fallbackDelegate);
    }

    bool remove(in string id)
    {
        return backingCache_.remove(id);
    }

    auto backingCache() @property @safe const pure
    {
        return backingCache_;
    }

    string createKey(T)(Snowflake id)
    {
        import std.conv : text;

        // this shall be expanded
        static if (is(T == User)) {
            return text("user/", id);
        } else {
            return text("unknown/", id);
        }
    }
}
