module droid.data.snowflake;

import std.typecons,
       std.conv;

import vibe.data.json;

alias Snowflake = Typedef!ulong;
