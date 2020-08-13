///
module droid.data.user;

import vibe.data.json;

import droid.data.snowflake;

/// A Discord User
struct User
{

		/// The user's `droid.data.snowflake.Snowflake`
    Snowflake id;

    /// The user's username
    string username;

    /// The user's discriminator
    string discriminator;

    /// The user's avatar hash
    string avatar;

    /// Whether or not the user is a Bot account
    @optional bool bot;
}
