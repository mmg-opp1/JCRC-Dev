# RetrieveSFLocal

A portable, drop-in tool to pull a **complete local copy of a Salesforce org's
metadata** into a single, standard SFDX source tree. Copy this whole folder into
the root of any local repo (or any empty folder), point it at an org, and run it.

It works against **any org** — production, sandbox, scratch, or a namespaced
packaging org — no matter which managed packages, standard objects, or custom
objects it has.

---

## Prerequisites

1. **Salesforce CLI (`sf`)** installed and on your PATH —
   <https://developer.salesforce.com/tools/salesforcecli>
   (check with `sf --version`).
2. **PowerShell** (Windows PowerShell 5.1 or PowerShell 7+).
3. The org **authenticated** with the CLI (see below).

---

## Quick start

```powershell
# 1. Put this folder at the root of your repo, e.g.  <your-repo>/RetrieveSFLocal/

# 2. Authenticate the org once (opens a browser). Pick any alias you like:
sf org login web --alias MyOrg

# 3. Retrieve everything:
./RetrieveSFLocal/Retrieve-FullOrg.ps1 -OrgAlias MyOrg
```

Metadata lands in `force-app/main/default/` at the repo root. A full run is
typically a few minutes.

> **Windows execution policy:** if the script is blocked, run it like this:
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\RetrieveSFLocal\Retrieve-FullOrg.ps1 -OrgAlias MyOrg
> ```

---

## What it does

| Layer | Captures |
|-------|----------|
| **1 — Objects** | Every customizable object (standard **+** custom **+** managed) by name, so your additive (non-namespaced) fields on managed objects come down *with* the object. |
| **2 — Regular types** | Every other top-level metadata type, **discovered at runtime** (not a fixed list). By default, filtered to what you own. |
| **3 — Folder types** | Email Templates, Reports, Dashboards, Documents (folder-by-folder). |

**Key design choices**
- **No wildcards.** Some orgs don't return namespaced (or even standard) members
  from a wildcard retrieve, so every member is enumerated **by name** via
  `listMetadata`. Reliable everywhere.
- **Dynamic discovery.** Metadata types are read from the org via
  `describeMetadata`, so the tool adapts to each org automatically.
- **Namespace policy.** By default it keeps what you own — non-namespaced
  metadata plus the org's *own* namespace (for packaging orgs) — and **excludes
  external managed-package components** (managed Apex/LWC/etc. are read-only and
  regenerable). Use `-IncludeManaged` to keep them too.
- **Resilient.** It tries one combined retrieve; if that fails, it falls back to
  retrieving each type on its own so a single problematic type can't abort the run.
- **Self-contained.** Generated manifests stay inside this folder. If the target
  folder isn't already an SFDX project, the script scaffolds a minimal
  `sfdx-project.json` + `force-app/` so it still works.

---

## Options

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `-OrgAlias <alias>` | default org from `sf config` | Which org to retrieve from. |
| `-IncludeManaged` | off | Also keep external managed-package members (complete mirror). |
| `-OnlyTypes a,b` | (all) | Restrict to specific top-level types. |
| `-ExcludeTypes a,b` | (none) | Skip specific types (e.g. `ConnectedApp,CustomObjectTranslation`). |
| `-ApiVersion 62.0` | project's `sourceApiVersion`, else 62.0 | Metadata API version. |
| `-ProjectRoot <path>` | parent of this folder | Where the metadata is written. |
| `-ManifestOnly` | off | Build the manifest and print coverage, but don't retrieve. |

Examples:
```powershell
./RetrieveSFLocal/Retrieve-FullOrg.ps1 -OrgAlias MySandbox -IncludeManaged
./RetrieveSFLocal/Retrieve-FullOrg.ps1 -OrgAlias MyOrg -ExcludeTypes CustomObjectTranslation
./RetrieveSFLocal/Retrieve-FullOrg.ps1 -ManifestOnly        # preview what would be pulled
```

---

## Tips & troubleshooting

- **See what would be pulled first:** run with `-ManifestOnly` and inspect
  `RetrieveSFLocal/full-org.generated.xml`.
- **A type fails to retrieve:** the per-type fallback reports which type failed;
  re-run with `-ExcludeTypes <thatType>` to skip it.
- **Object translations are heavy:** `CustomObjectTranslation` is often dominated
  by managed-package-shipped translations. Exclude with
  `-ExcludeTypes CustomObjectTranslation`, or add `**/objectTranslations/**` to the
  repo's `.forceignore`.
- **"Could not describe metadata / not authenticated":** run
  `sf org login web --alias <alias>` and pass that alias with `-OrgAlias`.
- **Keep backups private.** Salesforce metadata includes profiles, permission
  sets, email addresses, connected-app keys, and certificates — never push it to a
  public repo.

---

_Author: Jason Ott_
