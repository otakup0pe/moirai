# moirai

[![CI](https://github.com/otakup0pe/moirai/actions/workflows/ci.yml/badge.svg)](https://github.com/otakup0pe/moirai/actions/workflows/ci.yml)
[![Maintenance](https://img.shields.io/maintenance/yes/2026.svg)](https://github.com/otakup0pe/moirai)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Moirai assembles an Erlang/OTP agent from
[erl_openrouter](https://github.com/otakup0pe/erl_openrouter),
[erl_mcp](https://github.com/otakup0pe/erl_mcp),
[klotho](https://github.com/otakup0pe/klotho), and
[Magicbeam](https://github.com/otakup0pe/magicbeam).

Named after the Greek Fates collectively: Klotho spins the thread;
the Moirai are the assembled whole.

## What it demonstrates

Moirai is a learning artifact, not a production application. The
application itself is the demo:

- erl_openrouter provides the supervised OpenRouter client
- Klotho owns the multi-turn tool-use loop
- erl_mcp discovers weather and repository tools asynchronously
- Shellbeam provides the interactive command shell
- local tools inspect the real Moirai checkout, not a fixture project

The weather MCP is an isolated
[Open-Meteo](https://open-meteo.com/) sidecar and needs no API key.
A GeoIP lookup contributes an approximate location to the initial
agent context. Both are optional: startup and local chat tools remain
available if either endpoint is slow or unavailable.

## Requirements

Docker and an OpenRouter API key:

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
make demo
```

The custom Shellbeam prompt accepts natural language directly. Its
built-in commands are:

- `tools` — show tools discovered so far
- `status` — show the model and background discovery state
- `reset` — discard the current conversation
- `help` — show shell help
- `quit` — summarize the conversation and leave the shell
- `exit` — leave immediately without a summary

Moirai starts the shell immediately with `list_directory` and
`read_file`. If background MCP discovery is still running, the first
chat waits for it before creating the Klotho agent so that weather and
repo-namespaced gitmcp.io tools remain available for the conversation.

For a regular Erlang shell:

```bash
make shell
```

One-shot use returns Klotho's result record:

```erlang
moirai:run(#{
    prompt => <<"Inspect this checkout and explain its OTP structure.">>,
    verbose => true
}).
```

Set `MOIRAI_PROJECT_ROOT`, `MOIRAI_GEOIP_URL`, or
`MOIRAI_WEATHER_MCP_URL` to override their defaults.

## Dependency tree

```text
moirai
├── erl_openrouter   OpenRouter transport
├── erl_mcp          MCP client
├── klotho           agent/tool-use loop
└── magicbeam
    ├── shellbeam    interactive shell
    ├── hotbeam      optional development reloads
    └── thunderbeam  optional supervision testing
```

Hotbeam and Thunderbeam ship with the dependency but remain disabled
by default.

## Testing

All standard targets run in Docker. The `local-*` variants require
OTP 27+ and rebar3. `make test` is the consolidated gate: EUnit,
runtime smoke, Dialyzer, coverage, Compose validation, and the
PTY/Edlin demo smoke test.

```bash
make compile
make test
make dialyzer
make shell
```

## Public-endpoint posture

The demo publishes no local ports. The weather container is read-only,
drops Linux capabilities, runs with `no-new-privileges`, and limits the
single private-network client to 30 requests per minute. Remote
weather, GeoIP, gitmcp.io, and OpenRouter services still receive the
minimum request metadata needed to answer; do not use the demo for
sensitive prompts or private source trees.

## Note on AI usage

This project has been developed with AI assistance. AI-assisted
contributions are welcome when they are human-reviewed, explicitly
declared, and the contributor can explain and defend them.

## License

Apache-2.0. See [LICENSE](LICENSE).
