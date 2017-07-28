module droid.cache.primitives;

import std.traits;

private enum bool hasWrite(C) =
    is(ReturnType!((C c) => c.write("id", 123)) == string) &&
    is(typeof((C c) => c.write("id", 123)));

private enum bool hasRead(C) =
    is(ReturnType!((C c) => c.read!(int)("id")) == int) &&
    is(typeof((C c) => c.read!(int)("id")));

private enum bool hasFetch(C) =
    is(ReturnType!((C c) => c.fetch!(int)("id", id => 321)) == int) &&
    is(typeof((C c) => c.fetch!(int)("id", id => 321)));

private enum bool hasRemove(C) =
    is(ReturnType!((C c) => c.remove("id")) == bool) &&
    is(typeof((C c) => c.remove("id")));

private enum bool hasInOp(C) =
    is(ReturnType!((C c) => "id" in c) == bool) &&
    is(typeof((C c) => "id" in c));

enum bool isCache(C) =
    hasWrite!(C)  &&
    hasRead!(C)   &&
    hasFetch!(C)  &&
    hasRemove!(C) &&
    hasInOp!(C);

