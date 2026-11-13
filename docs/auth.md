<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Authentication

## Bearer tokens

A server that takes a bearer token gets it with `withToken`; any other
header (an API key, a tenant) with `withHeader`:

```jennifer
def c as fhir.Client init fhir.withToken(fhir.client("https://fhir.example.org/r4"), $token);
```

## SMART on FHIR backend services

A service without a user (a nightly export, an interface engine) registers
a public key with the server and authorises with a JWT signed by the
private key: the client-credentials grant with a `private_key_jwt` client
assertion. `smartBackend` reads the token endpoint from the server's
`.well-known/smart-configuration`, signs the assertion (RS384 or ES384, as
SMART requires), asks for the scopes, and returns the client with the
token:

```jennifer
def key as bytes init fs.readBytes("service-key.pem");
def c as fhir.Client init fhir.smartBackend(
    fhir.client("https://fhir.example.org/r4"),
    "my-service",
    "system/Patient.rs system/Observation.rs",
    "ES384",
    $key,
    "key-1");
```

The token is short-lived, often five minutes: call `smartBackend` again
for a new one. The key id (`kid`) is required: SMART servers find the key by
it. The token endpoint must be https (plain http only to this machine, even
with `withPlainHttp`), and the token must be a bearer token. The token
request runs through the `oauth` module with its own deadline (60 s) and
cap (1 MiB) and the system's certificate checks: a client's `withTls`
does not reach it, so a token endpoint behind a private CA needs that CA in
the system store. Its refusals carry the OAuth error (`invalid_client`,
...) rather than an HTTP status.

A user-facing SMART app launch (authorization code with PKCE) is the
`oauth` module's `authorize` / `exchangeCode`; give the token it returns to
`withToken`.
