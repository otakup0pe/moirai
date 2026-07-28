# AGENTS.md

## Project

moirai is an Erlang/OTP reference harness wiring erl_openrouter +
erl_mcp + klotho into a runnable, citable, teachable artifact. Named
after the Greek Fates collectively -- klotho spins the thread, the
moirai are the assembled whole. It is a learning artifact, not a
production application. Requires OTP 27+.

## Build and Test

```
make compile       # rebar3 compile
make test          # Docker-based: builds image, runs eunit + ct
make local-test    # runs eunit + ct directly (needs OTP 27 + rebar3)
make local-eunit   # eunit only
make local-ct      # common_test only
make dialyzer      # dialyzer
make shell         # rebar3 shell (starts moirai application)
```

rebar3 is not vendored; the Docker image builds it from source.

klotho must be available via `_checkouts/klotho` symlink for
compilation. rebar3's `_checkouts/` mechanism overrides deps
automatically.

## Module Inventory

### Application & Supervision

| Module | Description |
|--------|-------------|
| `moirai_app` | OTP application callback, delegates to `moirai_sup` |
| `moirai_sup` | Top-level supervisor; empty children list (MCP clients are per-demo ephemeral processes, not supervised) |

### Demo & Tools

| Module | Description |
|--------|-------------|
| `moirai_demo` | Interactive multi-turn demo (`max_turns => infinity`) with summarize-on-exit; supports one-shot mode via `run(#{prompt => ...})` and MCP mode via `run_with_mcp/0` or `run(#{mcp_repos => [...]})` |
| `moirai_tools` | Tool definitions: `echo_input` (synthetic), `list_directory` and `read_file` (sandboxed filesystem with traversal protection) |
| `moirai_mcp_config` | Guardrail module for gitmcp.io access. Hardcoded allow-list of repos (moirai, erl_openrouter, erl_mcp, klotho). Validates URLs before client start. |

### Tests

| Module | Description |
|--------|-------------|
| `moirai_integration_SUITE` | CT suite with two groups: `llm_tests` (end-to-end filesystem demo, gated on OPENROUTER_API_KEY) and `mcp_tests` (gitmcp.io tool discovery, gated on network access) |
| `moirai_mcp_config_tests` | EUnit tests for the guardrail module: allow-list count, URL construction, allow/block validation |

## Dependencies

- `erl_openrouter` (git) -- LLM transport, runtime + compile dep
- `klotho` (via `_checkouts/`) -- tool-use loop orchestrator,
  runtime + compile dep
- `erl_mcp` (via `_checkouts/`) -- MCP protocol client; runtime dep.
  Provides `erl_mcp_client` for connecting to remote MCP servers
  (gitmcp.io) over HTTP streamable transport.

## Key Design Decisions

1. **Single OTP application, not umbrella** -- The harness IS the demo.
   No separation needed until a second scenario grows complex enough
   to warrant isolation.

2. **openrouter_client started by erl_openrouter's own app, klotho_agent one-shot** --
   The LLM client is long-lived (connection pool, circuit breaker)
   and is booted by `openrouter_sup` when erl_openrouter starts via
   the OTP applications dependency. moirai_sup does NOT start it
   directly -- doing so would collide on the registered name.
   Agent workers are per-task ephemeral processes started by the
   demo, not supervised here.

3. **klotho via _checkouts/** -- Active development uses local source.
   Switch to a pinned git ref once klotho tags a release.

4. **Integration test gated on env var** -- No mock tests of the
   agent loop (that would exercise klotho, violating the test-posture
   rule). Compile + dialyzer + integration is the coverage strategy.

5. **Teaching surface via inline comments** -- Tool definitions and
   the agent config build in moirai_demo are intentionally verbose
   with explanatory comments. These are blog post anchor code.

6. **MCP clients are per-demo ephemeral** -- Like klotho_agent,
   erl_mcp_client processes are started by the demo and stopped
   when it ends. Not supervised by moirai_sup.

7. **Guardrailed gitmcp.io access** -- moirai_mcp_config hardcodes
   the four Erlang agent stack repos as the only allowed targets.
   The demo agent cannot query arbitrary GitHub repos.

## Conventions

- `warnings_as_errors` is enabled in rebar.config
- No catch-all clauses that silently swallow errors
- Prefer returning `{error, Reason}` tuples over throwing
- Binary strings for all protocol-level data (tool names, etc.)
- Mirror klotho's Makefile, Dockerfile, and CI patterns
