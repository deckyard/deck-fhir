<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/fhir

FHIR is the REST API of newer health systems: patients, encounters,
observations, medications and some 150 other resource types, as JSON over
HTTP. This deck is a client for FHIR R4 and R5 servers (HAPI FHIR, the
cloud health APIs, EHR vendors' endpoints): read, search with paging,
create, update and patch with version checks, delete, history,
transactions and batches, and operations.

- [Reading and searching](reading.md)
- [Writing](writing.md): create, update, patch, delete, transactions.
- [Resources](resources.md): working with resources as `json.Value`.
- [Authentication](auth.md): bearer tokens and SMART on FHIR.
- [Cheatsheet](cheatsheet.md): every export.

## Conventions

Snippets assume these imports:

```jennifer
use json;
import "@deckyard/fhir/" as fhir;
```

Resources are `json.Value`, read with `json.asString($r, "/name/0/family")`
and built with `json.set`: there is no struct per resource type. A request
the server refuses throws `fhir.HttpError`, kind `fhir.http`, with the HTTP
`status` and the `issues` of the server's OperationOutcome; a response over
`maxBytes` (or nested past the JSON decoder's caps) and a search or history
past `maxPages` / `maxBytes` are kind `"limit"`; no answer within the
timeout is `"timeout"`, a connection closed mid-answer `"closed"`; a server (or SMART
token endpoint) that cannot be reached, resets the connection or fails the
TLS handshake is kind `"net"`, the `net.NetError` that `http` threw, with
`op`, `reason`, `sent` and `replied` to read; any other failure is
`Error{kind: "fhir"}`:

```jennifer
try {
    def p as json.Value init fhir.read($c, "Patient", "123");
} catch (e) {
    if ($e.kind == "fhir.http" and $e.status == 404) {
        io.printf("no such patient\n");
    } else {
        throw $e;
    }
}
```

Every request has a deadline (one minute) and a response cap (8 MiB).
Plain `http` is refused except to this machine, since health data and
tokens would cross the network in clear. Links the server returns (next
pages, a created resource's Location) are followed only below its base
URL, so the token is never sent elsewhere. Resource types, ids (no `.` or
`..`), search parameter names and paths are checked before they go into a
URL, and text from the server is cleaned of control characters and capped
before it goes into an error message.

Out of scope: profile validation and FHIRPath, terminology services,
subscriptions. The deck needs the `net` capability and does not run on
`jennifer-tiny`.
