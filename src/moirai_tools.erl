-module(moirai_tools).

-include_lib("klotho/include/klotho.hrl").

-export([echo_tool/0, list_directory_tool/1, read_file_tool/1]).

%% @doc Synthetic echo tool for Phase 1 demos.
echo_tool() ->
    #klotho_tool{
        name = <<"echo_input">>,
        description = <<"Echoes the provided text back verbatim. "
                        "Use this tool when the user asks you to echo or repeat something.">>,
        input_schema = #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"text">> => #{
                    <<"type">> => <<"string">>,
                    <<"description">> => <<"The text to echo back">>
                }
            },
            <<"required">> => [<<"text">>]
        },
        handler = fun echo_handler/1
    }.

echo_handler(#{<<"text">> := Text}) ->
    {ok, Text};
echo_handler(_Args) ->
    {error, {missing_required_field, <<"text">>}}.

%% @doc List files in a directory within the sandbox root.
list_directory_tool(SandboxRoot) ->
    #klotho_tool{
        name = <<"list_directory">>,
        description = <<"Lists files and subdirectories at a given path "
                        "relative to the project root. Returns one entry "
                        "per line. Use this to explore the file tree.">>,
        input_schema = #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"path">> => #{
                    <<"type">> => <<"string">>,
                    <<"description">> => <<"Relative path to list (use \".\" for root)">>
                }
            },
            <<"required">> => [<<"path">>]
        },
        handler = fun(Args) -> list_directory_handler(SandboxRoot, Args) end
    }.

list_directory_handler(SandboxRoot, #{<<"path">> := RelPath}) ->
    FullPath = resolve_sandboxed_path(SandboxRoot, RelPath),
    case FullPath of
        {error, _} = Err -> Err;
        Path ->
            case file:list_dir(Path) of
                {ok, Entries} ->
                    Sorted = lists:sort(Entries),
                    Lines = lists:map(fun(E) ->
                        EntryPath = filename:join(Path, E),
                        case filelib:is_dir(EntryPath) of
                            true -> [E, "/"];
                            false -> E
                        end
                    end, Sorted),
                    {ok, iolist_to_binary(lists:join("\n", Lines))};
                {error, enoent} ->
                    {error, <<"Directory not found: ", RelPath/binary>>};
                {error, enotdir} ->
                    {error, <<"Not a directory: ", RelPath/binary>>};
                {error, Reason} ->
                    {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
            end
    end;
list_directory_handler(_SandboxRoot, _Args) ->
    {error, {missing_required_field, <<"path">>}}.

%% @doc Read a file within the sandbox root.
read_file_tool(SandboxRoot) ->
    #klotho_tool{
        name = <<"read_file">>,
        description = <<"Reads the contents of a file at a given path "
                        "relative to the project root. Returns the file "
                        "contents as text.">>,
        input_schema = #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"path">> => #{
                    <<"type">> => <<"string">>,
                    <<"description">> => <<"Relative path to the file to read">>
                }
            },
            <<"required">> => [<<"path">>]
        },
        handler = fun(Args) -> read_file_handler(SandboxRoot, Args) end
    }.

read_file_handler(SandboxRoot, #{<<"path">> := RelPath}) ->
    FullPath = resolve_sandboxed_path(SandboxRoot, RelPath),
    case FullPath of
        {error, _} = Err -> Err;
        Path ->
            case file:read_file(Path) of
                {ok, Content} ->
                    {ok, Content};
                {error, enoent} ->
                    {error, <<"File not found: ", RelPath/binary>>};
                {error, eisdir} ->
                    {error, <<"Path is a directory, not a file: ", RelPath/binary>>};
                {error, Reason} ->
                    {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
            end
    end;
read_file_handler(_SandboxRoot, _Args) ->
    {error, {missing_required_field, <<"path">>}}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

resolve_sandboxed_path(SandboxRoot, RelPath) ->
    Candidate = filename:join(SandboxRoot, RelPath),
    Canonical = filename:absname(Candidate),
    AbsRoot = filename:absname(SandboxRoot),
    case string:prefix(Canonical, AbsRoot) of
        nomatch ->
            {error, <<"Path traversal blocked: ", RelPath/binary>>};
        _Rest ->
            Canonical
    end.
