<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

An HL7 FHIR R4 / R5 REST client over the bundled `http`, `json` and `oauth`
modules: `capabilities`, `read` / `vread`, `search` following the bundle's
next links (or `searchBundle` / `nextBundle` to page by hand), `create`,
`update`, `patch` (JSON Patch), `delete`, `history`, `transaction` / `batch`,
`operation` for `$name` operations, and `call` for the rest. Helpers read and
build references, identifiers, codings, bundles and `OperationOutcome` issues.
Authentication is a bearer token or SMART on FHIR backend services.

Out of scope:

- Profile validation and FHIRPath: large, version-specific, and the server's
  job.
- Terminology services and subscriptions.
- A SMART user launch or device-code flow. The bundled `oauth` module's flows
  plus `withToken` cover user sign-in.
- XML and RDF encodings; the client speaks FHIR JSON.

## Decisions

- **Resources stay `json.Value`.** FHIR has hundreds of resource types, each
  extensible, in two major versions. A struct per type would be large, lag
  the specification and lose extensions; the helpers read with JSON pointers
  instead (a missing value is `""`, a value of the wrong type is an error).
- **One client value, configured with `with*`.** `client(baseUrl)` gives the
  defaults; `withToken`, `withHeader`, `withTls`, `withPlainHttp`,
  `withTimeout`, `withMaxBytes` and `withMaxPages` return an adjusted copy.
- **A hard deadline per request.** Each request runs in a task under
  `task.waitTimeout` with the client's timeout; on expiry the task is
  cancelled and discarded. Redirects are not followed.
- **Optimistic locking by default.** `update` sends
  `If-Match: W/"<versionId>"` when the resource carries `meta.versionId`.
  `create` refuses a resource that already has an id and asks for
  `Prefer: return=representation`, falling back to reading the `Location`
  when the server answers without the resource.
- **Paging is bounded.** `search` and `history` follow next links up to
  `maxPages` pages and `maxBytes` for all pages together, counted in bytes.
  Decoded JSON costs about 20 times its size in memory (a 4.8 MB bundle took
  about 100 MB), so the byte cap matters more than the page count.
- **Bundles are checked when built.** `entry` checks the bundle type, the
  presence of a resource per method, the type and id of a PUT and the form of
  `fullUrl`; `bundle` emits no empty `entry` list, which FHIR JSON forbids.
  `identifier` and `coding` refuse empty strings.
- **Issues are data.** `issues` returns the `OperationOutcome`'s issues
  uncleaned, refusing an issue without severity or code; the error message,
  which is for people, is cleaned.
- **SMART backend services** find the token endpoint in
  `.well-known/smart-configuration` and sign an RS384 or ES384 client
  assertion through `oauth`. A key id is required and the token type must be
  bearer. There is no refresh: call `smartBackend` again when the token
  expires.

## Errors

- A response that is not 2xx throws `HttpError{kind, message, status,
  issues}` with kind `"fhir.http"`, which no other error of the deck uses, so
  `status` and `issues` are safe to read once the kind matches. The message
  is the request, the `OperationOutcome`'s diagnostics and `(HTTP nnn)`.
  The status used to be parsed back out of the message; the field replaced
  that.
- A response over `maxBytes`, one nested past the JSON decoder's caps, and
  paging past `maxPages` or `maxBytes` are kind `"limit"`. A request with no
  answer within the timeout is `"timeout"`, a connection closed mid-answer
  `"closed"`.
- A network failure (refused, reset, unreachable, DNS, TLS), from the FHIR
  server or the SMART token endpoint, is the `net.NetError` (kind `"net"`)
  that `http` threw, passed on with its `op`, `reason`, `sent` and
  `replied`. The deck does not retry it.
- Every other failure is `Error{kind: "fhir"}`: local validation and a
  response that is not FHIR JSON. The SMART token request passes the shared
  kinds of `oauth` on as well.
- A cancelled task passes on as `"cancelled"`.

## Security and limits

- **The token never leaves the server.** Next links and `Location` headers
  are followed only when they start with the base URL followed by `/` or `?`,
  or are relative `Type/id[/_history/v]`. The SMART token endpoint passes the
  same URL checks.
- **Plain http only to loopback** unless `withPlainHttp`.
- **Everything placed in a URL is checked first**: resource types, ids,
  version ids, parameter names and paths. Ids made only of dots are refused,
  since `..` would form a dot-segment path.
- Defaults: `DEFAULT_TIMEOUT_MS` (60 s) per request, `DEFAULT_MAX_BYTES`
  (8 MiB) per response and for all pages together, `DEFAULT_MAX_PAGES`
  (100). The SMART token request uses `oauth`'s own bounds (1 MiB, 60 s).
- Server text in messages is cleaned of control and bidirectional
  characters and capped (1000 characters, the reason phrase 100).

## Testing and validation

- `jennifer test src/fhir_test.j` runs offline against a fake FHIR server
  over `httpd` that answers canned replies per `METHOD path?query` and
  records each request's headers and body.
- Live: every interaction against HAPI FHIR 4.0.1 in a local container. HAPI
  answers a stale `If-Match` with 409, not 412, and pages `$everything`.
- Not covered: an R5 server live, and SMART against a real authorisation
  server (the assertion and token exchange are tested against the fake).

## Known limitations and open questions

- The SMART token request does not take the client's TLS options, so a
  private CA works for the FHIR server but not yet for its token endpoint.
- The cancel and limit checks keep a message match as a fallback for
  interpreters older than those kinds; it goes at the next floor raise.

## Dependencies on the interpreter

Floor `>=0.27.0`, capability `net`, for the UTF-8 codec of `encoding.decode`
and `strings.replicate`. It needs `oauth.clientAssertion` and
`clientCredentialsJwt` from the bundled `oauth` module. From `jennifer`'s
milestones: M28.50 (lint accepts error-shaped structs, found by this deck's
message parsing), M28.47 (TLS options for `oauth`, not yet used here),
M28.57 (the error conventions) and M28.65 (transport failures as
`net.NetError`, passed on).
