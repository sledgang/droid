module droid.data.snowflake;

import std.typecons;

import vibe.data.json;

alias Snowflake = Typedef!ulong;

Json toJson(Snowflake id)
{
    import std.conv : to;
    return Json(to!string(id));
}

Snowflake fromJson(Json json)
{
    import std.conv : to;
    return Snowflake(to!ulong(json.get!string));
}
