# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for HL7 FHIR R4 and R5 servers over their REST API: the
 * CapabilityStatement, read and vread, search with paging, create, update
 * and JSON Patch with version checks, delete, history, transactions and
 * batches, operations (`$everything`, `$validate`, ...), and `call` for the
 * rest. Resources stay `json.Value`, read and built with the `json` library;
 * helpers cover references, identifiers, codings, bundles and the issues of
 * an OperationOutcome. Authentication is a bearer token, or SMART on FHIR
 * backend services through the `oauth` module.
 *
 * A request the server refuses throws `HttpError` (kind `fhir.http`) with the
 * HTTP status and the OperationOutcome's issues as fields; every other
 * failure is `Error{kind: "fhir"}`. Every request has a deadline and a
 * response cap; plain `http` is refused except to this machine; links the
 * server returns are followed only below its base URL, so the token never
 * leaves it.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Client`, settings, the exchange, errors |
 * | `resources` | types, ids, references, identifiers, codings, bundles, issues |
 * | `rest` | the RESTful interactions |
 * | `auth` | SMART on FHIR |
 *
 * @module fhir
 * @see https://hl7.org/fhir/R4/http.html
 * @example
 *   def c as fhir.Client init fhir.withToken(fhir.client("https://fhir.example.org/r4"), $token);
 *   for (def p in fhir.search($c, "Patient", ["family=Doe"])) {
 *       io.printf("%s\n", fhir.referenceOf($p));
 *   }
 */
use convert;
use encoding;
use io;
use json;
use lists;
use maps;
use regex;
use strings;
use task;

import "http.j" as http;
import "oauth.j" as oauth;
import "uri.j" as uri;

include "topics/core.j";
include "topics/resources.j";
include "topics/rest.j";
include "topics/auth.j";
