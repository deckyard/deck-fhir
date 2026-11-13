# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests: jennifer test src/fhir_test.j
 *
 * No test needs a FHIR server. A fake on 127.0.0.1 (`startFake` in the core
 * overlay) answers each request from a script and records what it got. The
 * topic overlays are fragments spliced in here, not standalone suites.
 */
use crypto;
use encoding;
use httpd;
use testing;
use time;

include "topics/core_test.j";
include "topics/resources_test.j";
include "topics/rest_test.j";
include "topics/auth_test.j";
