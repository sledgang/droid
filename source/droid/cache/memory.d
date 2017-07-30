module droid.cache.memory;

import std.variant;

import droid.cache.interfaces;

class MemoryCache : Cache
{
    private Cache.Entry[string] cache;

    Cache.Entry read(in string id) const
    {
        return cache[id];
    }

    string write(in string id, Cache.Entry item)
    {
        cache[id] = item;

        return id;
    }

    Cache.Entry fetch(in string id, Cache.Entry delegate(in string id) fallbackDelegate)
    {
        auto itemPtr = id in cache;
        if (itemPtr) {
            return *itemPtr;
        } else {
            auto fallback = fallbackDelegate(id);
            write(id, fallback);

            return fallback;
        }
    }

    bool remove(in string id)
    {
        return cache.remove(id);
    }
}
