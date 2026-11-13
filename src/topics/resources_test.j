# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - white-box tests for the resources topic. Spliced into fhir_test.j
# via include.

# a patient with two identifiers and a version
def const PATIENT as string init '{"resourceType":"Patient","id":"p1","meta":{"versionId":"3"},"identifier":[{"system":"urn:mrn","value":"M-1"},{"system":"urn:ssn","value":"S-9"}],"name":[{"family":"Doe","given":["Jane"]}]}';

func testResourceBasics() {
    def p as json.Value init json.decode(PATIENT);
    testing.assertEqual(resourceType($p), "Patient");
    testing.assertEqual(idOf($p), "p1");
    testing.assertEqual(versionOf($p), "3");
    testing.assertEqual(referenceOf($p), "Patient/p1");
    testing.assertEqual(identifierValue($p, "urn:ssn"), "S-9");
    testing.assertEqual(identifierValue($p, "urn:none"), "");
    testing.assertEqual(
        json.encode(identifier("urn:mrn", "M-2")),
        '{"system":"urn:mrn","value":"M-2"}');
    testing.assertEqual(versionOf(json.decode('{"resourceType":"Patient"}')), "");
    for (def bad in ['{"id":"x"}', '[]', '{"resourceType":"patient"}', '{"resourceType":7}']) {
        try {
            resourceType(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    for (def bad in [
        ["patient", "1"],
        ["Patient", "a/b"],
        ["Patient", ""],
        ["Patient", strings.repeat("x", 65)]
    ]) {
        try {
            reference($bad[0], $bad[1]);
            missed($bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    try {
        idOf(json.decode('{"resourceType":"Patient","id":5}'));
        missed("a number id");
    } catch (e) {
        testing.assertContains($e.message, "is a int, not a string");
    }
}

func testCodings() {
    def c as json.Value init concept("http://loinc.org", "2345-7", "Glucose");
    testing.assertEqual(
        json.encode($c),
        '{"coding":[{"system":"http://loinc.org","code":"2345-7","display":"Glucose"}]}');
    testing.assertTrue(hasCoding($c, "http://loinc.org", "2345-7"));
    testing.assertFalse(hasCoding($c, "http://loinc.org", "1234-5"));
    testing.assertFalse(hasCoding(json.map(), "a", "b"));
    testing.assertEqual(json.encode(coding("s", "c", "")), '{"system":"s","code":"c"}');
}

func testBundles() {
    def b as json.Value init bundle("transaction");
    $b = entry(
        $b,
        "POST",
        "Patient",
        json.decode('{"resourceType":"Patient"}'),
        "urn:uuid:9b1f0a54-62c7-4e7c-9d41-6cf0d4f0a001");
    $b = entry($b, "DELETE", "Patient/9", json.decode("null"), "");
    testing.assertEqual(
        json.encode($b),
        '{"resourceType":"Bundle","type":"transaction","entry":[{"fullUrl":"urn:uuid:9b1f0a54-62c7-4e7c-9d41-6cf0d4f0a001","resource":{"resourceType":"Patient"},"request":{"method":"POST","url":"Patient"}},{"request":{"method":"DELETE","url":"Patient/9"}}]}');
    testing.assertEqual(len(resourcesOf($b)), 1);
    for (def bad in [
        ["PUSH", "Patient"],
        ["GET", "/Patient"],
        ["GET", "https://x/Patient"],
        ["GET", ""]
    ]) {
        try {
            entry($b, $bad[0], $bad[1], json.decode("null"), "");
            missed($bad[0] + " " + $bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    try {
        bundle("searchset");
        missed("searchset");
    } catch (e) {
        testing.assertContains($e.message, "a bundle type is one of");
    }
    try {
        resourcesOf(json.decode(PATIENT));
        missed("not a bundle");
    } catch (e) {
        testing.assertContains($e.message, "not a Bundle");
    }
}

func testIssues() {
    def o as json.Value init json.decode('{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"invalid","diagnostics":"bad date","expression":["Patient.birthDate"]},{"severity":"warning","code":"informational","details":{"text":"note"}}]}');
    def found as list of Issue init issues($o);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].diagnostics, "bad date");
    testing.assertEqual($found[0].expression, ["Patient.birthDate"]);
    testing.assertEqual($found[1].text, "note");
    testing.assertEqual($found[1].severity, "warning");
}

func testEntriesAreChecked() {
    testing.assertEqual(json.encode(bundle("batch")), '{"resourceType":"Bundle","type":"batch"}');
    def b as json.Value init bundle("transaction");
    def pat as json.Value init json.decode('{"resourceType":"Patient","id":"1"}');
    def none as json.Value init json.decode("null");
    testing.assertEqual(json.length(entry($b, "PUT", "Patient/1", $pat, ""), "/entry"), 1);
    testing.assertEqual(
        json.length(entry($b, "PUT", "Patient?identifier=x", $pat, "urn:oid:1.2.3"), "/entry"),
        1);
    def cases as list of list of json.Value init [
        [json.decode('"POST"'), json.decode('"Patient"'), $none],
        [json.decode('"DELETE"'), json.decode('"Patient/1"'), $pat],
        [json.decode('"PUT"'), json.decode('"Patient/2"'), $pat],
        [json.decode('"PUT"'), json.decode('"Observation/1"'), $pat],
        [json.decode('"GET"'), json.decode('"Patient/1 x"'), $none]
    ];
    for (def k in $cases) {
        try {
            entry($b, json.asString($k[0]), json.asString($k[1]), $k[2], "");
            missed(json.asString($k[1]));
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    for (def bad in ["urn:uuid:1", "not a url", "urn:oid:x"]) {
        try {
            entry($b, "GET", "Patient/1", $none, $bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a fullUrl is");
        }
    }
    for (def wrong in [bundle("collection"), json.decode(PATIENT), json.decode("[]")]) {
        try {
            entry($wrong, "GET", "Patient/1", $none, "");
            missed("not a transaction or batch");
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
    for (def pair in [["", "x"], ["s", ""]]) {
        try {
            identifier($pair[0], $pair[1]);
            missed("an empty identifier");
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
        try {
            coding($pair[0], $pair[1], "");
            missed("an empty coding");
        } catch (e) {
            testing.assertEqual($e.kind, "fhir");
        }
    }
}

func testIssuesAreStrict() {
    def old as json.Value init json.decode('{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"invalid","location":["/f:Patient/f:birthDate"]}]}');
    testing.assertEqual(issues($old)[0].expression, ["/f:Patient/f:birthDate"]);
    for (def bad in [
        '{"resourceType":"OperationOutcome","issue":["boom"]}',
        '{"resourceType":"OperationOutcome","issue":[{"code":"invalid"}]}'
    ]) {
        try {
            issues(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "has no severity or code");
        }
    }
}
