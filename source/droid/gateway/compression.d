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
    const ulong[] ZLIB_SUFFIX = [0x0, 0x0, 0xFF, 0xFF];
    UnCompress decompressor;

    this() {
        decompressor = new UnCompress(HeaderFormat.deflate);
    }

    override string read(ubyte[] data) {
        if (data[$-4..$] != ZLIB_SUFFIX) {
            throw new DroidException("ZLib-Stream compression enabled but invalid data was recieved!");
        }

        string decompressed = to!string(decompressor.uncompress(data));
        decompressor.flush();

        return decompressed;
    }
}
