<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# fhir cheatsheet

Every export of `@deckyard/fhir`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/fhir/" as fhir;
```

A request the FHIR server refused throws `HttpError` (kind `fhir.http`),
with `status` and the OperationOutcome's `issues` as fields; every other
failure is `Error{kind: "fhir"}` (a refused SMART token request carries the
OAuth error). A `c` argument is a
`Client`; resources, bundles and patches are `json.Value`; a `query` is a
`list of string` of `name=value` search parameters.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_TIMEOUT_MS` | `60000` | how long one request may take |
| `DEFAULT_MAX_BYTES` | `8388608` | the largest response read |
| `DEFAULT_MAX_PAGES` | `100` | the most pages `search` and `history` follow |

## The client

| Function | Returns | Does |
|---|---|---|
| `fhir.client(baseUrl)` | `Client` | a client; plain http only to this machine |
| `fhir.withToken(c, token)` | `Client` | send `Authorization: Bearer <token>` |
| `fhir.withHeader(c, name, value)` | `Client` | send another header |
| `fhir.withTls(c, tls)` | `Client` | certificate options (`caCert`, `skipVerify`) |
| `fhir.withPlainHttp(c)` | `Client` | allow plain http to another machine |
| `fhir.withTimeout(c, ms)` | `Client` | the deadline of one request, 1000 to 86400000 ms |
| `fhir.withMaxBytes(c, most)` | `Client` | the largest response, 65536 to 268435456 bytes |
| `fhir.withMaxPages(c, pages)` | `Client` | the page cap of `search` and `history` |
| `fhir.smartConfiguration(c)` | `json.Value` | the server's `.well-known/smart-configuration` |
| `fhir.smartBackend(c, clientId, scope, alg, key, kid)` | `Client` | authorise as a SMART backend service (RS384 / ES384 client assertion, `kid` required) |

## Interactions

| Function | Returns | Does |
|---|---|---|
| `fhir.capabilities(c)` | `json.Value` | the CapabilityStatement |
| `fhir.read(c, type, id)` | `json.Value` | a resource |
| `fhir.vread(c, type, id, version)` | `json.Value` | one version of a resource |
| `fhir.search(c, type, query)` | `list of json.Value` | the matching resources, every page, within `maxPages` and `maxBytes` |
| `fhir.searchBundle(c, type, query)` | `json.Value` | the first page of a search |
| `fhir.nextBundle(c, b)` | `list of json.Value` | the next page, or nothing |
| `fhir.create(c, resource)` | `json.Value` | create; the server assigns the id |
| `fhir.update(c, resource)` | `json.Value` | update, only if `meta.versionId` is current when it is set |
| `fhir.patch(c, type, id, operations, version)` | `json.Value` | apply a JSON Patch, only to `version` when not `""` |
| `fhir.delete(c, type, id)` | `null` | delete a resource |
| `fhir.history(c, type, id)` | `list of json.Value` | every version of a resource, newest first |
| `fhir.transaction(c, b)` | `json.Value` | run a transaction bundle, all or nothing |
| `fhir.batch(c, b)` | `json.Value` | run a batch bundle, entry by entry |
| `fhir.operation(c, path, parameters)` | `json.Value` | invoke `$name`, `Type/$name` or `Type/id/$name` |
| `fhir.call(c, method, path, query, body)` | `json.Value` | any other request |

## Resources

| Function | Returns | Does |
|---|---|---|
| `fhir.resourceType(r)` | `string` | the `resourceType` |
| `fhir.idOf(r)` | `string` | the `id`, `""` if none |
| `fhir.versionOf(r)` | `string` | `meta.versionId`, `""` if none |
| `fhir.reference(type, id)` | `string` | `Type/id` |
| `fhir.referenceOf(r)` | `string` | the resource's `Type/id` |
| `fhir.identifier(system, value)` | `json.Value` | an Identifier; neither may be empty |
| `fhir.identifierValue(r, system)` | `string` | the value of the resource's identifier in a system |
| `fhir.coding(system, code, display)` | `json.Value` | a Coding |
| `fhir.concept(system, code, display)` | `json.Value` | a CodeableConcept with one coding |
| `fhir.hasCoding(c, system, code)` | `bool` | whether a CodeableConcept has a coding |
| `fhir.bundle(type)` | `json.Value` | a bundle without entries: `transaction`, `batch`, `collection`, `document`, `message` |
| `fhir.entry(b, method, url, resource, fullUrl)` | `json.Value` | add a checked request entry to a transaction or batch |
| `fhir.resourcesOf(b)` | `list of json.Value` | the resources of a bundle's entries |
| `fhir.issues(outcome)` | `list of Issue` | the issues of an OperationOutcome |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `baseUrl as string` | the server's base URL, without a trailing slash |
| `headers as map of string to string` | headers sent with every request |
| `tls as http.TlsOptions` | certificate checks for https |
| `allowPlainHttp as bool` | plain http to another machine allowed |
| `timeoutMs as int` | the deadline of one request |
| `maxBytes as int` | the largest response |
| `maxPages as int` | the page cap of `search` and `history` |

### `HttpError`

Thrown, not returned: test `$e.kind == "fhir.http"` before reading the
other fields.

| Field | Meaning |
|---|---|
| `kind as string` | `fhir.http` |
| `message as string` | the request, the server's diagnostics and `(HTTP nnn)` |
| `status as int` | the HTTP status, such as 404, 409 or 412 |
| `issues as list of Issue` | the OperationOutcome's issues, empty when there was none |

### `Issue`

| Field | Meaning |
|---|---|
| `severity as string` | `fatal`, `error`, `warning`, `information` |
| `code as string` | the issue type, such as `not-found` |
| `diagnostics as string` | the server's diagnostic text |
| `text as string` | `details.text` |
| `expression as list of string` | where in the resource, as FHIRPath |
