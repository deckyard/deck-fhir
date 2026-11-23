#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * patients example: ask a FHIR server for its version, then list the
 * patients with a family name, every page, each with its three latest
 * observations.
 *
 *   FHIR_TOKEN=... jennifer run examples/patients.j https://fhir.example.org/r4 Doe
 *   jennifer run examples/patients.j http://localhost:8080/fhir Doe
 *
 * FHIR_TOKEN is optional. Without arguments it prints this usage, so CI runs
 * it without a server.
 */

use io;
use json;
use os;

import "../src/fhir.j" as fhir;

def args as list of string init os.ARGS;
if (len($args) != 3) {
    io.printf("usage: [FHIR_TOKEN=...] jennifer run examples/patients.j <base-url> <family>\n");
    exit 0;
}

try {
    def c as fhir.Client init fhir.client($args[1]);
    if (os.getEnv("FHIR_TOKEN") != "") {
        $c = fhir.withToken($c, os.getEnv("FHIR_TOKEN"));
    }
    def caps as json.Value init fhir.capabilities($c);
    io.printf("FHIR %s\n", json.asString($caps, "/fhirVersion"));
    for (def p in fhir.search($c, "Patient", ["family=" + $args[2], "_count=50"])) {
        def ref as string init fhir.referenceOf($p);
        def born as string init "unknown";
        if (json.typeOf($p, "/birthDate") == "string") {
            $born = json.asString($p, "/birthDate");
        }
        io.printf("%s born %s\n", $ref, $born);
        def latest as json.Value init fhir.searchBundle(
            $c,
            "Observation",
            ["subject=" + $ref, "_sort=-date", "_count=3"]);
        for (def o in fhir.resourcesOf($latest)) {
            if (fhir.resourceType($o) == "Observation") {
                io.printf("  %s\n", json.encode(json.get($o, "/code")));
            }
        }
    }
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
