# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# fhir - white-box tests for the core topic, and the fake server the other
# overlays use. Spliced into fhir_test.j via include.

/**
 * A running fake FHIR server.
 *
 * @field srv {httpd.Server} the server
 * @field base {string} its base URL, ending in /fhir
 * @field t {task of list of string} the task serving it; its result is every request seen
 */
def struct Fake {
    srv as httpd.Server,
    base as string,
    t as task of list of string
};

/**
 * Mark a call that should have thrown.
 *
 * @param what {string} what got through
 * @throws {Error} always, kind "missed"
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Start a fake FHIR server. An answer is looked up by `METHOD path?query`,
 * then `METHOD path`; it is the status, a newline, header lines `Name: value`,
 * an empty line and the body; `BASE` in it becomes the server's base URL. A
 * request with no answer gets 404 and an OperationOutcome; status
 * `SLEEP <ms>` waits that long and answers 200 `{}`.
 *
 * @param answers {map of string to string} the answers
 * @return {Fake} the server
 */
func startFake(answers as map of string to string) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def base as string init "http://" + httpd.address($srv) + "/fhir";
    def t as task of list of string init spawn {
        return serveFake($srv, $answers, $base);
    };
    return Fake{srv: $srv, base: $base, t: $t};
}

/**
 * Serve requests until the server shuts down.
 *
 * @param srv {httpd.Server} the server
 * @param answers {map of string to string} the answers
 * @param base {string} the base URL
 * @return {list of string} each request as `METHOD path?query|header=value|...|body`
 */
func serveFake(srv as httpd.Server, answers as map of string to string, base as string) {
    def seen as list of string init [];
    while (true) {
        def req as httpd.Request;
        try {
            $req = httpd.accept($srv);
        } catch (e) {
            return $seen;
        }
        def target as string init httpd.path($req);
        if (httpd.rawQuery($req) != "") {
            $target = $target + "?" + httpd.rawQuery($req);
        }
        def key as string init httpd.method($req) + " " + $target;
        def line as list of string init [$key];
        for (def h in ["Accept", "Content-Type", "Authorization", "Prefer", "If-Match"]) {
            if (httpd.header($req, $h) != "") {
                $line[] = $h + "=" + httpd.header($req, $h);
            }
        }
        $line[] = encoding.decode("utf-8", httpd.body($req));
        $seen[] = strings.join($line, "|");
        def spec as string init "404\n\n" +
            '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-found","diagnostics":"no answer for ' +
            $key + '"}]}';
        if (maps.has($answers, $key)) {
            $spec = $answers[$key];
        } elseif (maps.has($answers, httpd.method($req) + " " + httpd.path($req))) {
            $spec = $answers[httpd.method($req) + " " + httpd.path($req)];
        }
        $spec = strings.replace($spec, "BASE", $base);
        def split as int init strings.indexOf($spec, "\n\n");
        def head as list of string init strings.split($spec[..$split], "\n");
        for (def h in $head[1..]) {
            def at as int init strings.indexOf($h, ": ");
            httpd.setHeader($req, $h[..$at], $h[$at + 2..]);
        }
        if (strings.startsWith($head[0], "SLEEP ")) {
            time.sleep(time.fromMilliseconds(convert.toInt($head[0][len("SLEEP ")..])));
            httpd.respond($req, 200, '{}');
        } else {
            httpd.respond($req, convert.toInt($head[0]), $spec[$split + 2..]);
        }
    }
}

/**
 * Stop a fake and return what it saw.
 *
 * @param f {Fake} the fake
 * @return {list of string} the requests
 */
func stopFake(f as Fake) {
    httpd.shutdown($f.srv);
    return task.wait($f.t);
}

/**
 * A client of a fake.
 *
 * @param f {Fake} the fake
 * @return {Client} the client
 */
func fakeClient(f as Fake) {
    return client($f.base);
}

func testClientUrlsAreChecked() {
    testing.assertEqual(
        client("https://fhir.example.org/r4/").baseUrl,
        "https://fhir.example.org/r4");
    testing.assertEqual(client("http://localhost:8080/fhir").baseUrl, "http://localhost:8080/fhir");
    for (def bad in [
        "ftp://x/fhir",
        "https://x/fhir?a=1",
        "https://x/f#h",
        "fhir.example.org",
        "https://x y/"
    ]) {
        try {
            client($bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a base URL is");
        }
    }
    try {
        client("http://fhir.example.org/r4");
        missed("plain http");
    } catch (e) {
        testing.assertContains($e.message, "would send health data in clear");
    }
    def c as Client init client("https://fhir.example.org/r4");
    $c.baseUrl = "http://fhir.example.org/r4";
    $c = withPlainHttp($c);
    checkUrl($c);
}

func testWithFunctionsCheckTheirValues() {
    def c as Client init client("https://fhir.example.org/r4");
    testing.assertEqual(withToken($c, "abc").headers["Authorization"], "Bearer abc");
    testing.assertEqual(withHeader($c, "X-Tenant", "a").headers["X-Tenant"], "a");
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withMaxBytes($c, 65536).maxBytes, 65536);
    testing.assertEqual(withMaxPages($c, 3).maxPages, 3);
    testing.assertTrue(withTls($c, http.TlsOptions{skipVerify: true}).tls.skipVerify);
    for (def bad in ["", "a b", "a\nb"]) {
        try {
            withToken($c, $bad);
            missed("token " + $bad);
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    try {
        withHeader($c, "X Bad", "a");
        missed("header name");
    } catch (e) {
        testing.assertEqual($e.kind, "fhir");
    }
    for (def ms in [999, 86400001]) {
        try {
            withTimeout($c, $ms);
            missed("timeout");
        } catch (e) {
            testing.assertContains($e.message, "the timeout must be 1000 to 86400000");
        }
    }
}

func testQueriesAreEncoded() {
    testing.assertEqual(queryOf([]), "");
    testing.assertEqual(
        queryOf(["family=Doe Jr", "birthdate=ge1980-01-01", "name:exact=a&b", "_count=5"]),
        "?family=Doe%20Jr&birthdate=ge1980-01-01&name:exact=a%26b&_count=5");
    for (def bad in ["family", "=Doe", "fam ily=x", "a&b=c"]) {
        try {
            queryOf([$bad]);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a search parameter is name=value");
        }
    }
}

func testOtherErrorsKeepTheFhirKind() {
    try {
        fail("boom");
    } catch (e) {
        testing.assertEqual($e.kind, "fhir");
        testing.assertEqual($e.message, "fhir: boom");
    }
}
