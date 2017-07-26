module droid.api.api;

import std.json;

import vibe.http.common : HTTPMethod;

interface API
{
    JSONValue fetch(in HTTPMethod method, in string path, in string postData = "");
}
