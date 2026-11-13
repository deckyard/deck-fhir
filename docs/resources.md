<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Resources

A resource is a `json.Value`. Read it with JSON pointers and change it with
`json.set`, `json.append` and `json.remove`:

```jennifer
def family as string init json.asString($p, "/name/0/family");
$p = json.set($p, "/birthDate", "1980-02-14");
$p = json.append($p, "/identifier", fhir.identifier("urn:oid:1.2.3.4", "MRN-1001"));
```

The helpers cover what every resource has: `resourceType`, `idOf`,
`versionOf`, `referenceOf` (`Patient/123`), and `reference(type, id)` to
build one. `identifierValue` finds the value of an identifier in a system.

## Codes

```jennifer
$obs = json.set($obs, "/code", fhir.concept("http://loinc.org", "2345-7", "Glucose"));
if (fhir.hasCoding(json.get($obs, "/code"), "http://loinc.org", "2345-7")) {
    io.printf("a glucose observation\n");
}
```

## Bundles

`resourcesOf` gives the resources of any bundle's entries; `bundle` and
`entry` build transactions and batches (see [Writing](writing.md)).

## OperationOutcome

A server explains a failure with an OperationOutcome. The deck puts its
diagnostics into the error message; `issues` reads one fully, such as the
result of `$validate`:

```jennifer
for (def i in fhir.issues($outcome)) {
    io.printf("%s %s at %s: %s\n", $i.severity, $i.code,
        strings.join($i.expression, ", "), $i.diagnostics);
}
```
