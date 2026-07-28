# moirai

[![CI](https://github.com/otakup0pe/moirai/actions/workflows/ci.yml/badge.svg)](https://github.com/otakup0pe/moirai/actions/workflows/ci.yml)
[![Maintenance](https://img.shields.io/maintenance/yes/2026.svg)](https://github.com/otakup0pe/moirai)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Reference harness wiring
[erl_openrouter](https://github.com/otakup0pe/erl_openrouter) +
[erl_mcp](https://github.com/otakup0pe/erl_mcp) +
[klotho](https://github.com/otakup0pe/klotho) into a runnable,
citable, teachable artifact.

Named after the Greek Fates collectively -- klotho spins the thread,
the moirai are the assembled whole.

## What This Is

moirai is a learning artifact, not a production application. It
demonstrates how to wire an Erlang/OTP LLM agent stack
end-to-end:

1. An `openrouter_client` lives under a supervisor (long-lived)
2. A `klotho_agent` is started per-task as a one-shot process
3. Tool definitions are concrete `#klotho_tool{}` records in a
   dedicated module
4. The agent loop drives LLM calls, dispatches tool calls, and
   returns a result with a full step trace
5. Remote MCP tools from [gitmcp.io](https://gitmcp.io) are
   bridged into the same agent via `klotho_mcp`, mixing local
   and remote tools seamlessly

## Dependency Tree

```
moirai
├── erl_openrouter   (LLM transport -- OpenRouter API client)
├── erl_mcp          (MCP protocol client and server)
└── klotho           (tool-use loop orchestrator)
    └── erl_openrouter
```

## Requirements

Docker. It's all in a container.

## Running the Demo

The demo wires a klotho_agent some sandboxed filesystem tools and an
external MCP.  You need an OpenRouter API key for the LLM call.

The two points of entry are

* `make demo` to bring up an interactive demo
* `make shell` to invoke beam shell directly

### Interactive Mode (multi-turn, summarize on exit)

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
make demo
```

This starts an interactive loop — type messages at the `moirai>`
prompt. The agent uses `list_directory` and `read_file` to explore
`priv/demo_files/` and answer your questions. It uses the
`search_*_code` and `fetch_*_documentation` MCP tools to access
documentation on `erl_openrouter`, `erl_mcp`, `klotho`, and `moirai` -
the four components of this little ecosystem.

Type `quit` or `exit` (or send EOF) to end the session. Before
stopping, the agent generates a brief summary of the conversation.

### One-shot Mode

Open the interactive erlang shell and invoke `moirai_demo:run/1` directly.

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
make shell
```

```erlang

moirai_demo:run(#{prompt => <<"List the project files.">>}).
```

Sends a single prompt, prints the result, and returns
`{ok, #klotho_result{}}`.

### MCP Mode (local + remote tools)

# gadget note - THIS NEEDS UPDATE?

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
make shell

# In the Erlang shell:
moirai_demo:run_with_mcp().
```

This connects to [gitmcp.io](https://gitmcp.io) over HTTP
streamable MCP transport for all four repos in the Erlang agent
stack (moirai, erl_openrouter, erl_mcp, klotho). The agent gets
both the local filesystem tools and the remote GitHub
documentation/code-search tools. An internal guardrail
(`moirai_mcp_config`) restricts which repos can be queried.

You can also select specific repos:

```erlang
moirai_demo:run(#{
    mcp_repos => [<<"otakup0pe/moirai">>, <<"otakup0pe/klotho">>]
}).
```

### Options

```erlang
moirai_demo:run(#{
    model     => <<"google/gemma-3-27b-it">>,  %% default
    prompt    => <<"...">>,       %% set for one-shot; omit for interactive
    verbose   => true,            %% print step trace (default: true)
    sandbox   => "/path/to/dir", %% sandbox root (default: priv/demo_files)
    mcp_repos => [binary()]       %% gitmcp.io repos (default: [])
}).
```

## Testing

All targets run in docker by default. `local-*` variants run on
the host for users with OTP 27 + rebar3 installed locally.

```
make compile       # docker compile
make test          # docker eunit + common_test
make dialyzer      # docker dialyzer
make shell         # docker rebar3 shell
```

The integration test suite (`moirai_integration_SUITE`) has two
groups:

- **llm_tests** -- end-to-end filesystem demo. Requires
  `OPENROUTER_API_KEY`. Skipped automatically if not set.
- **mcp_tests** -- gitmcp.io tool discovery. Requires outbound
  HTTPS. Skips gracefully if gitmcp.io is unreachable.

```bash
OPENROUTER_API_KEY=sk-or-v1-... make test
```

## Reference Stack

- [erl_openrouter](https://github.com/otakup0pe/erl_openrouter) -- LLM transport with tool use
- [erl_mcp](https://github.com/otakup0pe/erl_mcp) -- MCP protocol client and server
- [klotho](https://github.com/otakup0pe/klotho) -- tool-use loop orchestrator
- **moirai** (this repo) -- end-to-end harness wiring all three

## Blog Series

TODO: Links to blog posts will be added as the series is published.

## Note on AI Usage

This project has been developed with AI assistance. Contributions making
use of AI generated content are welcome, however they _must_ be human
reviewed prior to submission as pull requests, or issues. All contributors
must be able to fully explain and defend any AI generated code,
documentation, issues, or tests they submit. Contributions making use of
AI must have this explicitly declared in the pull request or issue. This
also applies to utilization of AI for reviewing of pull requests.

## Feedback

Open an issue at https://github.com/otakup0pe/moirai/issues

## License

Apache-2.0. See [LICENSE](LICENSE).
