<?php
// mayhem/kat/run.php — known-answer oracle for php-src. Asserts concrete results of the exact
// subsystems the fuzz targets drive: the Zend compile+execute path (php-fuzz-execute /
// php-fuzz-parser), serialize/unserialize (php-fuzz-unserialize), JSON (php-fuzz-json) and core
// string/array builtins. Run by mayhem/test.sh against a clean (non-sanitized) PHP CLI. A no-op /
// broken patch to the engine changes these values (or stops PHP running), so the suite fails —
// "ran the corpus without crashing" is explicitly NOT what this checks.
$n = 0; $p = 0; $f = 0;
function ck($desc, $got, $want) {
    global $n, $p, $f; $n++;
    if ($got === $want) { $p++; echo "ok $n - $desc\n"; }
    else { $f++; echo "not ok $n - $desc (got=" . var_export($got, true) . " want=" . var_export($want, true) . ")\n"; }
}

// Zend VM: arithmetic precedence, function calls, closures, array ops.
ck("arith_precedence", 2 + 3 * 4, 14);
ck("int_pow", 2 ** 10, 1024);
ck("array_sum", array_sum([1, 2, 3, 4]), 10);
ck("sort_implode", (function () { $a = [3, 1, 2]; sort($a); return implode(",", $a); })(), "1,2,3");
ck("closure_capture", (function () { $x = 5; $g = fn($y) => $x + $y; return $g(37); })(), 42);

// ext/standard string builtins.
ck("strrev", strrev("hello"), "olleh");
ck("strtoupper", strtoupper("abc"), "ABC");
ck("str_repeat", str_repeat("ab", 3), "ababab");

// PCRE (always bundled).
ck("preg_match", (function () { return preg_match('/\d+/', 'abc123def', $m) ? $m[0] : ''; })(), "123");

// serialize / unserialize — the unserialize fuzzer's domain.
ck("serialize", serialize(["x" => 1, "y" => [2, 3]]), 'a:2:{s:1:"x";i:1;s:1:"y";a:2:{i:0;i:2;i:1;i:3;}}');
ck("unserialize", unserialize('a:2:{i:0;s:3:"foo";i:1;b:1;}'), ["foo", true]);
ck("serialize_roundtrip", unserialize(serialize([1, "two", 3.5, ["nested" => true]])), [1, "two", 3.5, ["nested" => true]]);

// JSON — the json fuzzer's domain (ext/json is always built in PHP 8+).
if (function_exists('json_encode')) {
    ck("json_encode", json_encode(["a" => 1, "b" => [true, null]]), '{"a":1,"b":[true,null]}');
    ck("json_decode", json_decode('[1,2,3]', true), [1, 2, 3]);
    ck("json_roundtrip", json_decode(json_encode(["k" => "v\u{00e9}"]), true), ["k" => "v\u{00e9}"]);
}

echo "TESTS total=$n passed=$p failed=$f\n";
exit($f > 0 ? 1 : 0);
