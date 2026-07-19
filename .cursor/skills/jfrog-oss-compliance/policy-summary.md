# JFrog OSS Policy — Structured Summary

Source: *JFrog OSS Policy for Consumption, JFrog OSS Projects, and OSS Contribution* (created July 2025; owners: P&E, Legal, CTO).

This file is a structured summary used by the `jfrog-oss-compliance` skill. It is not the canonical policy — the canonical PDF is owned by P&E/Legal/CTO. Refresh this file when the policy is amended.

---

## 1. Scope

Applies to all JFrog employees, contractors, and third-party vendors involved in software that uses or contributes to OSS. Two stages covered:

- **Consumption** — using OSS created by others.
- **Contribution** — initiating new JFrog OSS projects, or contributing to external OSS projects.

Owners of the policy: Chief P&E, CTO, CLO. Amendments require their approval.

---

## 2. OSS Consumption (§3)

All OSS components must be evaluated before adoption against three criteria:

1. **Licensing** — license must be in the Acceptable bucket (see §6 below).
2. **Security** — vulnerability assessment + ongoing patch process. JFrog Xray is the recommended tool for scanning and ongoing monitoring.
3. **Operational risk** — project health: commit/PR/issue activity, release cadence, contributor diversity, community support, response rate, stars/forks/downloads, integrations, user base.

Compliance with the OSS license terms is required (attribution, source-code distribution, sharing modifications where applicable). For multi-licensed OSS, pick one of the listed licenses from the Acceptable bucket.

**OSS AI models** are subject to additional risk-management guidelines beyond this policy.

---

## 3. OSS Contribution (§4)

### 3.1 Contributing to projects maintained by others (§4.2)

- **Approval**: prior written approval from a Director-level (or above) manager.
- **CLA path**: if the upstream requires a CLA, contact Legal with a link to the CLA before signing.
- **No-CLA path** ("license in = out"): contribute under the project's own permissive license. Contact Legal for approval and provide the project link.
- **Affiliation**: make your JFrog affiliation clear in community discussions.
- **Time management**: contributions must not interfere with regular work obligations.

### 3.2 Initiating new JFrog OSS projects (§4.3)

Each new project requires:

- **Proposal** to the manager and CTO via the `OSSGOV` team. Proposal covers purpose, scope, benefits, resources, alignment with org goals, and intended license.
- **Designated leader** who acts as coordinator/lead contributor. JFrog will not rely on the external community to maintain the project.
- **Legal compliance** — consult Legal for IP/licensing concerns.
- **Community engagement** — encourage internal & external contributions; provide docs and support.
- **Documentation** — README, codebase, licensing details, contributor guidelines.

### 3.3 IP & licensing rules (§4.4)

- Contributions during employment are JFrog IP (subject to the relevant employment / contractor agreement). Once contributed, they are no longer confidential.
- **Default license** for new JFrog OSS projects: **Apache 2.0** (SPDX `Apache-2.0`). Other licenses may be approved case-by-case.
- All projects must:
  - include the JFrog CLA workflow;
  - be hosted under a JFrog organization account on an established OSS platform (e.g. GitHub, Hugging Face);
  - not include sensitive proprietary or confidential information, and no PII;
  - have all dependencies under licenses compatible with the project's license.

### 3.4 Special case — Artifactory AGPL release

A limited version of Artifactory is available under AGPL. Any change to that release requires CTO and CPEO approval. The artifactory release in question must remain under AGPL.

---

## 4. Quarterly process (FAQ section)

Each product team submits its 3rd-party component list (SBOM, produced via JFrog Xray) **once per quarter** by email to `ossgov@jfrog.com`. The OSSGOV team reviews, approves, and proceeds for publishing.

---

## 5. Enforcement (§5)

Lack of adherence may lead to disciplinary action, up to and including termination of employment or affiliation.

---

## 6. License classification (Appendix A)

Uses **Google's Third-Party license grouping**:

| Bucket | Examples | Status |
|---|---|---|
| **Unencumbered** | Unlicense, CC0 | Acceptable |
| **Notice** | Apache-2.0, BSD-3-Clause, MIT | Acceptable |
| **Reciprocal** | EPL, MPL, CDDL | Acceptable |
| **Restricted_if_statically_linked** | (subset of the next row) | Requires special approval |
| **Restricted** | GPL, LGPL, NGPL | Unacceptable |
| **By_exception_only** | special cases, internal use only | Requires explicit exception |

---

## 7. Markings — Appendix B (contributions to existing projects)

When contributing to an external project under a different license than the project's own (assuming permitted by the project's contribution rules + CLA), contribute under **Apache 2.0** (`SPDX: Apache-2.0`).

Add a copyright notice to all source-code files in the project, in one of these forms:

- `© JFrog Ltd. (YEAR)`
- `(c) JFrog Ltd. (YEAR)`

JFrog CLA reference: <https://jfrog.com/cla/>

---

## 8. Markings — Appendix C (new JFrog OSS projects)

- **License**: Apache 2.0 (`SPDX: Apache-2.0`). Other OSS licenses possible case-by-case via Legal.
- Include the **full Apache-2.0 license text** in a file named `LICENSE` at the project root.
- Add a copyright notice to **every** source-code file:
  - `© JFrog Ltd. (YEAR)` or `(c) JFrog Ltd. (YEAR)`

---

## 9. OSSGOV team

- Contact email: `ossgov@jfrog.com`
- Members (as of 2025): Guy Levi (VP Architect leads), Alex Haiut (VP of R&D, JFS).
- Responsibilities: review and approve new OSS projects; review quarterly SBOM submissions.
