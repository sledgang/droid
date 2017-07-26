module droid.api.default_api;

import std.json;

import vibe.http.client;

import droid.droidversion,
       droid.api.api;

final class DefaultAPI : API
{
    enum DEFAULT_BASE_URL   = "https://discordapp.com/api";
    enum DEFAULT_USER_AGENT = "DiscordBot (https://github.com/y32/droid, " ~ VERSION ~ ")";

    private immutable string baseUrl_;
    private immutable string token_;
    private immutable string tokenProper_;
    private immutable string userAgent_;

    this(in string token, in string baseUrl = DEFAULT_BASE_URL, in string userAgent = DEFAULT_USER_AGENT)
    {
        token_       = token;
        tokenProper_ = makeTokenProper(token);
        baseUrl_     = baseUrl;
        userAgent_   = userAgent;
    }

    override JSONValue fetch(in HTTPMethod method, in string path, in string postData = "")
    in
    {
        if (postData.length == 0) assert(method == HTTPMethod.GET);
    }
    body
    {
        import vibe.stream.operations : readAllUTF8;

        return makeRequest!(JSONValue)(
            makeAPIUrl(path),
            method,
            (scope req) { if (postData.length != 0) req.bodyWriter.write(postData); },
            (scope res) => parseJSON(res.bodyReader.readAllUTF8())
        );
    }

    private R makeRequest(R)(
        in string url,
        in HTTPMethod method,
        scope void delegate(scope HTTPClientRequest) requester,
        scope R delegate(scope HTTPClientResponse) responder
    )
    {
        R toReturn;

        requestHTTP(
            url,
            (scope req) {
                req.method = method;

                req.headers["Authorization"] = tokenProper_;
                req.headers["User-Agent"]    = userAgent_;

                requester(req);
            },
            (scope res) {
                toReturn = responder(res);
            }
        );

        return toReturn;
    }

    pragma(inline, true) private string makeTokenProper(in string token) @safe const pure
    {
        return "Bot " ~ token;
    }

    pragma(inline, true) private string makeAPIUrl(in string path) @safe const pure
    {
        return baseUrl_ ~ path;
    }
}
