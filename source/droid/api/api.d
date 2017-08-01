module droid.api.api;

import vibe.http.common,
       vibe.data.json;

import droid.data;

interface API
{
    User getUser(in Snowflake id);

    Json fetch(in HTTPMethod method, in string path, in Json postData = Json.emptyObject);
    string token() @property @safe @nogc const pure;
}
