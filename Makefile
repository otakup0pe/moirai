ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all compile docker-compile local-compile \
        test docker-test local-test local-eunit local-ct \
        dialyzer docker-dialyzer local-dialyzer \
        shell docker-shell local-shell \
        demo docker-demo local-demo \
        upgrade \
        docker-build resolve-checkouts clean

REBAR3 ?= rebar3
CHECKOUTS_OVERRIDE = docker-compose.checkouts.yml
COMPOSE ?= docker compose -f docker-compose.test.yml -f $(CHECKOUTS_OVERRIDE)

# All Erlang invocations run in docker by default. The local-* targets
# exist for power users who already have OTP 27 + rebar3 on the host.

all: compile

compile: docker-compile
test: docker-test
dialyzer: docker-dialyzer
shell: docker-shell
demo: docker-demo

# Generate a docker-compose override that bind-mounts each
# _checkouts/* symlink target at its real host path inside the
# container so the symlinks resolve. Run before any docker action.
resolve-checkouts:
	@sh scripts/resolve-checkouts > $(CHECKOUTS_OVERRIDE)

docker-build: resolve-checkouts
	$(COMPOSE) build

docker-compile: docker-build
	$(COMPOSE) run --rm test make local-compile

docker-test: docker-build
	$(COMPOSE) run --rm test

docker-dialyzer: docker-build
	$(COMPOSE) run --rm test make local-dialyzer

docker-shell: docker-build
	$(COMPOSE) run --rm test make local-shell

docker-demo: docker-build
	$(COMPOSE) run --rm test make local-demo

# `make upgrade`             -- bump every git dep to latest branch tip
# `make upgrade DEP=klotho`  -- bump just that dep
# Uses unlock + rm + deps + lock instead of `rebar3 upgrade` which
# silently no-ops for git branch deps. Follows morpheus pattern.
# See: memory://workflow/erlang-dep-management
upgrade: resolve-checkouts
	@if [ -z "$$SSH_AUTH_SOCK" ]; then \
		echo "ERROR: SSH_AUTH_SOCK not set. Start your ssh-agent first."; \
		exit 1; \
	fi
	@target='$(DEP)'; \
	if [ -z "$$target" ]; then \
		echo "Bumping all deps to latest allowed refs..."; \
		unlock_cmd='rebar3 unlock'; \
		rm_cmd='rm -rf _build/default/lib _build/test/lib'; \
	else \
		echo "Bumping $$target..."; \
		unlock_cmd="rebar3 unlock $$target"; \
		rm_cmd="rm -rf _build/default/lib/$$target _build/test/lib/$$target"; \
	fi; \
	$(COMPOSE) run --rm \
		-v $$SSH_AUTH_SOCK:/ssh-agent \
		-e SSH_AUTH_SOCK=/ssh-agent \
		test sh -c "$$unlock_cmd && $$rm_cmd && rebar3 deps && rebar3 lock"

local-compile:
	$(REBAR3) compile

local-test: local-eunit local-ct
	$(REBAR3) cover

local-eunit:
	$(REBAR3) eunit --sys_config conf/moirai-test.config

local-ct:
	$(REBAR3) ct --sys_config conf/moirai-test.config

local-dialyzer:
	$(REBAR3) dialyzer

local-shell:
	$(REBAR3) shell

local-demo:
	$(REBAR3) compile
	erl -pa _build/default/lib/*/ebin \
	    -pa _build/default/checkouts/*/ebin \
	    -noshell \
	    -eval "application:ensure_all_started(moirai), moirai_demo:run_with_mcp(), halt(0)."

clean:
	rm -rf _build $(CHECKOUTS_OVERRIDE)
