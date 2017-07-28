module droid.cache.memory;

import std.variant;

struct MemoryCache
{
    alias Entry = Variant;

    private Entry[string] cache;

    T read(T)(in string id) const
    {
        return cache[id].get!T;
    }

    string write(T)(in string id, in T item)
    {
        cache[id] = item;

        return id;
    }

    T fetch(T)(in string id, T delegate(in string id) fallbackDelegate)
    {
        auto itemPtr = id in cache;
        if (itemPtr) {
            return (*itemPtr).get!T;
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

    bool opBinaryRight(string op)(in string id)
        if (op == "in")
    {
        return (id in cache) != null;
    }
}
