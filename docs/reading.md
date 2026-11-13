<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading and searching

```jennifer
def c as fhir.Client init fhir.client("https://fhir.example.org/r4");
def caps as json.Value init fhir.capabilities($c);
io.printf("FHIR %s\n", json.asString($caps, "/fhirVersion"));
```

## Read

`read` gets the current version, `vread` an older one:

```jennifer
def p as json.Value init fhir.read($c, "Patient", "123");
def v2 as json.Value init fhir.vread($c, "Patient", "123", "2");
```

A missing resource fails with HTTP 404, a deleted one with 410.

## Search

Search parameters are `name=value` strings, in the server's own syntax:
modifiers (`name:exact`), prefixes (`birthdate=ge1980-01-01`), chains
(`subject.name=Doe`), `_count`, `_sort`, `_include`. Values are
percent-encoded by the deck.

```jennifer
for (def o in fhir.search($c, "Observation", ["subject=Patient/123", "code=http://loinc.org|2345-7", "_sort=-date"])) {
    io.printf("%s\n", json.encode(json.get($o, "/valueQuantity")));
}
```

`search` follows every `next` link and returns the resources that matched.
`_count` sets the page size, not the number of results: for the first few
only, take `resourcesOf(searchBundle(...))`.
It stops with an error after `maxPages` pages (100; `withMaxPages`), or
when all pages together hold more than `maxBytes` bytes (8 MiB;
`withMaxBytes`), rather than reading an unbounded result. Decoded JSON takes
roughly twenty times its size in memory, so the default keeps a search
under about 170 MB. To read more, page yourself with `searchBundle` and
`nextBundle`, which also give the included resources (`_include`) and the
total: narrow the search, or page yourself with
`searchBundle` and `nextBundle`, which also give the included resources
(`_include`) and the total:

```jennifer
def page as json.Value init fhir.searchBundle($c, "Encounter", ["status=in-progress", "_include=Encounter:subject"]);
def more as bool init true;
while ($more) {
    for (def r in fhir.resourcesOf($page)) {
        io.printf("%s %s\n", fhir.resourceType($r), fhir.idOf($r));
    }
    def next as list of json.Value init fhir.nextBundle($c, $page);
    $more = len($next) > 0;
    if ($more) {
        $page = $next[0];
    }
}
```

A next link that leaves the server's base URL is refused.

## History

`history` gives every version of a resource, newest first; a deletion in
the history has no resource and is left out.

## Operations and the rest

`operation` invokes a named operation with a Parameters resource (JSON
`null` to send none); `call` sends any other request below the base URL.
An operation that returns a Bundle, such as `$everything`, may page it:
read the rest with `nextBundle`.

```jennifer
def everything as json.Value init fhir.operation($c, "Patient/123/$everything", json.decode("null"));
def stats as json.Value init fhir.call($c, "GET", "Observation/$stats", ["patient=Patient/123"], json.decode("null"));
```
