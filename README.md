# @deckyard/fhir

[![test](https://github.com/deckyard/deck-fhir/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-fhir/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-fhir/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-fhir)](https://github.com/deckyard/deck-fhir/releases/latest)

An HL7 FHIR R4 / R5 client for [Jennifer](https://jennifer-lang.dev/)
programs: read, search with paging, create, update and JSON Patch with
version checks, delete, history, transactions, batches and operations,
with resources as `json.Value`, helpers for references, identifiers,
codings, bundles and OperationOutcome, bearer tokens and SMART on FHIR
backend services. Every request has a deadline and a response cap, plain
http is refused except to this machine, and the token never follows a link
off the server.

**[Documentation](https://deckyard.github.io/deck-fhir/)**

## Install

```sh
jvc add @deckyard/fhir
```

This vendors the deck to `vendor/<scope>/fhir/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-fhir-<version>.tar.gz`) there.

## Usage

```jennifer
use io;

import "@deckyard/fhir/" as fhir;

def c as fhir.Client init fhir.withToken(fhir.client("https://fhir.example.org/r4"), $token);
for (def p in fhir.search($c, "Patient", ["family=Doe"])) {
    io.printf("%s\n", fhir.referenceOf($p));
}
```

## Requirements

Jennifer 0.26.0 or newer and the default `jennifer` binary: the deck needs
`net`, which the stock `jennifer-tiny` lacks.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/fhir_test.j        # the tests, against a fake server
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
