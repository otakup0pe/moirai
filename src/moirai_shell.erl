-module(moirai_shell).
-behaviour(shellbeam).

-include_lib("klotho/include/klotho.hrl").

-export([commands/0, chat/1, tools/0, status/0, reset/0, quit/0]).

-ifdef(TEST).
-export([format_status/1, format_success/3]).
-endif.

commands() ->
    [
        {["tools"], "List currently available agent tools",
            fun ?MODULE:tools/0},
        {["status"], "Show model and asynchronous discovery status",
            fun ?MODULE:status/0},
        {["reset"], "Start a fresh agent conversation",
            fun ?MODULE:reset/0},
        {["quit"], "Summarize the conversation and exit",
            fun ?MODULE:quit/0},
        {[{"message", string}], "Chat with Moirai",
            fun ?MODULE:chat/1}
    ].

chat(Message) ->
    case moirai:chat(Message) of
        {ok, #klotho_result{
            status = ok,
            message = Reply,
            total_steps = Steps,
            elapsed_ms = Elapsed
        }} when is_binary(Reply) ->
            {Format, Args} = format_success(Reply, Steps, Elapsed),
            {ok, Format, Args};
        {ok, #klotho_result{
            status = Status,
            message = Reply,
            error = Reason
        }} ->
            {error, "~ts~n  status: ~p, reason: ~tp",
                [reply_text(Reply), Status, Reason]};
        {error, Reason} ->
            {error, "~tp", [Reason]}
    end.

tools() ->
    Names = moirai:tools(),
    {ok, "~ts", [lists:join("\n", Names)]}.

status() ->
    {ok, "~ts", [format_status(moirai:status())]}.

reset() ->
    ok = moirai:reset(),
    {ok, "Conversation reset."}.

quit() ->
    case moirai:summarize() of
        {ok, #klotho_result{
            status = ok,
            message = Summary,
            total_steps = Steps,
            elapsed_ms = Elapsed
        }} when is_binary(Summary) ->
            {Format, Args} = format_reply(
                "summary", Summary, Steps, Elapsed),
            {exit, Format, Args};
        {error, no_conversation} ->
            {exit, "Goodbye."};
        {ok, #klotho_result{
            status = Status,
            message = Summary,
            error = Reason
        }} ->
            {exit, "~ts~n  status: ~p, reason: ~tp",
                [reply_text(Summary), Status, Reason]};
        {error, Reason} ->
            {exit, "Unable to summarize: ~tp", [Reason]}
    end.

format_success(Reply, Steps, Elapsed) ->
    format_reply("moirai", Reply, Steps, Elapsed).

format_reply(Label, Reply, Steps, Elapsed) ->
    ColouredLabel = shellbeam:colour(cyan, Label),
    Footer = shellbeam:colour(
        dim,
        lists:flatten(io_lib:format(
            "[~B steps, ~Bms]", [Steps, Elapsed]))),
    {"~n~ts~n~ts~n  ~ts", [ColouredLabel, Reply, Footer]}.

format_status(#{
    model := Model,
    tools := Tools,
    discovery_pending := Pending,
    discovery_errors := Errors,
    agent_started := AgentStarted
}) ->
    [
        "Model: ", Model,
        "\nConversation: ", conversation_status(AgentStarted),
        "\nResources: ", resource_status(Pending, Errors),
        "\nTools: ", integer_to_list(length(Tools)), " available",
        "\nWarnings: ", warning_status(Errors)
    ].

conversation_status(true) -> "active";
conversation_status(false) -> "not started".

resource_status(Pending, _Errors) when Pending > 0 ->
    lists:flatten(io_lib:format(
        "connecting (~B pending)", [Pending]));
resource_status(0, []) ->
    "ready";
resource_status(0, _Errors) ->
    "ready with warnings".

warning_status([]) ->
    "none";
warning_status(Errors) ->
    lists:join(", ", [Label || {Label, _Reason} <- Errors]).

reply_text(undefined) -> <<"<no message>">>;
reply_text(Reply) when is_binary(Reply) -> Reply.
