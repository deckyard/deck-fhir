# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# fhir - white-box tests for the auth topic. Spliced into fhir_test.j via
# include.

func testSmartBackendServices() {
    def f as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" +
            '{"token_endpoint":"BASE/token","grant_types_supported":["client_credentials"]}',
        "POST /fhir/token": "200\nContent-Type: application/json\n\n" +
            '{"access_token":"tok-1","token_type":"bearer","expires_in":300,"scope":"system/Patient.rs"}',
        "GET /fhir/Patient/p1": "200\n\n" + PATIENT
    });
    def key as crypto.Keypair init crypto.keypair("p384");
    def c as Client init smartBackend(
        fakeClient($f),
        "svc",
        "system/Patient.rs",
        "ES384",
        $key.private,
        "k1");
    testing.assertEqual($c.headers["Authorization"], "Bearer tok-1");
    read($c, "Patient", "p1");
    def seen as list of string init stopFake($f);
    def form as string init $seen[1];
    testing.assertContains($form, "grant_type=client_credentials");
    testing.assertContains(
        $form,
        "client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3Aclient-assertion-type%3Ajwt-bearer");
    testing.assertContains($form, "scope=system%2FPatient.rs");
    def m as regex.Match init regex.find('client_assertion=([A-Za-z0-9_-]+)\.', $form);
    def header as string init encoding.decode(
        "utf-8",
        encoding.fromText(
            "base64-url",
            $m.groups[0] + strings.replicate("=", (4 - len($m.groups[0]) % 4) % 4)));
    testing.assertContains($header, "\"alg\":\"ES384\"");
    testing.assertContains($header, "\"kid\":\"k1\"");
    testing.assertEqual(
        $seen[2],
        "GET /fhir/Patient/p1|Accept=application/fhir+json|Authorization=Bearer tok-1|");
}

func testSmartBackendRefusals() {
    def c as Client init client("https://fhir.example.org/r4");
    def key as bytes init crypto.keypair("p256").private;
    try {
        smartBackend($c, "svc", "system/*.rs", "ES256", $key, "k");
        missed("ES256");
    } catch (e) {
        testing.assertContains($e.message, "sign with RS384 or ES384");
    }
    try {
        smartBackend($c, "", "system/*.rs", "ES384", $key, "k");
        missed("no client id");
    } catch (e) {
        testing.assertContains($e.message, "need a client id, a scope and the key id");
    }
    try {
        smartBackend($c, "svc", "system/*.rs", "ES384", $key, "");
        missed("no kid");
    } catch (e) {
        testing.assertContains($e.message, "the key id (kid)");
    }
    def f as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" +
            '{"token_endpoint":"http://auth.example.org/token"}',
        "GET /fhir/x/.well-known/smart-configuration": "200\n\n" + '{"issuer":"x"}'
    });
    try {
        smartBackend(fakeClient($f), "svc", "system/*.rs", "ES384", $key, "k");
        missed("a plain http token endpoint");
    } catch (e) {
        testing.assertContains($e.message, "is not https");
    }
    try {
        smartConfiguration(client($f.base + "/x"));
        missed("no token endpoint");
    } catch (e) {
        testing.assertContains($e.message, "it has no token_endpoint");
    }
    stopFake($f);
}

func testSmartTokenClaimsAndRefusals() {
    def f as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" +
            '{"token_endpoint":"BASE/token?realm=a"}',
        "POST /fhir/token?realm=a": "200\nContent-Type: application/json\n\n" +
            '{"access_token":"t","token_type":"mac"}'
    });
    def key as bytes init crypto.keypair("p384").private;
    try {
        smartBackend(fakeClient($f), "svc", "system/*.rs", "ES384", $key, "k1");
        missed("a mac token");
    } catch (e) {
        testing.assertContains($e.message, "not bearer");
    }
    def seen as list of string init stopFake($f);
    def m as regex.Match init regex.find(
        'client_assertion=[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.',
        $seen[1]);
    def part as string init $m.groups[0];
    def claims as json.Value init json.decode(encoding.decode(
        "utf-8",
        encoding.fromText("base64-url", $part + strings.replicate("=", (4 - len($part) % 4) % 4))));
    testing.assertEqual(json.asString($claims, "/iss"), "svc");
    testing.assertEqual(json.asString($claims, "/sub"), "svc");
    testing.assertTrue(strings.endsWith(json.asString($claims, "/aud"), "/fhir/token?realm=a"));
    testing.assertTrue(json.asInt($claims, "/exp") - json.asInt($claims, "/iat") <= 300);
    testing.assertTrue(len(json.asString($claims, "/jti")) >= 16);
    def g as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" + '{"token_endpoint":"BASE/token"}',
        "POST /fhir/token": "400\nContent-Type: application/json\n\n" +
            '{"error":"invalid_client","error_description":"bad signature"}'
    });
    try {
        smartBackend(fakeClient($g), "svc", "system/*.rs", "ES384", $key, "k1");
        missed("a refused client");
    } catch (e) {
        testing.assertEqual($e.kind, "fhir");
        testing.assertContains($e.message, "invalid_client");
    }
    stopFake($g);
    # a token endpoint nobody listens on: net's NetError, through oauth
    def h as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" +
            '{"token_endpoint":"http://' + closedAddress() + '/token"}'
    });
    try {
        smartBackend(fakeClient($h), "svc", "system/*.rs", "ES384", $key, "k1");
        missed("an unreachable token endpoint");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        def ne as net.NetError init $e;
        testing.assertEqual($ne.reason, "refused");
    }
    stopFake($h);
    # a token answer over oauth's 1 MiB cap: oauth's "limit", passed on
    def big as Fake init startFake({
        "GET /fhir/.well-known/smart-configuration": "200\n\n" + '{"token_endpoint":"BASE/token"}',
        "POST /fhir/token": "200\nContent-Type: application/json\n\n" +
            '{"access_token":"' + strings.replicate("x", 1100000) + '"}'
    });
    try {
        smartBackend(fakeClient($big), "svc", "system/*.rs", "ES384", $key, "k1");
        missed("an oversized token answer");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    stopFake($big);
}
