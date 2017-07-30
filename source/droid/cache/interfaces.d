module droid.cache.interfaces;

import std.variant;

interface Cache
{
    alias Entry = Variant;

    Entry read(in string id) const;
    string write(in string id, Entry item);
    Entry fetch(in string id, Entry delegate(in string id) fallbackDelegate);
    bool remove(in string id);
}
