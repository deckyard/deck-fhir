<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Writing

## Create

`create` posts a resource without an id; the server assigns one and the
deck returns the stored resource (asking with `Prefer:
return=representation`, or reading the Location, which must be on the
server, when it sends no body or only an OperationOutcome):

```jennifer
def p as json.Value init json.decode('{"resourceType":"Patient","name":[{"family":"Roe"}]}');
$p = fhir.create($c, $p);
io.printf("created %s version %s\n", fhir.referenceOf($p), fhir.versionOf($p));
```

## Update

`update` puts a resource with its id. When the resource carries
`meta.versionId`, as one just read does, the deck sends it as `If-Match`,
and the server applies the update only if nobody changed the resource in
between; otherwise it answers HTTP 412, or 409 as HAPI FHIR™ does:

```jennifer
def p as json.Value init fhir.read($c, "Patient", "123");
$p = json.set($p, "/active", false);
try {
    $p = fhir.update($c, $p);
} catch (e) {
    if ($e.kind == "fhir.http" and ($e.status == 412 or $e.status == 409)) {
        io.printf("changed meanwhile: read it again\n");
    } else {
        throw $e;
    }
}
```

To overwrite whatever is there, remove `meta.versionId` first
(`json.remove($p, "/meta/versionId")`). A server that allows it creates a
resource with the id given.

## Patch

`patch` applies a JSON Patch, only to `version` when it is not `""`:

```jennifer
def ops as json.Value init json.decode('[{"op":"replace","path":"/active","value":false}]');
$p = fhir.patch($c, "Patient", "123", $ops, fhir.versionOf($p));
```

## Delete

```jennifer
fhir.delete($c, "Patient", "123");
```

A server may refuse with HTTP 409 while other resources refer to it.

## Transactions and batches

A transaction runs every entry or none; a batch runs each on its own.
Entries are built with `bundle` and `entry`, which checks them: POST, PUT
and PATCH carry a resource, GET, HEAD and DELETE none, a PUT to `Type/id`
carries that type and id, and a `fullUrl` is `urn:uuid:<uuid>`,
`urn:oid:...` or an absolute URL. A resource created in the transaction can
be referred to by its `fullUrl` before it has an id:

```jennifer
def pid as string init "urn:uuid:" + uuid.v4();
def b as json.Value init fhir.bundle("transaction");
$b = fhir.entry($b, "POST", "Patient", $patient, $pid);
$obs = json.set($obs, "/subject", json.map({"reference": $pid}));
$b = fhir.entry($b, "POST", "Observation", $obs, "");
def result as json.Value init fhir.transaction($c, $b);
```

The response bundle has an entry per request with its `response.status`
and `response.location`; in a batch, read each one, since some may have
failed.
