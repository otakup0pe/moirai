# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Moirai agent application** -- `moirai` assembles erl_openrouter,
  erl_mcp, Klotho, and Magicbeam into one Erlang/OTP learning artifact.
- **Interactive Shellbeam demo** -- Colored conversation boundaries,
  Edlin history and navigation, human-readable status, conversation
  reset, and summarize-on-quit.
- **Local checkout tools** -- `list_directory` and `read_file`
  inspect the real Moirai source tree while blocking traversal and
  paths excluded by `.gitignore`.
- **Asynchronous MCP discovery** -- Open-Meteo weather tools and
  repo-namespaced gitmcp.io tools connect in the background. The
  gitmcp.io guardrail permits erl_openrouter, erl_mcp, and magicbeam.
- **Approximate local weather context** -- Optional GeoIP context feeds
  the isolated Open-Meteo MCP sidecar without requiring a weather API
  key.
- **One-shot API** -- `moirai:run/1` runs a Klotho agent against the
  local project tools and returns its result record.
- **Dependency hygiene** -- Checkout-aware Docker mounts and
  `scripts/purge-zombie-deps` prevent stale compiled dependencies from
  shadowing the active lock or checkout.
- **Consolidated test gate** -- `make test` runs EUnit, runtime startup,
  Dialyzer, coverage, Compose validation, and a real PTY/Edlin shell
  smoke test.
- Docker-based build infrastructure, GitHub Actions CI, and the Avakas
  release workflow.
