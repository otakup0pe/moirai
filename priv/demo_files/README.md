# Demo Project

A small weather lookup service used as a fixture corpus for the
moirai interactive demo.

## Structure

- `src/` — Source modules
- `docs/` — Design notes

## Purpose

This fixture corpus exists so the moirai demo agent has something
to explore with the `list_directory` and `read_file` tools. The
files are small and self-contained.

## Running

```erlang
weather:forecast(<<"tokyo">>).
%% => #{temp => 24, condition => <<"sunny">>}
```
