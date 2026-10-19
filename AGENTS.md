# AGENTS.md

## Project

moirai is an Erlang/OTP reference harness wiring erl_openrouter,
erl_mcp, klotho, and magicbeam into a runnable, citable, teachable
artifact. Named after the Greek Fates collectively -- Klotho spins the
thread; the Moirai are the assembled whole. It is a learning artifact,
not a production application. Requires OTP 27+.

## Build and Test

```
make compile       # Docker-based rebar3 compile
make test          # Docker-based consolidated gate
make local-test    # eunit + ct + runtime smoke + dialyzer + cover
make local-eunit   # eunit only
make local-ct      # common_test only
make dialyzer      # Docker-based dialyzer
make shell         # regular rebar3 shell
make demo          # Shellbeam interactive demo + weather sidecar
```

The consolidated `make test` gate runs EUnit, Common Test, the runtime
smoke test, Dialyzer, coverage, Docker Compose validation, and a real
PTY/Edlin shell smoke test.

rebar3 is not vendored; the Docker image builds it from source.
Klotho remains a private git dependency until its public release.
A local `_checkouts/klotho` checkout overrides the declared dependency
automatically when present.

## Module Inventory

### Application and supervision

| Module | Description |
|--------|-------------|
| `moirai_app` | OTP application callback, delegates to `moirai_sup` |
| `moirai_sup` | Top-level supervisor; long-lived dependency clients are owned by their dependency applications |

### Agent, shell, and tools

| Module | Description |
|--------|-------------|
| `moirai` | Public agent API, Shellbeam lifecycle, conversation state, and asynchronous MCP discovery |
| `moirai_shell` | Shellbeam commands and human-readable result formatting |
| `moirai_tools` | Local filesystem tools with traversal and `.gitignore` protection |
| `moirai_geoip` | Optional approximate-location lookup and prompt context |
| `moirai_weather` | Open-Meteo MCP tool allow-list and weather prompt context |
| `moirai_mcp_config` | gitmcp.io allow-list for erl_openrouter, erl_mcp, and magicbeam |

### Tests

| Module | Description |
|--------|-------------|
| `moirai_demo_tests` | EUnit coverage for shell behavior, tool filtering, and agent configuration |
| `moirai_geoip_tests` | EUnit coverage for GeoIP response decoding and context |
| `moirai_mcp_config_tests` | EUnit coverage for the gitmcp.io allow-list |
| `moirai_purge_zombie_deps_tests` | EUnit coverage for checkout artifact cleanup |
| `moirai_integration_SUITE` | Live LLM and gitmcp.io Common Test groups with prerequisite skips |

## Dependencies

- `erl_openrouter` -- supervised OpenRouter transport
- `erl_mcp` -- HTTP streamable MCP client
- `klotho` -- agent and tool-use loop; private until its public release
- `magicbeam` -- Shellbeam interactive shell, with Hotbeam and
  Thunderbeam available but disabled by default

All dependencies are declared in `rebar.config`. Local `_checkouts/`
entries are development overrides, not the shipped source of truth.

## Key Design Decisions

1. **Single OTP application, not umbrella** -- The harness is the demo.

2. **Dependency-owned OpenRouter supervision** -- `openrouter_client`
   is started by erl_openrouter. Starting it from `moirai_sup` would
   collide on its registered name.

3. **Ephemeral agent and MCP processes** -- Klotho agents are per
   conversation. Remote MCP clients are discovered asynchronously for
   an interactive shell and stopped when that shell ends.

4. **Live integration gates** -- The LLM group requires
   `OPENROUTER_API_KEY`; the public MCP group skips when its endpoint
   is unavailable. Mocking either dependency would test the mock rather
   than the assembled stack.

5. **Guardrailed gitmcp.io access** -- Only the three public stack
   repositories are queryable. Moirai and Klotho can be added after
   they are public.

## Conventions

- `warnings_as_errors` is enabled in rebar.config
- No catch-all clauses that silently swallow errors
- Prefer returning `{error, Reason}` tuples over throwing
- Binary strings for protocol-level data
- Mirror the established Erlang OSS Makefile, Docker, CI, and Avakas patterns
