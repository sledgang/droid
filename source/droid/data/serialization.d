module droid.data.serialization;

import vibe.data.json;

import droid.data.snowflake;

template SnowflakePolicy(T : Snowflake)
{
    import std.conv : to;

    static string toRepresentation(in T value) @safe
    {
        return to!string(value);
    }

    static T fromRepresentation(in string value) @safe
    {
        return Snowflake(to!ulong(value));
    }
}

T deserializeDataObject(T, ARGS...)(ARGS args)
{
    return deserializeWithPolicy!(JsonSerializer, SnowflakePolicy, T)(args);
}
