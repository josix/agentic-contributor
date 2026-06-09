---
name: dev-env-setup
description: >
  This skill should be used when the user asks to set up their local development environment for
  an open-source project. Trigger phrases include: "set up the project locally", "how do I clone
  and build X", "help me get the dev environment running", "how do I run the tests for X",
  "I can't get the build to work", "set up apache/airflow locally", "set up apache/spark locally",
  "what are the prerequisites for X".
---

# Dev Environment Setup

To guide a contributor through setting up their local development environment, follow these steps:

## 1. Extract Documented Setup Steps

Locate and read the project's official setup documentation:

- `CONTRIBUTING.md` / `CONTRIBUTING.rst` — look for "Development Setup", "Local Development",
  or "Building from Source" sections.
- `README.md` — may contain a quick-start or prerequisites section.
- `docs/` directory for deeper setup guides.
- Docker/container setup files if documented as the primary path (`Dockerfile`, `docker-compose.yml`,
  `scripts/ci/` directories).

Present the steps **in order** as extracted from the official docs. Do not improvise steps not in
the documentation.

## 2. Flag Heavy or Platform-Specific Setups

Before the user starts, flag any known heavy or finicky setup requirements:

**Apache Airflow (Breeze):**
> Airflow uses its own Docker-based development environment called **Breeze**. Setup requires
> Docker Desktop (or a Docker daemon), and the initial image pull is several GB. First-time setup
> can take 15–30 minutes. The canonical entry point is `./scripts/ci/tools/breeze`.
> Non-Breeze local setup is also documented but less supported for testing.

**Apache Spark (JDK + Scala + SBT/Maven):**
> Spark requires a supported JDK (check the current CONTRIBUTING.md — typically JDK 8 or 11/17),
> Scala (usually installed via sbt), and either Maven or sbt for the build. The full build
> (`./build/mvn -DskipTests package`) can take 10–30 minutes on first run.
> PySpark additionally requires a matching Python version.

For other projects, check CONTRIBUTING.md and surface any flagged prerequisites.

## 3. Define the "Environment Ready" Checkpoint

Guide the contributor to a **verifiable** checkpoint — the project's test suite or a smoke build:

- Present the specific command the project recommends for verification (e.g.,
  `pytest tests/unit/`, `./gradlew test`, `mvn test -pl core -Dtest=SimpleTest`).
- State what a passing result looks like (test count, success message, or build artifact).
- Only declare "environment ready" after the checkpoint command succeeds.

## 4. Diagnose Failures

When a setup step fails:

1. Identify which documented requirement or version constraint is not met.
2. Refer back to the project's documented prerequisites (OS version, tool version, env var).
3. Suggest the documented fix or point to the project's troubleshooting section if one exists.
4. NEVER suggest changes that could break other projects or the system toolchain without explicit
   confirmation from the user.

## 5. Confirm Before Destructive Actions

If any step would make a destructive or global change (e.g., upgrading a system package, changing
`$PATH` permanently, removing existing virtual environments), present it as a confirmation step:

> "The next step will [describe change]. Do you want to proceed? (yes/no)"

Proceed only after explicit confirmation.

## 6. Scope Boundary

This skill ends at a verified, ready development environment. The following are **out of scope**
and belong to the separate execution/submission plugin:

- Writing code or tests.
- Committing changes.
- Opening or updating a pull request.
- Pushing branches.

State this boundary clearly if the user asks about next steps beyond environment setup.

## Output Format

Structure the guidance as:

```
## Dev Environment Setup: <owner/repo>

### Prerequisites
<list of required tools, versions, and download links>

### Setup Steps
1. <step from official docs>
2. <step>
...

### Environment Ready Checkpoint
<command to run> → <expected success output>

### Known Pitfalls
<any flagged heavy setups or common failure modes>
```
