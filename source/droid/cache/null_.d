module droid.cache.null_;

import droid.cache.interfaces;

/**
 * The NullCache does not do any caching.
 */
class NullCache : Cache
{
    Cache.Entry read(in string id) const
    {
        return Cache.Entry();
    }

    string write(in string id, Cache.Entry item)
    {
        return id;
    }

    Cache.Entry fetch(in string id, Cache.Entry delegate(in string id) fallbackDelegate)
    {
        return fallbackDelegate(id);
    }

    bool remove(in string id)
    {
        return false;
    }
}
