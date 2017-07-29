module droid.api.api;

import vibe.http.common,
       vibe.data.json;

interface API
{
    Json fetch(in HTTPMethod method, in string path, in string postData = "");



    string token() @property @safe @nogc const pure;
}
