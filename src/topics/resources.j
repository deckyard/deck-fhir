# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# fhir - resources: helpers for resources as `json.Value` - their type, id
# and version, references, identifiers, codings, bundles and the issues of an
# OperationOutcome. Pure; no request is sent. Spliced into fhir.j via include.

# the bundle types a client builds
def const BUNDLE_TYPES as list of string init [
    "transaction",
    "batch",
    "collection",
    "document",
    "message"
];

# the request methods of a transaction or batch entry
def const ENTRY_METHODS as list of string init ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"];

/**
 * One issue of an OperationOutcome.
 *
 * @field severity {string} `fatal`, `error`, `warning` or `information`
 * @field code {string} the issue type, such as `not-found`, `invalid`, `conflict`
 * @field diagnostics {string} the server's diagnostic text, `""` when absent
 * @field text {string} `details.text`, `""` when absent
 * @field expression {list of string} where in the resource the issue is, as FHIRPath expressions (from the deprecated `location` when a server sends only that)
 */
export def struct Issue {
    severity as string,
    code as string,
    diagnostics as string,
    text as string,
    expression as list of string
};

/**
 * A string at a JSON pointer, `""` when the pointer does not resolve.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the string
 * @throws {Error} kind "fhir" when the node is there but not a string
 */
func text(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing") {
        return "";
    }
    if ($t != "string") {
        fail(shown($ptr) + " is a " + $t + ", not a string");
    }
    return json.asString($v, $ptr);
}

/**
 * The type of a resource.
 *
 * @param r {json.Value} the resource
 * @return {string} its `resourceType`, such as `Patient`
 * @throws {Error} kind "fhir" when it has none
 */
export func resourceType(r as json.Value) {
    if (json.typeOf($r) != "map" or json.typeOf($r, "/resourceType") != "string") {
        fail("not a resource: it has no resourceType");
    }
    def t as string init json.asString($r, "/resourceType");
    checkType($t);
    return $t;
}

/**
 * The id of a resource.
 *
 * @param r {json.Value} the resource
 * @return {string} its `id`, `""` when it has none
 */
export func idOf(r as json.Value) {
    return text($r, "/id");
}

/**
 * The version of a resource, `meta.versionId`.
 *
 * @param r {json.Value} the resource
 * @return {string} the version, `""` when it has none
 */
export func versionOf(r as json.Value) {
    return text($r, "/meta/versionId");
}

/**
 * A relative reference.
 *
 * @param type {string} the resource type
 * @param id {string} the id
 * @return {string} `type/id`, such as `Patient/123`
 * @example
 *   $obs = json.set($obs, "/subject", json.map({"reference": fhir.reference("Patient", "123")}));
 */
export func reference(type as string, id as string) {
    checkType($type);
    checkId($id, "an id");
    return $type + "/" + $id;
}

/**
 * The relative reference of a resource that has an id.
 *
 * @param r {json.Value} the resource
 * @return {string} `type/id`
 * @throws {Error} kind "fhir" when it has no type or id
 */
export func referenceOf(r as json.Value) {
    return reference(resourceType($r), idOf($r));
}

/**
 * An Identifier.
 *
 * @param system {string} the namespace URI, such as `http://hospital.example.org/mrn`
 * @param value {string} the value
 * @return {json.Value} `{"system": ..., "value": ...}`
 * @throws {Error} kind "fhir" when the system or value is empty (FHIR has no empty strings)
 */
export func identifier(system as string, value as string) {
    if ($system == "" or $value == "") {
        fail("an identifier needs a system and a value");
    }
    return json.map({"system": $system, "value": $value});
}

/**
 * The value of a resource's identifier in a system.
 *
 * @param r {json.Value} the resource
 * @param system {string} the system
 * @return {string} the first matching identifier's value, `""` when none
 */
export func identifierValue(r as json.Value, system as string) {
    if (json.typeOf($r, "/identifier") != "list") {
        return "";
    }
    for (def i in 0..json.length($r, "/identifier")) {
        def at as string init "/identifier/" + convert.toString($i);
        if (text($r, $at + "/system") == $system) {
            return text($r, $at + "/value");
        }
    }
    return "";
}

/**
 * A Coding.
 *
 * @param system {string} the code system, such as `http://loinc.org`
 * @param code {string} the code
 * @param display {string} its display text, `""` to leave it out
 * @return {json.Value} the coding
 */
export func coding(system as string, code as string, display as string) {
    if ($system == "" or $code == "") {
        fail("a coding needs a system and a code");
    }
    def c as json.Value init json.map({"system": $system, "code": $code});
    if ($display != "") {
        $c = json.set($c, "/display", $display);
    }
    return $c;
}

/**
 * A CodeableConcept with one coding.
 *
 * @param system {string} the code system
 * @param code {string} the code
 * @param display {string} its display text, `""` to leave it out
 * @return {json.Value} `{"coding": [...]}`
 * @example
 *   $obs = json.set($obs, "/code", fhir.concept("http://loinc.org", "2345-7", "Glucose"));
 */
export func concept(system as string, code as string, display as string) {
    return json.set(json.map(), "/coding", json.list([coding($system, $code, $display)]));
}

/**
 * Whether a CodeableConcept has a coding.
 *
 * @param c {json.Value} the CodeableConcept
 * @param system {string} the code system
 * @param code {string} the code
 * @return {bool} true when one of its codings has that system and code
 */
export func hasCoding(c as json.Value, system as string, code as string) {
    if (json.typeOf($c, "/coding") != "list") {
        return false;
    }
    for (def i in 0..json.length($c, "/coding")) {
        def at as string init "/coding/" + convert.toString($i);
        if (text($c, $at + "/system") == $system and text($c, $at + "/code") == $code) {
            return true;
        }
    }
    return false;
}

/**
 * A new Bundle without entries (FHIR JSON has no empty arrays; `entry`
 * adds the list).
 *
 * @param type {string} `transaction`, `batch`, `collection`, `document` or `message`
 * @return {json.Value} the bundle
 * @example
 *   def b as json.Value init fhir.bundle("transaction");
 */
export func bundle(type as string) {
    if (not lists.contains(BUNDLE_TYPES, $type)) {
        fail("a bundle type is one of " + strings.join(BUNDLE_TYPES, ", ") + ", got " + shown($type));
    }
    return json.map({"resourceType": "Bundle", "type": $type});
}

/**
 * Add an entry to a transaction or batch bundle.
 *
 * @param b {json.Value} the bundle
 * @param method {string} `GET`, `HEAD`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param url {string} the request URL relative to the base, such as `Patient` or `Patient/123`
 * @param resource {json.Value} the resource for POST, PUT and PATCH (a PUT to `Type/id` must carry that type and id); JSON `null` for GET, HEAD and DELETE
 * @param fullUrl {string} the entry's fullUrl: `urn:uuid:<uuid>` for a resource others in the bundle refer to, `urn:oid:...` or an absolute URL; `""` for none
 * @return {json.Value} the bundle
 * @throws {Error} kind "fhir" when the bundle is not a transaction or batch, or the method, URL, resource or fullUrl does not fit
 * @example
 *   $b = fhir.entry($b, "POST", "Patient", $patient, "urn:uuid:" + uuid.v4());
 */
export func entry(
    b as json.Value,
    method as string,
    url as string,
    resource as json.Value,
    fullUrl as string) {
    if (resourceType($b) != "Bundle" or
        (text($b, "/type") != "transaction" and text($b, "/type") != "batch")) {
        fail("entries with requests go into a transaction or batch bundle");
    }
    if (not lists.contains(ENTRY_METHODS, $method)) {
        fail("an entry method is one of " + strings.join(ENTRY_METHODS, ", ") + ", got " +
            shown($method));
    }
    if ($url == "" or strings.contains($url, "://") or strings.startsWith($url, "/") or
        regex.matches('[\s\x00-\x1f\x7f]', $url)) {
        fail("an entry URL is relative to the base, such as Patient/123, got " + shown($url));
    }
    def hasResource as bool init json.typeOf($resource) != "null";
    def needs as bool init $method == "POST" or $method == "PUT" or $method == "PATCH";
    if ($needs and not $hasResource) {
        fail("a " + $method + " entry needs a resource");
    }
    if ($hasResource and not $needs) {
        fail("a " + $method + " entry has no resource");
    }
    if ($fullUrl != "" and
        not regex.matches(
        '^(urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|urn:oid:[0-2](\.[0-9]+)+|https?://[^\s]+)$',
        $fullUrl)) {
        fail("a fullUrl is urn:uuid:<uuid>, urn:oid:<oid> or an absolute URL, got " +
            shown($fullUrl));
    }
    def e as json.Value init json.map();
    if ($fullUrl != "") {
        $e = json.set($e, "/fullUrl", $fullUrl);
    }
    if ($hasResource) {
        def type as string init resourceType($resource);
        def m as regex.Match init regex.find('^([A-Za-z]+)/([^/?]+)$', $url);
        if ($method == "PUT" and $m.start == 0 and
            ($m.groups[0] != $type or ($m.groups[1] != idOf($resource)))) {
            fail("PUT " + $url + " carries a " + $type + " with id " + shown(idOf($resource)));
        }
        $e = json.set($e, "/resource", $resource);
    }
    $e = json.set($e, "/request", json.map({"method": $method, "url": $url}));
    if (json.typeOf($b, "/entry") != "list") {
        $b = json.set($b, "/entry", json.list());
    }
    return json.append($b, "/entry", $e);
}

/**
 * The resources in a bundle's entries, in order; entries without a resource
 * are left out.
 *
 * @param b {json.Value} the bundle
 * @return {list of json.Value} the resources
 * @throws {Error} kind "fhir" when it is not a Bundle
 */
export func resourcesOf(b as json.Value) {
    if (resourceType($b) != "Bundle") {
        fail("not a Bundle: " + resourceType($b));
    }
    def out as list of json.Value init [];
    if (json.typeOf($b, "/entry") != "list") {
        return $out;
    }
    for (def i in 0..json.length($b, "/entry")) {
        def at as string init "/entry/" + convert.toString($i) + "/resource";
        if (json.typeOf($b, $at) == "map") {
            $out[] = json.get($b, $at);
        }
    }
    return $out;
}

/**
 * The issues of an OperationOutcome.
 *
 * @param outcome {json.Value} the OperationOutcome
 * @return {list of Issue} its issues
 * @throws {Error} kind "fhir" when it is not an OperationOutcome
 * @example
 *   for (def i in fhir.issues($outcome)) {
 *       io.printf("%s %s: %s\n", $i.severity, $i.code, $i.diagnostics);
 *   }
 */
export func issues(outcome as json.Value) {
    if (resourceType($outcome) != "OperationOutcome") {
        fail("not an OperationOutcome: " + resourceType($outcome));
    }
    def out as list of Issue init [];
    if (json.typeOf($outcome, "/issue") != "list") {
        return $out;
    }
    for (def i in 0..json.length($outcome, "/issue")) {
        def at as string init "/issue/" + convert.toString($i);
        if (json.typeOf($outcome, $at) != "map" or text($outcome, $at + "/severity") == "" or
            text($outcome, $at + "/code") == "") {
            fail(io.sprintf("issue %d of the OperationOutcome has no severity or code", $i + 1));
        }
        def where as list of string init [];
        def field as string init "/expression";
        if (json.typeOf($outcome, $at + "/expression") != "list") {
            $field = "/location";
        }
        if (json.typeOf($outcome, $at + $field) == "list") {
            for (def k in 0..json.length($outcome, $at + $field)) {
                $where[] = text($outcome, $at + $field + "/" + convert.toString($k));
            }
        }
        $out[] = Issue{
            severity: text($outcome, $at + "/severity"),
            code: text($outcome, $at + "/code"),
            diagnostics: text($outcome, $at + "/diagnostics"),
            text: text($outcome, $at + "/details/text"),
            expression: $where
        };
    }
    return $out;
}
