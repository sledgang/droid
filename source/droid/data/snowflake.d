module droid.data.snowflake;

import std.typecons;

alias Snowflake = Typedef!ulong;

string toString(Snowflake snowflake)
{
    import std.conv : to;

    return to!string(cast(TypedefType!Snowflake) snowflake);
}
