#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * bundle example: resources without a server. It builds a Patient and an
 * Observation that refers to it, puts both in a transaction bundle (the
 * patient by a temporary urn:uuid), and prints the bundle a server would
 * get from `fhir.transaction`.
 *
 *   jennifer run examples/bundle.j
 */

use io;
use json;

import "../src/fhir.j" as fhir;

def patientUrl as string init "urn:uuid:9b1f0a54-62c7-4e7c-9d41-6cf0d4f0a001";

def patient as json.Value init json.decode('{"resourceType":"Patient","name":[{"family":"Doe","given":["Jane"]}],"birthDate":"1980-02-14"}');
$patient = json.set(
    $patient,
    "/identifier",
    json.list([fhir.identifier("urn:oid:1.2.3.4", "MRN-1001")]));

def obs as json.Value init json.decode('{"resourceType":"Observation","status":"final"}');
$obs = json.set($obs, "/code", fhir.concept("http://loinc.org", "2345-7", "Glucose"));
$obs = json.set($obs, "/subject", json.map({"reference": $patientUrl}));
$obs = json.set(
    $obs,
    "/valueQuantity",
    json.decode('{"value":5.4,"unit":"mmol/L","system":"http://unitsofmeasure.org","code":"mmol/L"}'));

def b as json.Value init fhir.bundle("transaction");
$b = fhir.entry($b, "POST", "Patient", $patient, $patientUrl);
$b = fhir.entry($b, "POST", "Observation", $obs, "");

io.printf(
    "%d resources, glucose coded: %v\n",
    len(fhir.resourcesOf($b)),
    fhir.hasCoding(json.get($obs, "/code"), "http://loinc.org", "2345-7"));
io.printf("%s\n", json.encodePretty($b));
