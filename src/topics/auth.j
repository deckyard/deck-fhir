# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - auth: SMART on FHIR. The server's smart-configuration, and the
# backend services flow (client credentials with a signed JWT client
# assertion) through the `oauth` module. Spliced into fhir.j via include.

# the signing algorithms SMART backend services require servers to accept
def const SMART_ALGS as list of string init ["RS384", "ES384"];

/**
 * The server's SMART configuration, from `.well-known/smart-configuration`:
 * its token endpoint, supported scopes and capabilities.
 *
 * @param c {Client} the client
 * @return {json.Value} the configuration
 * @throws {Error} kind "fhir" when the server does not publish one or the request fails
 */
export func smartConfiguration(c as Client) {
    def v as json.Value init request(
        $c,
        "GET",
        $c.baseUrl + "/.well-known/smart-configuration",
        {"Accept": "application/json"},
        "",
        "smart-configuration");
    if (json.typeOf($v, "/token_endpoint") != "string") {
        fail("smart-configuration: it has no token_endpoint");
    }
    return $v;
}

/**
 * The client authorised as a SMART backend service: it asks the server's
 * token endpoint for an access token with a JWT client assertion signed by
 * its private key (client credentials, `private_key_jwt`), and sends that
 * token from then on. The token expires (often after five minutes); call
 * again for a new one.
 *
 * @param c {Client} the client, without a token
 * @param clientId {string} the client id registered with the server
 * @param scope {string} the scopes, such as `system/Patient.rs system/Observation.rs`
 * @param alg {string} `RS384` or `ES384`
 * @param key {bytes} the PEM private key matching the registered public key
 * @param kid {string} the key id of the registered JWK, which SMART requires in the assertion
 * @return {Client} the client sending the token
 * @throws {Error} kind "fhir" when the algorithm is not RS384 or ES384, a client id, scope or kid is empty, the server has no SMART configuration, its token endpoint is not https (plain http only to this machine), the token request fails, or the token is not a bearer token. The token request runs through the `oauth` module: its own deadline (60 s) and cap (1 MiB), and the system's certificate checks, not the client's `withTls`.
 * @example
 *   $c = fhir.smartBackend($c, "my-service", "system/Patient.rs", "ES384", fs.readBytes("key.pem"), "key-1");
 */
export func smartBackend(
    c as Client,
    clientId as string,
    scope as string,
    alg as string,
    key as bytes,
    kid as string) {
    if (not lists.contains(SMART_ALGS, $alg)) {
        fail("SMART backend services sign with RS384 or ES384, got " + shown($alg));
    }
    if ($clientId == "" or $scope == "" or $kid == "") {
        fail("SMART backend services need a client id, a scope and the key id (kid) of the registered key");
    }
    def tokenUrl as string init json.asString(smartConfiguration($c), "/token_endpoint");
    def m as regex.Match init regex.find(
        '^(https?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[^#\s]*)?$',
        $tokenUrl);
    if ($m.start < 0 or
        ($m.groups[0] == "http" and
        not lists.contains(LOOPBACK, strings.lower($m.groups[1])))) {
        fail("the token endpoint " + shown($tokenUrl) +
            " is not https (plain http only to this machine, even with withPlainHttp)");
    }
    def config as oauth.Config init oauth.Config{
        tokenUrl: $tokenUrl,
        deviceUrl: "",
        authorizeUrl: "",
        clientId: $clientId,
        clientSecret: "",
        scope: $scope
    };
    def token as oauth.Token;
    try {
        def assertion as string init oauth.clientAssertion($alg, $clientId, $tokenUrl, $key, $kid);
        $token = oauth.clientCredentialsJwt($config, $assertion);
    } catch (e) {
        # A cancel is kind "cancelled" (jennifer after 0.25); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            throw $e;
        }
        fail("SMART backend token: " + cleaned($e.message, 1000));
    }
    if (strings.lower($token.tokenType) != "bearer") {
        fail("SMART backend token: the token type is " + shown($token.tokenType) + ", not bearer");
    }
    $c = withToken($c, $token.accessToken);
    return $c;
}
