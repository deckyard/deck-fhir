# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - white-box tests for the rest topic. Spliced into fhir_test.j via
# include.

# an OperationOutcome for a 404
def const GONE as string init "404\n\n" +
    '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-found","diagnostics":"Resource Patient/x is not known"}]}';

func testCapabilitiesReadAndVread() {
    def f as Fake init startFake({
        "GET /fhir/metadata": "200\n\n" +
            '{"resourceType":"CapabilityStatement","fhirVersion":"4.0.1"}',
        "GET /fhir/Patient/p1": "200\n\n" + PATIENT,
        "GET /fhir/Patient/p1/_history/2": "200\n\n" +
            '{"resourceType":"Patient","id":"p1","meta":{"versionId":"2"}}',
        "GET /fhir/Patient/x": GONE,
        "GET /fhir/Patient/odd": "200\n\n" + '{"resourceType":"Observation","id":"odd"}',
        "GET /fhir/Patient/html": "200\n\n<html>login</html>"
    });
    def c as Client init withToken(fakeClient($f), "t0k");
    testing.assertEqual(json.asString(capabilities($c), "/fhirVersion"), "4.0.1");
    testing.assertEqual(identifierValue(read($c, "Patient", "p1"), "urn:mrn"), "M-1");
    testing.assertEqual(versionOf(vread($c, "Patient", "p1", "2")), "2");
    try {
        read($c, "Patient", "x");
        missed("a 404");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "fhir: read Patient/x: Resource Patient/x is not known (HTTP 404)");
        testing.assertEqual($e.kind, "fhir.http");
        testing.assertEqual($e.status, 404);
        testing.assertEqual(len($e.issues), 1);
        testing.assertEqual($e.issues[0].diagnostics, "Resource Patient/x is not known");
    }
    try {
        read($c, "Patient", "odd");
        missed("another type");
    } catch (e) {
        testing.assertContains($e.message, "the server did not return a resource of type Patient");
    }
    try {
        read($c, "Patient", "html");
        missed("not JSON");
    } catch (e) {
        testing.assertContains($e.message, "the response is not JSON");
    }
    try {
        read($c, "Patient", "../metadata");
        missed("a path in an id");
    } catch (e) {
        testing.assertContains($e.message, "an id is 1 to 64");
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        $seen[1],
        "GET /fhir/Patient/p1|Accept=application/fhir+json|Authorization=Bearer t0k|");
}

func testSearchFollowsPages() {
    def f as Fake init startFake({
        "GET /fhir/Patient?family=Doe%20Jr": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"BASE?_getpages=a&_page=2"}],"entry":[{"resource":{"resourceType":"Patient","id":"1"},"search":{"mode":"match"}},{"resource":{"resourceType":"Organization","id":"o"},"search":{"mode":"include"}}]}',
        "GET /fhir?_getpages=a&_page=2": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset","entry":[{"resource":{"resourceType":"Patient","id":"2"}}]}',
        "GET /fhir/Observation?code=x": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"https://evil.example/steal"}],"entry":[]}',
        "GET /fhir/Location": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"BASE/Location"}],"entry":[{"resource":{"resourceType":"Location","id":"l","description":"' +
            strings.repeat("x", 30000) + '"}}]}',
        "GET /fhir/Encounter": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"BASE/Encounter"}],"entry":[{"resource":{"resourceType":"Encounter","id":"e"}}]}'
    });
    def c as Client init fakeClient($f);
    def found as list of json.Value init search($c, "Patient", ["family=Doe Jr"]);
    testing.assertEqual(len($found), 2);
    testing.assertEqual(idOf($found[1]), "2");
    def first as json.Value init searchBundle($c, "Patient", ["family=Doe Jr"]);
    testing.assertEqual(len(resourcesOf($first)), 2);
    testing.assertEqual(len(nextBundle($c, $first)), 1);
    try {
        search($c, "Observation", ["code=x"]);
        missed("a next link elsewhere");
    } catch (e) {
        testing.assertContains($e.message, "leaves the server");
    }
    try {
        search(withMaxPages(withMaxBytes($c, 65536), 1000), "Location", []);
        missed("pages over the byte cap");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual(
            $e.message,
            "fhir: search Location: the pages hold more than 65536 bytes; narrow it or raise withMaxBytes");
    }
    try {
        search(withMaxPages($c, 3), "Encounter", []);
        missed("endless pages");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertContains($e.message, "search Encounter: more than 3 pages");
    }
    stopFake($f);
}

func testCreateUpdatePatchDelete() {
    def f as Fake init startFake({
        "POST /fhir/Patient": "201\nLocation: BASE/Patient/new/_history/1\n\n" +
            '{"resourceType":"Patient","id":"new","meta":{"versionId":"1"}}',
        "POST /fhir/Observation": "201\nLocation: BASE/Observation/o9/_history/1\n\n",
        "GET /fhir/Observation/o9/_history/1": "200\n\n" +
            '{"resourceType":"Observation","id":"o9"}',
        "PUT /fhir/Patient/p1": "200\n\n" +
            '{"resourceType":"Patient","id":"p1","meta":{"versionId":"4"}}',
        "PUT /fhir/Patient/old": "412\n\n" +
            '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"conflict","diagnostics":"version 3 is not current"}]}',
        "PATCH /fhir/Patient/p1": "200\n\n" + '{"resourceType":"Patient","id":"p1","active":false}',
        "DELETE /fhir/Patient/p1": "204\n\n"
    });
    def c as Client init fakeClient($f);
    def p as json.Value init create(
        $c,
        json.decode('{"resourceType":"Patient","name":[{"family":"Roe"}]}'));
    testing.assertEqual(referenceOf($p), "Patient/new");
    testing.assertEqual(idOf(create($c, json.decode('{"resourceType":"Observation"}'))), "o9");
    try {
        create($c, json.decode(PATIENT));
        missed("create with an id");
    } catch (e) {
        testing.assertContains($e.message, "the server assigns the id");
    }
    testing.assertEqual(versionOf(update($c, json.decode(PATIENT))), "4");
    try {
        update($c, json.decode('{"resourceType":"Patient","id":"old","meta":{"versionId":"3"}}'));
        missed("a stale version");
    } catch (e) {
        testing.assertEqual($e.kind, "fhir.http");
        testing.assertEqual($e.status, 412);
        testing.assertContains($e.message, "version 3 is not current");
    }
    try {
        update($c, json.decode('{"resourceType":"Patient"}'));
        missed("no id");
    } catch (e) {
        testing.assertEqual($e.kind, "fhir");
    }
    def ops as json.Value init json.decode('[{"op":"replace","path":"/active","value":false}]');
    testing.assertFalse(json.asBool(patch($c, "Patient", "p1", $ops, "4"), "/active"));
    try {
        patch($c, "Patient", "p1", json.map(), "");
        missed("a patch that is not a list");
    } catch (e) {
        testing.assertContains($e.message, "a JSON Patch is a list");
    }
    delete($c, "Patient", "p1");
    def seen as list of string init stopFake($f);
    testing.assertContains(
        $seen[0],
        "POST /fhir/Patient|Accept=application/fhir+json|Content-Type=application/fhir+json; charset=utf-8|Prefer=return=representation|");
    testing.assertContains($seen[3], "PUT /fhir/Patient/p1|");
    testing.assertContains($seen[3], "If-Match=W/\"3\"");
    testing.assertContains($seen[5], "Content-Type=application/json-patch+json");
    testing.assertContains($seen[5], "If-Match=W/\"4\"");
    testing.assertEqual($seen[6], "DELETE /fhir/Patient/p1|Accept=application/fhir+json|");
}

func testHistoryTransactionsOperationsAndCall() {
    def f as Fake init startFake({
        "GET /fhir/Patient/p1/_history": "200\n\n" +
            '{"resourceType":"Bundle","type":"history","entry":[{"resource":{"resourceType":"Patient","id":"p1","meta":{"versionId":"2"}}},{"request":{"method":"DELETE","url":"Patient/p1"}},{"resource":{"resourceType":"Patient","id":"p1","meta":{"versionId":"1"}}}]}',
        "POST /fhir": "200\n\n" +
            '{"resourceType":"Bundle","type":"transaction-response","entry":[]}',
        "POST /fhir/Patient/p1/$everything": "200\n\n" +
            '{"resourceType":"Bundle","type":"searchset"}',
        "GET /fhir/Patient/p1/_history/2": "200\n\n" + '{"resourceType":"Patient"}',
        "DELETE /fhir/Patient/p2": "200\n\n"
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(len(history($c, "Patient", "p1")), 2);
    testing.assertEqual(
        json.asString(
            transaction(
                $c,
                entry(bundle("transaction"), "GET", "Patient/p1", json.decode("null"), "")),
            "/type"),
        "transaction-response");
    testing.assertEqual(json.asString(batch($c, bundle("batch")), "/type"), "transaction-response");
    try {
        transaction($c, bundle("batch"));
        missed("a batch as a transaction");
    } catch (e) {
        testing.assertContains($e.message, "the bundle's type is not transaction");
    }
    testing.assertEqual(
        resourceType(operation($c, "Patient/p1/$everything", json.decode("null"))),
        "Bundle");
    for (def bad in ["everything", "Patient/p1/$", "../$x", "$X"]) {
        try {
            operation($c, $bad, json.decode("null"));
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "an operation path is");
        }
    }
    try {
        operation($c, "$validate", json.decode('{"resourceType":"Patient"}'));
        missed("not Parameters");
    } catch (e) {
        testing.assertContains($e.message, "not a Parameters resource");
    }
    testing.assertEqual(
        resourceType(call($c, "GET", "Patient/p1/_history/2", [], json.decode("null"))),
        "Patient");
    testing.assertEqual(
        json.typeOf(call($c, "DELETE", "Patient/p2", [], json.decode("null"))),
        "null");
    for (def bad in [["GET", "../x"], ["GET", "a//b"], ["TRACE", "Patient"], ["GET", "a b"]]) {
        try {
            call($c, $bad[0], $bad[1], [], json.decode("null"));
            missed($bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    def seen as list of string init stopFake($f);
    testing.assertContains($seen[3], "POST /fhir/Patient/p1/$everything|");
    testing.assertContains($seen[3], '{"resourceType":"Parameters"}');
}

func testDeadlinesAndCaps() {
    def f as Fake init startFake({
        "GET /fhir/Patient/slow": "SLEEP\n\n",
        "GET /fhir/Patient/big": "200\n\n" + '{"resourceType":"Patient","text":"' +
            strings.repeat("x", 70000) + '"}'
    });
    def c as Client init withTimeout(fakeClient($f), 1000);
    try {
        read(withMaxBytes($c, 65536), "Patient", "big");
        missed("a big response");
    } catch (e) {
        testing.assertContains($e.message, "the response is over 65536 bytes");
    }
    def started as time.Time init time.now();
    try {
        read($c, "Patient", "slow");
        missed("a slow server");
    } catch (e) {
        testing.assertEqual($e.message, "fhir: read Patient/slow: no answer within 1000 ms");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    stopFake($f);
    try {
        read(client("http://127.0.0.1:1/fhir"), "Patient", "x");
        missed("nobody listening");
    } catch (e) {
        testing.assertContains($e.message, "cannot reach");
    }
}

func testServerTextCannotForgeOrFlood() {
    def r as http.Response init http.Response{
        status: 404,
        statusText: "Not Found (HTTP 200) " + convert.fromCodepoint(27) + "[2J",
        headers: {},
        body: "<html>"
    };
    try {
        failHttp("read Patient/x", $r);
        missed("an HttpError");
    } catch (e) {
        testing.assertFalse(strings.contains($e.message, convert.fromCodepoint(27)));
        testing.assertEqual($e.kind, "fhir.http");
        testing.assertEqual($e.status, 404);
        testing.assertEqual(len($e.issues), 0);
    }
    def long as http.Response init http.Response{
        status: 400,
        statusText: "Bad Request",
        headers: {},
        body: '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"invalid","diagnostics":"' +
            strings.repeat("x", 5000) + '"}]}'
    };
    testing.assertEqual(len(outcomeIssues($long)), 1);
    testing.assertTrue(len(explain(outcomeIssues($long), $long)) <= 1003);
    def broken as http.Response init http.Response{
        status: 400,
        statusText: "Bad Request",
        headers: {},
        body: '{"resourceType":"OperationOutcome","issue":["boom"]}'
    };
    testing.assertEqual(len(outcomeIssues($broken)), 0);
    testing.assertEqual(explain(outcomeIssues($broken), $broken), "Bad Request");
}

func testDotIdsAndOddLocationsAreRefused() {
    def f as Fake init startFake({
        "POST /fhir/Patient": "201\nLocation: /fhir/Patient/n1\n\n",
        "POST /fhir/Observation": "201\nLocation: https://elsewhere.example/fhir/Observation/o1\n\n",
        "POST /fhir/Device": "201\nLocation: Device/d1/_history/1\n\n" +
            '{"resourceType":"OperationOutcome","issue":[{"severity":"information","code":"informational","diagnostics":"created"}]}',
        "GET /fhir/Device/d1/_history/1": "200\n\n" + '{"resourceType":"Device","id":"d1"}'
    });
    def c as Client init fakeClient($f);
    for (def id in [".", ".."]) {
        try {
            read($c, "Patient", $id);
            missed($id);
        } catch (e) {
            testing.assertContains($e.message, "not only dots");
        }
    }
    try {
        operation($c, "Patient/../$everything", json.decode("null"));
        missed("a dot id in an operation");
    } catch (e) {
        testing.assertContains($e.message, "an operation path is");
    }
    for (def type in ["Patient", "Observation"]) {
        try {
            create($c, json.decode('{"resourceType":"' + $type + '"}'));
            missed($type);
        } catch (e) {
            testing.assertContains($e.message, "is not on this server");
        }
    }
    testing.assertEqual(idOf(create($c, json.decode('{"resourceType":"Device"}'))), "d1");
    def headers as map of string to string init withHeader(
        withHeader($c, "accept", "a"),
        "Accept",
        "b").headers;
    testing.assertEqual(maps.keys($headers), ["Accept"]);
    stopFake($f);
}

func testThePageCapCountsBytes() {
    def page as string init '{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"BASE/Media"}],"entry":[{"resource":{"resourceType":"Media","id":"m","text":"' +
        strings.repeat("é", 20000) + '"}}]}';
    def f as Fake init startFake({"GET /fhir/Media": "200\n\n" + $page});
    try {
        search(withMaxBytes(fakeClient($f), 65536), "Media", []);
        missed("multibyte pages over the cap");
    } catch (e) {
        testing.assertContains($e.message, "the pages hold more than 65536 bytes");
    }
    stopFake($f);
}
