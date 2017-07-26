module droid.exception;

import std.exception : basicExceptionCtors;

class DroidException : Exception
{
    mixin basicExceptionCtors;
}
