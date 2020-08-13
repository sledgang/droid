module droid.gateway.compression;

import droid.exception;
import std.zlib,
       std.stdio,
       std.conv : to;

enum CompressionType : string {
    NONE        = "",
    ZLIB        = "zlib",
    ZLIB_STREAM = "zlib-stream"
}
class Decompressor {
    string read(ubyte[] data) {
        throw new DroidException("Compression type not supported!");
    }
}

class ZLibStream : Decompressor {
    const ubyte[] ZLIB_SUFFIX = [0x0, 0x0, 0xFF, 0xFF];
    UnCompress decompressor;

    ubyte[] buffer;

    this() {
        decompressor = new UnCompress(HeaderFormat.deflate);
    }

    /*
     * Reads a zlib stream from the websocket
     * This will append the data to a buffer,
     * returning nothing if the data is not a full zlib frame
     * otherwise, returning the decompressed string.
     */
    override string read(ubyte[] data) {
        buffer ~= data;

        if (data[$-4..$] != ZLIB_SUFFIX) {
            return "";
        }

        string decompressed = to!string(decompressor.uncompress(buffer));
        decompressor.flush();
        buffer = null;

        return decompressed;
    }
}
