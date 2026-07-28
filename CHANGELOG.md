# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Remote MCP tool support** -- `moirai_demo:run_with_mcp/0` connects
  to gitmcp.io over HTTP streamable transport and makes GitHub
  documentation/code-search tools available alongside local filesystem
  tools in the same klotho agent. Uses `klotho_mcp:tools_from_client/2`
  bridge for tool conversion.
- **moirai_mcp_config** -- Guardrail module restricting gitmcp.io access
  to the four Erlang agent stack repos (moirai, erl_openrouter,
  erl_mcp, klotho).
- **mcp_tool_discovery** integration test -- CT test case verifying
  end-to-end MCP tool discovery against gitmcp.io (skips gracefully
  when network is unavailable).
- `erl_mcp` and `inets` added as runtime dependencies.
- **moirai_app** -- OTP application callback.
- **moirai_sup** -- Top-level supervisor (empty children list;
  openrouter_client is started by erl_openrouter's own supervision
  tree as a transitive application dependency).
- **moirai_tools** -- Tool definitions as `#klotho_tool{}` records:
  `echo_input` (synthetic echo), `list_directory` and `read_file`
  (sandboxed filesystem access with path-traversal protection).
- **moirai_demo** -- Interactive multi-turn demo and one-shot mode.
  Starts a klotho_agent with filesystem tools pointed at
  `priv/demo_files/`, loops on stdin via `klotho_agent:resume/2`
  with `max_turns => infinity`, and injects a summary prompt on
  quit/EOF before stopping the agent. One-shot mode (pass `prompt`
  in the options map) is used by the integration test.
- **moirai_integration_SUITE** -- Common Test suite for end-to-end
  verification using filesystem tools (gated on OPENROUTER_API_KEY
  env var).
- `priv/demo_files/` fixture corpus for the filesystem tools demo.
- Docker-based test infrastructure (Dockerfile.test,
  docker-compose.test.yml, Makefile targets).
- GitHub Actions CI workflow.
- README with setup, demo instructions, and reference stack links.
- AGENTS.md with module inventory and design decisions.
