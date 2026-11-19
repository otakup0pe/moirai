ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all compile docker-compile local-compile \
        test docker-test local-test local-eunit local-ct test-runtime-smoke local-runtime-smoke test-demo-config test-demo-pty \
        dialyzer docker-dialyzer local-dialyzer \
        shell docker-shell local-shell \
        demo docker-demo local-demo \
        dev-upgrade purge-zombie-deps lint-secrets \
        lint-secrets-staged docker-build resolve-checkouts clean

REBAR3 ?= rebar3
export HOST_UID ?= $(shell id -u)
export HOST_GID ?= $(shell id -g)
GITLEAKS_IMAGE ?= ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
GITLEAKS_MODE ?= git
GITLEAKS_SOURCE ?= .
GITLEAKS_FLAGS ?=
CHECKOUTS_OVERRIDE = docker-compose.checkouts.yml
COMPOSE ?= docker compose -f docker-compose.test.yml -f $(CHECKOUTS_OVERRIDE)
DEMO_COMPOSE = $(COMPOSE) -f docker-compose.demo.yml
RUNTIME_ERL_LIBS = $(ROOT_DIR)/_build/default/lib:$(ROOT_DIR)/_build/default/checkouts

# All Erlang invocations run in docker by default. The local-* targets
# exist for power users who already have OTP 27 + rebar3 on the host.

all: compile

compile: docker-compile
test: docker-test test-demo-config test-demo-pty
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

purge-zombie-deps: resolve-checkouts
	@$(COMPOSE) run --rm --no-deps -T --user 0:0 --entrypoint sh test \
		/app/scripts/purge-zombie-deps

docker-compile: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(COMPOSE) run --rm test make local-compile

docker-test: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(COMPOSE) run --rm test

test-demo-config: resolve-checkouts
	$(DEMO_COMPOSE) config -q

test-demo-pty: docker-build
	@log=$$(mktemp); trap 'rm -f "$$log"' 0; \
		(sleep 5; printf 'exitx\033[D\033[3~\n') | timeout 60s script -qec \
			'$(DEMO_COMPOSE) run --rm test make local-demo' "$$log" && \
		grep -Fq 'The Erlang/OTP agent stack' "$$log"

test-runtime-smoke: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(COMPOSE) run --rm test make local-runtime-smoke

docker-dialyzer: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(COMPOSE) run --rm test make local-dialyzer

docker-shell: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(COMPOSE) run --rm test make local-shell

docker-demo: docker-build
	@$(MAKE) -s purge-zombie-deps
	$(DEMO_COMPOSE) run --rm test make local-demo

# `make dev-upgrade` refreshes every git lock from rebar.config.
# `make dev-upgrade DEP=klotho` refreshes one dependency.
#
# `unlock --all` is required: rebar3 rejects the bare `unlock` form.
# The fail-fast chain prevents a failed unlock from falling through to a
# green lock command, and verify-erlang-lock reports the resulting refs.
dev-upgrade: resolve-checkouts
	@mkdir -p _build
	@sh scripts/verify-erlang-lock --snapshot > _build/rebar-lock.before
	@target='$(DEP)'; \
	if [ -z "$$target" ]; then \
		echo "Bumping all deps to latest allowed refs..."; \
		unlock_cmd='rebar3 unlock --all'; \
		rm_cmd='rm -rf _build/default/lib _build/default/checkouts _build/test/lib _build/test/checkouts'; \
	else \
		echo "Bumping $$target..."; \
		unlock_cmd="rebar3 unlock $$target"; \
		rm_cmd="rm -rf _build/default/lib/$$target _build/default/checkouts/$$target _build/test/lib/$$target _build/test/checkouts/$$target"; \
	fi; \
	$(COMPOSE) run --rm test sh -c \
		"$$unlock_cmd && $$rm_cmd && rebar3 deps && rebar3 lock"
	@rc=0; sh scripts/verify-erlang-lock --since _build/rebar-lock.before $(DEP) || rc=$$?; \
		rm -f _build/rebar-lock.before; \
		exit $$rc

lint-secrets:
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		--network none \
		--read-only \
		--cap-drop=ALL \
		--tmpfs /tmp:rw,noexec,nosuid,size=16m \
		-v "$(ROOT_DIR):/repo:ro" \
		-w /repo \
		$(GITLEAKS_IMAGE) $(GITLEAKS_MODE) $(GITLEAKS_SOURCE) $(GITLEAKS_FLAGS) --redact --no-banner --verbose

lint-secrets-staged: GITLEAKS_FLAGS := --pre-commit --staged
lint-secrets-staged: lint-secrets

local-compile:
	$(REBAR3) compile

local-test: local-eunit local-ct local-runtime-smoke local-dialyzer
	$(REBAR3) cover

local-eunit:
	$(REBAR3) eunit --sys_config conf/moirai-test.config

local-ct:
	$(REBAR3) ct --sys_config conf/moirai-test.config

local-dialyzer:
	$(REBAR3) dialyzer

local-shell:
	$(REBAR3) shell

local-runtime-smoke:
	@sh scripts/purge-zombie-deps
	$(REBAR3) compile
	@ERL_LIBS="$(RUNTIME_ERL_LIBS)" erl -noshell \
		-eval 'case application:ensure_all_started(moirai) of {ok, _} -> case whereis(openrouter_client) of Pid when is_pid(Pid) -> io:format("runtime smoke: ok~n"), halt(0); undefined -> io:format(standard_error, "openrouter_client not started~n", []), halt(1) end; {error, Reason} -> io:format(standard_error, "moirai start failed: ~p~n", [Reason]), halt(1) end.'

local-demo:
	@sh scripts/purge-zombie-deps
	$(REBAR3) compile
	@ERL_LIBS="$(RUNTIME_ERL_LIBS)" erl -noshell \
		-eval "case application:ensure_all_started(moirai) of {ok, _} -> case user_drv:start_shell(#{initial_shell => {moirai, spawn_shell, []}}) of ok -> Group = user_drv:whereis_group(), Ref = monitor(process, Group), receive {'DOWN', Ref, process, Group, normal} -> halt(0); {'DOWN', Ref, process, Group, ExitReason} -> io:format(standard_error, \"moirai shell exited: ~tp~n\", [ExitReason]), halt(1) end; {error, Reason} -> io:format(standard_error, \"moirai shell failed: ~p~n\", [Reason]), halt(1) end; {error, Reason} -> io:format(standard_error, \"moirai start failed: ~p~n\", [Reason]), halt(1) end."

clean:
	rm -rf _build $(CHECKOUTS_OVERRIDE)
