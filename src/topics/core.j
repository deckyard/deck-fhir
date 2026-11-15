# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - core: the client and its settings, URLs, the HTTP exchange with its
# deadline, and errors carrying the server's OperationOutcome. Spliced into
# fhir.j via include.

/** How long one request may take, in milliseconds: one minute. */
export def const DEFAULT_TIMEOUT_MS as int init 60000;

/** The largest response read, in bytes: 8 MiB. */
export def const DEFAULT_MAX_BYTES as int init 8388608;

/** The most pages `search` and `history` follow: 100. */
export def const DEFAULT_MAX_PAGES as int init 100;

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]';

# a resource type, an id, a version id, a search parameter name
def const TYPE as string init '^[A-Z][A-Za-z]{1,63}$';
def const ID as string init '^[A-Za-z0-9.-]{1,64}$';
def const PARAM as string init '^[A-Za-z_][A-Za-z0-9_.:-]*$';

# the hosts plain http is allowed to without `withPlainHttp`
def const LOOPBACK as list of string init ["127.0.0.1", "localhost", "[::1]"];

# an HTTP header name (an RFC 9110 token)
def const TOKEN as string init "^[A-Za-z0-9!#$%&'*+.^_`|~-]+$";

# the media type of FHIR JSON
def const FHIR_JSON as string init "application/fhir+json";

/**
 * How to reach a FHIR server. Build it with `client` and change it with the
 * `with*` functions.
 *
 * @field baseUrl {string} the server's base URL, without a trailing slash, such as `https://fhir.example.org/r4`
 * @field headers {map of string to string} headers sent with every request, such as `Authorization`
 * @field tls {http.TlsOptions} certificate checks for an `https` URL
 * @field allowPlainHttp {bool} whether a plain `http` URL to another machine is allowed (health data and the token then cross the network in clear)
 * @field timeoutMs {int} how long one request may take
 * @field maxBytes {int} the largest response read
 * @field maxPages {int} the most pages `search` and `history` follow
 */
export def struct Client {
    baseUrl as string,
    headers as map of string to string,
    tls as http.TlsOptions,
    allowPlainHttp as bool,
    timeoutMs as int,
    maxBytes as int,
    maxPages as int
};

/**
 * Throw a fhir error.
 *
 * @param message {string} what went wrong, without the `fhir: ` prefix
 * @throws {Error} kind "fhir", always
 */
func fail(message as string) {
    throw Error{kind: "fhir", message: "fhir: " + $message};
}

/**
 * Throw a reached cap: kind "limit", the message as `fail` writes it.
 *
 * @param message {string} what was over the cap, without the `fhir: ` prefix
 * @throws {Error} kind "limit", always
 */
func failLimit(message as string) {
    throw Error{kind: "limit", message: "fhir: " + $message};
}

/**
 * Throw a deadline that passed: kind "timeout", the message as `fail`
 * writes it.
 *
 * @param message {string} what took too long, without the `fhir: ` prefix
 * @throws {Error} kind "timeout", always
 */
func failTimeout(message as string) {
    throw Error{kind: "timeout", message: "fhir: " + $message};
}

/**
 * Whether a caught error has a kind every library shares, which a wrapper
 * passes on as it is: a reached cap, a deadline, a closed connection, a
 * cancelled task or a network failure (a `net.NetError`).
 *
 * @param kind {string} the error's kind
 * @return {bool} whether it passes on
 */
func generic(kind as string) {
    return lists.contains(["limit", "timeout", "closed", "cancelled", "net"], $kind);
}

/**
 * A request the server answered with a status other than 2xx. Caught, it
 * has kind `fhir.http`, which no other fhir error uses: test the kind, then
 * read `status` and `issues`.
 *
 * @field kind {string} `fhir.http`
 * @field message {string} the request, the server's diagnostics and `(HTTP nnn)`
 * @field status {int} the HTTP status, such as 404, 409 or 412
 * @field issues {list of Issue} the issues of the OperationOutcome the server sent, empty when it sent none or a malformed one
 * @example
 *   try {
 *       fhir.read($c, "Patient", "123");
 *   } catch (e) {
 *       if ($e.kind == "fhir.http" and $e.status == 404) {
 *           io.printf("gone\n");
 *       }
 *   }
 */
export def struct HttpError {
    kind as string,
    message as string,
    status as int,
    issues as list of Issue
};

/**
 * Throw the HttpError of a response that is not 2xx.
 *
 * @param what {string} the request, for the message
 * @param r {http.Response} the response
 * @throws {HttpError} kind "fhir.http", always
 */
func failHttp(what as string, r as http.Response) {
    def found as list of Issue init outcomeIssues($r);
    throw HttpError{
        kind: "fhir.http",
        message: io.sprintf("fhir: %s: %s (HTTP %d)", $what, explain($found, $r), $r.status),
        status: $r.status,
        issues: $found
    };
}

/**
 * Text quoted for an error message: at most 200 characters, control and bidi
 * characters as `?`.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes
 */
func shown(s as string) {
    def text as string init $s;
    if (len($text) > 200) {
        $text = $text[..200] + "...";
    }
    return "\"" + regex.replace(UNSHOWN, $text, "?") + "\"";
}

/**
 * Server-controlled text made safe for an error message: control and bidi
 * characters as `?`, at most a number of characters.
 *
 * @param s {string} the text
 * @param most {int} the most characters kept
 * @return {string} the text
 */
func cleaned(s as string, most as int) {
    def text as string init $s;
    if (len($text) > $most) {
        $text = $text[..$most] + "...";
    }
    return regex.replace(UNSHOWN, $text, "?");
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

/**
 * A client for a FHIR server: no authentication, the default deadline,
 * response cap and page cap. Plain `http` is refused except to this machine:
 * add `withPlainHttp` to allow it.
 *
 * @param baseUrl {string} the server's base URL, such as `https://fhir.example.org/r4`
 * @return {Client} the client
 * @throws {Error} kind "fhir" when the URL is not an absolute http(s) URL without query or fragment, or plain http to another machine
 * @example
 *   def c as fhir.Client init fhir.client("https://fhir.example.org/r4");
 */
export func client(baseUrl as string) {
    def base as string init $baseUrl;
    while (strings.endsWith($base, "/")) {
        $base = $base[..len($base) - 1];
    }
    def c as Client init Client{
        baseUrl: $base,
        headers: {},
        tls: http.TlsOptions{},
        allowPlainHttp: false,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        maxBytes: DEFAULT_MAX_BYTES,
        maxPages: DEFAULT_MAX_PAGES
    };
    checkUrl($c);
    return $c;
}

/**
 * Refuse a base URL that is not absolute http(s), has a query or fragment,
 * or is plain http to another machine without `allowPlainHttp`.
 *
 * @param c {Client} the client
 */
func checkUrl(c as Client) {
    def m as regex.Match init regex.find(
        '^(https?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[^?#\s]*)?$',
        $c.baseUrl);
    if ($m.start < 0) {
        fail("a base URL is http(s)://host[:port][/path] without query or fragment, got " +
            shown($c.baseUrl));
    }
    if ($m.groups[0] == "http" and not $c.allowPlainHttp and
        not lists.contains(LOOPBACK, strings.lower($m.groups[1]))) {
        fail("plain http to " + shown($m.groups[1]) +
            " would send health data in clear: use https, or withPlainHttp");
    }
}

/**
 * The client sending a bearer token with every request.
 *
 * @param c {Client} the client
 * @param token {string} the access token
 * @return {Client} the client
 * @example
 *   $c = fhir.withToken($c, $token.accessToken);
 */
export func withToken(c as Client, token as string) {
    if ($token == "" or regex.matches('[\x00-\x20\x7f]', $token)) {
        fail("a token is not empty and has no spaces or control characters");
    }
    $c.headers["Authorization"] = "Bearer " + $token;
    return $c;
}

/**
 * The client sending a header with every request.
 *
 * @param c {Client} the client
 * @param name {string} the header name
 * @param value {string} its value
 * @return {Client} the client
 */
export func withHeader(c as Client, name as string, value as string) {
    if (not regex.matches(TOKEN, $name) or
        regex.matches('[\x00-\x1f\x7f]', $value)) {
        fail("a header name is a token and its value has no control characters: " + shown($name));
    }
    for (def k in maps.keys($c.headers)) {
        if (strings.lower($k) == strings.lower($name)) {
            $c.headers = maps.delete($c.headers, $k);
        }
    }
    $c.headers[$name] = $value;
    return $c;
}

/**
 * The client with certificate options for `https`.
 *
 * @param c {Client} the client
 * @param tls {http.TlsOptions} the options (`caCert`, `skipVerify`)
 * @return {Client} the client
 */
export func withTls(c as Client, tls as http.TlsOptions) {
    $c.tls = $tls;
    return $c;
}

/**
 * The client allowed to use plain `http` to another machine. Health data and
 * the token cross the network in clear.
 *
 * @param c {Client} the client
 * @return {Client} the client
 */
export func withPlainHttp(c as Client) {
    $c.allowPlainHttp = true;
    return $c;
}

/**
 * The client with another deadline for each request.
 *
 * @param c {Client} the client
 * @param ms {int} 1000 to 86400000 milliseconds
 * @return {Client} the client
 */
export func withTimeout(c as Client, ms as int) {
    checkRange($ms, 1000, 86400000, "the timeout");
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * The client with another response cap.
 *
 * @param c {Client} the client
 * @param most {int} 65536 to 268435456 bytes
 * @return {Client} the client
 */
export func withMaxBytes(c as Client, most as int) {
    checkRange($most, 65536, 268435456, "the largest response");
    $c.maxBytes = $most;
    return $c;
}

/**
 * The client with another page cap for `search` and `history`.
 *
 * @param c {Client} the client
 * @param pages {int} 1 to 100000
 * @return {Client} the client
 */
export func withMaxPages(c as Client, pages as int) {
    checkRange($pages, 1, 100000, "the page count");
    $c.maxPages = $pages;
    return $c;
}

/**
 * Refuse a resource type that is not a FHIR type name.
 *
 * @param type {string} the type
 */
func checkType(type as string) {
    if (not regex.matches(TYPE, $type)) {
        fail("a resource type is a capitalised name such as Patient, got " + shown($type));
    }
}

/**
 * Refuse an id that is not a FHIR id.
 *
 * @param id {string} the id
 * @param what {string} what it is
 */
func checkId(id as string, what as string) {
    if (not regex.matches(ID, $id) or regex.matches('^\.+$', $id)) {
        fail($what + " is 1 to 64 letters, digits, '-' and '.', not only dots, got " + shown($id));
    }
}

/**
 * A query string from `name=value` parameters, each value percent-encoded.
 *
 * @param query {list of string} the parameters, such as `family=Doe` or `birthdate=ge1980-01-01`
 * @return {string} `?a=b&c=d`, or `""` without parameters
 */
func queryOf(query as list of string) {
    if (len($query) == 0) {
        return "";
    }
    def parts as list of string init [];
    for (def q in $query) {
        def at as int init strings.indexOf($q, "=");
        if ($at < 1 or not regex.matches(PARAM, $q[..$at])) {
            fail("a search parameter is name=value with a name such as family or name:exact, got " +
                shown($q));
        }
        $parts[] = $q[..$at] + "=" + uri.encode($q[$at + 1..]);
    }
    return "?" + strings.join($parts, "&");
}

/**
 * Whether a URL the server gave (a next link, a Location) belongs to this
 * server, so the token is never sent elsewhere.
 *
 * @param c {Client} the client
 * @param url {string} the URL
 * @return {bool} true when it starts with the base URL and `/` or `?`
 */
func isOwn(c as Client, url as string) {
    return strings.startsWith($url, $c.baseUrl + "/") or strings.startsWith($url, $c.baseUrl + "?");
}

/**
 * Send one request to the server within the deadline.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param url {string} the full URL
 * @param extra {map of string to string} headers for this request
 * @param body {string} the body, `""` for none
 * @param what {string} the request, for messages
 * @return {http.Response} the response, any status
 */
func exchange(
    c as Client,
    method as string,
    url as string,
    extra as map of string to string,
    body as string,
    what as string) {
    def headers as map of string to string init $c.headers;
    $headers["Accept"] = FHIR_JSON;
    if ($body != "") {
        $headers["Content-Type"] = FHIR_JSON + "; charset=utf-8";
    }
    for (def k in maps.keys($extra)) {
        $headers[$k] = $extra[$k];
    }
    def o as http.Options init http.defaultOptions();
    $o.timeoutMs = $c.timeoutMs;
    $o.maxBytes = $c.maxBytes;
    $o.tls = $c.tls;
    def t as task of http.Response init spawn {
        return http.send($method, $url, $headers, $body, $o);
    };
    try {
        return task.waitTimeout($t, $c.timeoutMs);
    } catch (e) {
        # A cancel is kind "cancelled" (jennifer after 0.25); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            task.cancel($t);
            task.discard($t);
            throw $e;
        }
        if ($e.kind == "timeout") {
            task.cancel($t);
            task.discard($t);
            failTimeout(io.sprintf("%s: no answer within %d ms", $what, $c.timeoutMs));
        }
        # A cap is kind "limit" (jennifer after 0.25: http, net); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "limit" or strings.startsWith($e.message, "http: response body exceeds ")) {
            failLimit(io.sprintf("%s: the response is over %d bytes", $what, $c.maxBytes));
        }
        # the other kinds every library shares (a closed connection, a
        # net.NetError) pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail($what + ": cannot reach " + shown($url) + ": " + $e.message);
    }
}

/**
 * Send a request and read the JSON response, failing on a status that is
 * not 2xx with the diagnostics of the server's OperationOutcome.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param url {string} the full URL
 * @param extra {map of string to string} headers for this request
 * @param body {string} the body
 * @param what {string} the request, for messages
 * @return {json.Value} the response, JSON `null` when it has no body
 */
func request(
    c as Client,
    method as string,
    url as string,
    extra as map of string to string,
    body as string,
    what as string) {
    def r as http.Response init exchange($c, $method, $url, $extra, $body, $what);
    if ($r.status < 200 or $r.status > 299) {
        failHttp($what, $r);
    }
    return jsonOf($r.body, $what);
}

/**
 * A response body as JSON.
 *
 * @param body {string} the body
 * @param what {string} the request, for messages
 * @return {json.Value} the JSON, `null` when the body is empty
 */
func jsonOf(body as string, what as string) {
    if (strings.trim($body) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($body);
    } catch (e) {
        # the decoder's nesting and node caps are a reached cap, kind "limit"
        if ($e.kind == "limit") {
            failLimit($what + ": " + cleaned($e.message, 1000));
        }
        fail($what + ": the response is not JSON: " + shown($body));
    }
}

/**
 * The issues of the OperationOutcome a failed response carries; empty when
 * its body is not one, or a malformed one (the status still tells).
 *
 * @param r {http.Response} the response
 * @return {list of Issue} the issues
 */
func outcomeIssues(r as http.Response) {
    def none as list of Issue init [];
    try {
        def v as json.Value init json.decode($r.body);
        if (json.typeOf($v, "/resourceType") == "string" and
            json.asString($v, "/resourceType") == "OperationOutcome") {
            return issues($v);
        }
    } catch (e) {
        return $none;
    }
    return $none;
}

/**
 * What a failed response says: its OperationOutcome's issues when it has
 * any, else the status text.
 *
 * @param found {list of Issue} the response's issues, from `outcomeIssues`
 * @param r {http.Response} the response
 * @return {string} the explanation
 */
func explain(found as list of Issue, r as http.Response) {
    def texts as list of string init [];
    for (def i in $found) {
        def t as string init $i.diagnostics;
        if ($t == "") {
            $t = $i.text;
        }
        if ($t == "") {
            $t = $i.code;
        }
        $texts[] = $t;
    }
    if (len($texts) > 0) {
        return cleaned(strings.join($texts, "; "), 1000);
    }
    return cleaned($r.statusText, 100);
}
