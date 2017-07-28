module droid.cache.discord;

import droid.cache.primitives,
       droid.api;

struct DiscordCache(Cache)
    if (isCache!Cache)
{
    private Cache backingCache_;
    private API api_;

    this(Cache backingCache, API api)
    {
        backingCache_ = backingCache;
        api_ = api;
    }

    // TODO: add helper methods for dickswords stuff

    T read(T)(in string id) const
    {
        return backingCache_.read!T(id);
    }

    string write(T)(in string id, in T item)
    {
        return backingCache_.write(id, item);
    }

    T fetch(T)(in string id, T delegate(in string id) fallbackDelegate)
    {
        return backingCache_.fetch(id, fallbackDelegate);
    }

    bool remove(in string id)
    {
        return cache.remove(id);
    }

    bool opBinaryRight(string op)(in string id)
        if (op == "in")
    {
        return id in cache;
    }

    Cache backingCache() @property @safe const pure
    {
        return backingCache_;
    }
}
