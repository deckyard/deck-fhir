# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - rest: the RESTful API. Capabilities, read, vread, search with paging,
# create, update and patch with version checks, delete, history,
# transactions and batches, operations, and `call` for the rest. Spliced into
# fhir.j via include.

# an operation path: [Type[/id]/]$name
def const OPERATION as string init '^([A-Z][A-Za-z]{1,63}(/[A-Za-z0-9.-]*[A-Za-z0-9-][A-Za-z0-9.-]*)?/)?\$[a-z][A-Za-z0-9-]*$';

# a path for `call`: segments of letters, digits and `-._$`
def const CALL_PATH as string init '^[A-Za-z0-9_$.-]+(/[A-Za-z0-9_$.-]+)*$';

/**
 * Refuse a response that is not a resource of the expected type.
 *
 * @param v {json.Value} the response
 * @param type {string} the type expected
 * @param what {string} the request, for messages
 * @return {json.Value} the response
 */
func expect(v as json.Value, type as string, what as string) {
    if (json.typeOf($v) != "map" or json.typeOf($v, "/resourceType") != "string" or
        json.asString($v, "/resourceType") != $type) {
        fail($what + ": the server did not return a resource of type " + $type);
    }
    return $v;
}

/**
 * The server's CapabilityStatement: its FHIR version, resources, search
 * parameters and operations.
 *
 * @param c {Client} the client
 * @return {json.Value} the CapabilityStatement
 * @throws {Error} kind "fhir" when the server cannot be reached, fails, or returns something else
 * @example
 *   io.printf("FHIR %s\n", json.asString(fhir.capabilities($c), "/fhirVersion"));
 */
export func capabilities(c as Client) {
    def v as json.Value init request($c, "GET", $c.baseUrl + "/metadata", {}, "", "capabilities");
    return expect($v, "CapabilityStatement", "capabilities");
}

/**
 * Read a resource.
 *
 * @param c {Client} the client
 * @param type {string} the resource type, such as `Patient`
 * @param id {string} the id
 * @return {json.Value} the resource
 * @throws {Error} kind "fhir" when it does not exist (HTTP 404), was deleted (410), the request fails, or the type or id is malformed
 * @example
 *   def p as json.Value init fhir.read($c, "Patient", "123");
 */
export func read(c as Client, type as string, id as string) {
    def path as string init reference($type, $id);
    return expect(
        request($c, "GET", $c.baseUrl + "/" + $path, {}, "", "read " + $path),
        $type,
        "read " + $path);
}

/**
 * Read one version of a resource.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param id {string} the id
 * @param version {string} the version id
 * @return {json.Value} the resource as it was in that version
 * @throws {Error} kind "fhir" as `read` does
 */
export func vread(c as Client, type as string, id as string, version as string) {
    checkId($version, "a version id");
    def path as string init reference($type, $id) + "/_history/" + $version;
    return expect(
        request($c, "GET", $c.baseUrl + "/" + $path, {}, "", "vread " + $path),
        $type,
        "vread " + $path);
}

/**
 * The first page of a search, as the server's Bundle.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param query {list of string} search parameters as `name=value`, such as `family=Doe`, `birthdate=ge1980-01-01`, `_count=50`; values are percent-encoded here
 * @return {json.Value} the searchset Bundle
 * @throws {Error} kind "fhir" when a parameter is malformed or the request fails
 */
export func searchBundle(c as Client, type as string, query as list of string) {
    checkType($type);
    def url as string init $c.baseUrl + "/" + $type + queryOf($query);
    return expect(request($c, "GET", $url, {}, "", "search " + $type), "Bundle", "search " + $type);
}

/**
 * The next page of a search or history Bundle.
 *
 * @param c {Client} the client
 * @param b {json.Value} a page
 * @return {list of json.Value} the next page, or nothing when this is the last
 * @throws {Error} kind "fhir" when the next link points away from the server, or the request fails
 */
export func nextBundle(c as Client, b as json.Value) {
    def out as list of json.Value init [];
    def link as string init nextLink($b);
    if ($link == "") {
        return $out;
    }
    if (not isOwn($c, $link)) {
        fail("the next link " + shown($link) + " leaves the server " + shown($c.baseUrl));
    }
    $out[] = expect(request($c, "GET", $link, {}, "", "next page"), "Bundle", "next page");
    return $out;
}

/**
 * A bundle's `next` link.
 *
 * @param b {json.Value} the bundle
 * @return {string} the URL, `""` when there is none
 */
func nextLink(b as json.Value) {
    if (json.typeOf($b, "/link") != "list") {
        return "";
    }
    for (def i in 0..json.length($b, "/link")) {
        def at as string init "/link/" + convert.toString($i);
        if (text($b, $at + "/relation") == "next") {
            return text($b, $at + "/url");
        }
    }
    return "";
}

/**
 * The resources of a page that matched the search: entries whose
 * `search.mode` is `match` or absent, not `include`d ones or outcomes.
 *
 * @param b {json.Value} the page
 * @return {list of json.Value} the resources
 */
func matches(b as json.Value) {
    def out as list of json.Value init [];
    if (json.typeOf($b, "/entry") != "list") {
        return $out;
    }
    for (def i in 0..json.length($b, "/entry")) {
        def at as string init "/entry/" + convert.toString($i);
        def mode as string init text($b, $at + "/search/mode");
        if (($mode == "" or $mode == "match") and json.typeOf($b, $at + "/resource") == "map") {
            $out[] = json.get($b, $at + "/resource");
        }
    }
    return $out;
}

/**
 * Search, following every page: the resources that matched, in order.
 * Included resources (`_include`) are left out; read them with
 * `searchBundle` and `nextBundle`.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param query {list of string} search parameters as `name=value`
 * @return {list of json.Value} the matching resources
 * @throws {Error} kind "fhir" when a parameter is malformed, a request fails or a next link leaves the server; kind "limit" when the result has more pages than `maxPages` or more bytes in all its pages than `maxBytes`
 * @example
 *   for (def p in fhir.search($c, "Patient", ["family=Doe", "birthdate=ge1980-01-01"])) {
 *       io.printf("%s\n", fhir.idOf($p));
 *   }
 */
export func search(c as Client, type as string, query as list of string) {
    checkType($type);
    return firstPage($c, $c.baseUrl + "/" + $type + queryOf($query), "search " + $type);
}

/**
 * The matching resources of a first page and every page after it, within
 * the page cap and, for all pages together, the response cap.
 *
 * @param c {Client} the client
 * @param first {json.Value} the first page
 * @param size {int} the first page's size in bytes
 * @param what {string} the request, for messages
 * @return {list of json.Value} the resources
 */
func allPages(c as Client, first as json.Value, size as int, what as string) {
    def out as list of json.Value init matches($first);
    def total as int init $size;
    def link as string init nextLink($first);
    def pages as int init 1;
    while ($link != "") {
        $pages = $pages + 1;
        if ($pages > $c.maxPages) {
            failLimit(io.sprintf(
                "%s: more than %d pages; narrow it or raise withMaxPages",
                $what,
                $c.maxPages));
        }
        if (not isOwn($c, $link)) {
            fail("the next link " + shown($link) + " leaves the server " + shown($c.baseUrl));
        }
        def r as http.Response init exchange($c, "GET", $link, {}, "", $what);
        if ($r.status < 200 or $r.status > 299) {
            failHttp($what, $r);
        }
        $total = $total + encoding.lenBytes($r.body);
        if ($total > $c.maxBytes) {
            failLimit(io.sprintf(
                "%s: the pages hold more than %d bytes; narrow it or raise withMaxBytes",
                $what,
                $c.maxBytes));
        }
        def page as json.Value init expect(jsonOf($r.body, $what), "Bundle", $what);
        for (def m in matches($page)) {
            $out[] = $m;
        }
        $link = nextLink($page);
    }
    return $out;
}

/**
 * The first page of a search or history, with its size.
 *
 * @param c {Client} the client
 * @param url {string} the URL
 * @param what {string} the request, for messages
 * @return {list of json.Value} the matching resources of every page
 */
func firstPage(c as Client, url as string, what as string) {
    def r as http.Response init exchange($c, "GET", $url, {}, "", $what);
    if ($r.status < 200 or $r.status > 299) {
        failHttp($what, $r);
    }
    return allPages(
        $c,
        expect(jsonOf($r.body, $what), "Bundle", $what),
        encoding.lenBytes($r.body),
        $what);
}

/**
 * Create a resource; the server assigns its id.
 *
 * @param c {Client} the client
 * @param resource {json.Value} the resource, without an id
 * @return {json.Value} the resource as stored, with its id and version
 * @throws {Error} kind "fhir" when the resource has an id or no type, the server refuses it (HTTP 400, 422, ...), or the request fails
 * @example
 *   def p as json.Value init fhir.create($c, json.decode("{\"resourceType\":\"Patient\",\"name\":[{\"family\":\"Doe\"}]}"));
 *   io.printf("created %s\n", fhir.referenceOf($p));
 */
export func create(c as Client, resource as json.Value) {
    def type as string init resourceType($resource);
    if (idOf($resource) != "") {
        fail("create " + $type + ": the server assigns the id; update sets one");
    }
    def r as http.Response init exchange(
        $c,
        "POST",
        $c.baseUrl + "/" + $type,
        {"Prefer": "return=representation"},
        json.encode($resource),
        "create " + $type);
    return stored($c, $r, $type, "create " + $type);
}

/**
 * The resource a create or update stored: the response body, or the
 * resource at its Location when the server sent none.
 *
 * @param c {Client} the client
 * @param r {http.Response} the response
 * @param type {string} the type
 * @param what {string} the request, for messages
 * @return {json.Value} the resource
 */
func stored(c as Client, r as http.Response, type as string, what as string) {
    if ($r.status < 200 or $r.status > 299) {
        failHttp($what, $r);
    }
    def location as string init http.header($r, "Location");
    if (strings.trim($r.body) != "") {
        def v as json.Value init jsonOf($r.body, $what);
        def isOutcome as bool init json.typeOf($v, "/resourceType") == "string" and
            json.asString($v, "/resourceType") == "OperationOutcome";
        if (not $isOutcome or $location == "") {
            return expect($v, $type, $what);
        }
    }
    if ($location == "") {
        fail($what + ": done, but the server returned neither the resource nor its Location");
    }
    def url as string init $location;
    if (not isOwn($c, $url)) {
        if (not regex.matches(
            '^[A-Z][A-Za-z]{1,63}/[A-Za-z0-9.-]{1,64}(/_history/[A-Za-z0-9.-]{1,64})?$',
            $url) or
            regex.matches('/\.+(/|$)', $url)) {
            fail($what + ": done, but its Location " + shown($location) + " is not on this server");
        }
        $url = $c.baseUrl + "/" + $url;
    }
    return expect(request($c, "GET", $url, {}, "", $what), $type, $what);
}

/**
 * Update a resource, or create it with the id it has. When the resource
 * carries `meta.versionId`, the update only succeeds if that is still the
 * current version (`If-Match`); otherwise the server answers HTTP 412.
 * Remove `meta.versionId` to overwrite whatever is there.
 *
 * @param c {Client} the client
 * @param resource {json.Value} the resource, with its id
 * @return {json.Value} the resource as stored, with its new version
 * @throws {Error} kind "fhir" when the resource has no id, the version no longer matches (HTTP 412), the server refuses it, or the request fails
 * @example
 *   def p as json.Value init fhir.read($c, "Patient", "123");
 *   $p = json.set($p, "/active", false);
 *   $p = fhir.update($c, $p);
 */
export func update(c as Client, resource as json.Value) {
    def path as string init referenceOf($resource);
    def extra as map of string to string init {"Prefer": "return=representation"};
    def version as string init versionOf($resource);
    if ($version != "") {
        checkId($version, "a version id");
        $extra["If-Match"] = "W/\"" + $version + "\"";
    }
    def r as http.Response init exchange(
        $c,
        "PUT",
        $c.baseUrl + "/" + $path,
        $extra,
        json.encode($resource),
        "update " + $path);
    return stored($c, $r, resourceType($resource), "update " + $path);
}

/**
 * Change a resource with a JSON Patch (RFC 6902), when `version` is not
 * empty only if it is still the current version.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param id {string} the id
 * @param operations {json.Value} the patch: a list of operations such as `{"op": "replace", "path": "/active", "value": false}`
 * @param version {string} the version the patch applies to, `""` for any
 * @return {json.Value} the resource as stored
 * @throws {Error} kind "fhir" when the patch is not a list, the version no longer matches (HTTP 412), the server refuses it, or the request fails
 * @example
 *   $p = fhir.patch($c, "Patient", "123", json.decode("[{\"op\":\"replace\",\"path\":\"/active\",\"value\":false}]"), "");
 */
export func patch(
    c as Client,
    type as string,
    id as string,
    operations as json.Value,
    version as string) {
    def path as string init reference($type, $id);
    if (json.typeOf($operations) != "list") {
        fail("patch " + $path + ": a JSON Patch is a list of operations");
    }
    def extra as map of string to string init {
        "Prefer": "return=representation",
        "Content-Type": "application/json-patch+json"
    };
    if ($version != "") {
        checkId($version, "a version id");
        $extra["If-Match"] = "W/\"" + $version + "\"";
    }
    def r as http.Response init exchange(
        $c,
        "PATCH",
        $c.baseUrl + "/" + $path,
        $extra,
        json.encode($operations),
        "patch " + $path);
    return stored($c, $r, $type, "patch " + $path);
}

/**
 * Delete a resource.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param id {string} the id
 * @throws {Error} kind "fhir" when the server refuses (HTTP 409 when others refer to it, ...) or the request fails
 */
export func delete(c as Client, type as string, id as string) {
    def path as string init reference($type, $id);
    request($c, "DELETE", $c.baseUrl + "/" + $path, {}, "", "delete " + $path);
}

/**
 * Every version of a resource, newest first, following every page.
 *
 * @param c {Client} the client
 * @param type {string} the resource type
 * @param id {string} the id
 * @return {list of json.Value} the versions; a deleted version has no resource and is left out
 * @throws {Error} kind "fhir" when the request fails; kind "limit" when the history has more pages than `maxPages` or more bytes than `maxBytes`; kind "timeout", "closed" or "net" as the transport threw it
 */
export func history(c as Client, type as string, id as string) {
    def path as string init reference($type, $id) + "/_history";
    return firstPage($c, $c.baseUrl + "/" + $path, "history " + $path);
}

/**
 * Post a transaction or batch bundle.
 *
 * @param c {Client} the client
 * @param b {json.Value} the bundle
 * @param type {string} `transaction` or `batch`
 * @return {json.Value} the response bundle
 */
func postBundle(c as Client, b as json.Value, type as string) {
    if (resourceType($b) != "Bundle" or text($b, "/type") != $type) {
        fail($type + ": the bundle's type is not " + $type);
    }
    def v as json.Value init request($c, "POST", $c.baseUrl, {}, json.encode($b), $type);
    return expect($v, "Bundle", $type);
}

/**
 * Run a transaction: every entry succeeds or none does.
 *
 * @param c {Client} the client
 * @param b {json.Value} a bundle of type `transaction`, built with `bundle` and `entry`
 * @return {json.Value} the `transaction-response` bundle, an entry per entry with its `response.status` and `location`
 * @throws {Error} kind "fhir" when the bundle is not a transaction, the server rejects it (the whole transaction fails), or the request fails
 */
export func transaction(c as Client, b as json.Value) {
    return postBundle($c, $b, "transaction");
}

/**
 * Run a batch: each entry on its own; some may fail while others succeed.
 *
 * @param c {Client} the client
 * @param b {json.Value} a bundle of type `batch`
 * @return {json.Value} the `batch-response` bundle; read each entry's `response.status`
 * @throws {Error} kind "fhir" when the bundle is not a batch or the request fails
 */
export func batch(c as Client, b as json.Value) {
    return postBundle($c, $b, "batch");
}

/**
 * Invoke an operation with a Parameters resource, such as
 * `Patient/123/$everything` or `$validate`.
 *
 * @param c {Client} the client
 * @param path {string} `$name`, `Type/$name` or `Type/id/$name`
 * @param parameters {json.Value} a Parameters resource, or JSON `null` to send none
 * @return {json.Value} what the operation returns (a resource, often a Bundle or Parameters; JSON `null` when nothing)
 * @throws {Error} kind "fhir" when the path is malformed, the parameters are not a Parameters resource, or the request fails
 * @example
 *   def all as json.Value init fhir.operation($c, "Patient/123/$everything", json.decode("null"));
 */
export func operation(c as Client, path as string, parameters as json.Value) {
    if (not regex.matches(OPERATION, $path)) {
        fail("an operation path is $name, Type/$name or Type/id/$name, got " + shown($path));
    }
    def body as string init "";
    if (json.typeOf($parameters) != "null") {
        if (resourceType($parameters) != "Parameters") {
            fail("operation " + $path + ": the parameters are not a Parameters resource");
        }
        $body = json.encode($parameters);
    } else {
        $body = '{"resourceType":"Parameters"}';
    }
    return request($c, "POST", $c.baseUrl + "/" + $path, {}, $body, "operation " + $path);
}

/**
 * Any other request to the server.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH`, `DELETE` or `HEAD`
 * @param path {string} the path below the base, such as `Patient/123/_history/2`
 * @param query {list of string} parameters as `name=value`
 * @param body {json.Value} the body, JSON `null` for none
 * @return {json.Value} the response, JSON `null` when it has no body
 * @throws {Error} kind "fhir" when the method or path is malformed, the status is not 2xx, or the request fails
 */
export func call(
    c as Client,
    method as string,
    path as string,
    query as list of string,
    body as json.Value) {
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"], $method)) {
        fail("a method is GET, POST, PUT, PATCH, DELETE or HEAD, got " + shown($method));
    }
    if (not regex.matches(CALL_PATH, $path) or regex.matches('(^|/)\.\.?(/|$)', $path)) {
        fail("a path is segments of letters, digits and -._$, got " + shown($path));
    }
    def payload as string init "";
    if (json.typeOf($body) != "null") {
        $payload = json.encode($body);
    }
    return request(
        $c,
        $method,
        $c.baseUrl + "/" + $path + queryOf($query),
        {},
        $payload,
        $method + " " + $path);
}
