module droid.data.user;

import vibe.data.json;

import droid.data.snowflake;

struct User
{
    Snowflake id;
    string username;
    string discriminator;
    string avatar;
    bool bot;
}
