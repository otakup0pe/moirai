# Design Notes

## Overview

The weather service provides a simple lookup from location name
to current conditions. It is deliberately minimal -- a teaching
example, not a production service.

## Data Model

Each forecast returns a map with two keys:

- `temp` -- integer, degrees Celsius
- `condition` -- binary string (e.g. `<<"sunny">>`, `<<"cloudy">>`)

Unknown locations return a default forecast (`20C, unknown`).

## Limitations

- No real data source; forecasts are hardcoded
- No error handling for malformed input
- Location matching is case-sensitive and exact
