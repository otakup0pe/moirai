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
    with_visible_path(SandboxRoot, RelPath,
        fun(Path, _GitPath, Rules) ->
            case file:list_dir(Path) of
                {ok, Entries} ->
                    Visible = visible_entries(
                        SandboxRoot, Path, lists:sort(Entries), Rules),
                    Lines = lists:map(fun(E) ->
                        EntryPath = filename:join(Path, E),
                        case filelib:is_dir(EntryPath) of
                            true -> [E, "/"];
                            false -> E
                        end
                    end, Visible),
                    {ok, iolist_to_binary(lists:join("\n", Lines))};
                {error, enoent} ->
                    {error, <<"Directory not found: ", RelPath/binary>>};
                {error, enotdir} ->
                    {error, <<"Not a directory: ", RelPath/binary>>};
                {error, Reason} ->
                    {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
            end
        end);
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
    with_visible_path(SandboxRoot, RelPath,
        fun(Path, _GitPath, _Rules) ->
            case file:read_file(Path) of
                {ok, Content} ->
                    {ok, Content};
                {error, enoent} ->
                    {error, <<"File not found: ", RelPath/binary>>};
                {error, eisdir} ->
                    {error, <<"Path is a directory, not a file: ",
                              RelPath/binary>>};
                {error, Reason} ->
                    {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
            end
        end);
read_file_handler(_SandboxRoot, _Args) ->
    {error, {missing_required_field, <<"path">>}}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

with_visible_path(SandboxRoot, RelPath, Fun) ->
    case resolve_sandboxed_path(SandboxRoot, RelPath) of
        {error, _} = Error ->
            Error;
        {ok, Path, GitPath} ->
            case moirai_gitignore:load(canonical_root(SandboxRoot)) of
                {ok, Rules} ->
                    case git_ignore_status(Path, GitPath, Rules) of
                        ignored ->
                            {error, <<"Path excluded by .gitignore: ",
                                      RelPath/binary>>};
                        visible ->
                            Fun(Path, GitPath, Rules)
                    end;
                {error, Reason} ->
                    {error, <<"Unable to evaluate .gitignore: ",
                              Reason/binary>>}
            end
    end.

visible_entries(SandboxRoot, Path, Entries, Rules) ->
    lists:filter(
        fun(Entry) ->
            EntryPath = filename:join(Path, Entry),
            GitPath = relative_from_root(
                canonical_root(SandboxRoot), EntryPath),
            git_ignore_status(EntryPath, GitPath, Rules) =:= visible
        end,
        Entries).

git_ignore_status(Path, GitPath, Rules) ->
    case filename:split(GitPath) of
        [".git" | _] ->
            ignored;
        _ ->
            Kind = case filelib:is_dir(Path) of
                true -> directory;
                false -> file
            end,
            case moirai_gitignore:ignored(GitPath, Kind, Rules) of
                true -> ignored;
                false -> visible
            end
    end.

resolve_sandboxed_path(SandboxRoot, RelPath) ->
    AbsRoot = canonical_root(SandboxRoot),
    case filelib:safe_relative_path(path_to_list(RelPath), AbsRoot) of
        unsafe ->
            {error, <<"Path traversal blocked: ", RelPath/binary>>};
        "." ->
            {ok, AbsRoot, "."};
        SafePath ->
            Canonical = filename:join(AbsRoot, SafePath),
            {ok, Canonical, relative_from_root(AbsRoot, Canonical)}
    end.

canonical_root(SandboxRoot) ->
    Components = filename:split(
        filename:absname(path_to_list(SandboxRoot))),
    filename:join([Component || Component <- Components,
                                Component =/= "."]).

relative_from_root(Root, Root) ->
    ".";
relative_from_root(Root, Path) ->
    Prefix = Root ++ "/",
    string:slice(Path, length(Prefix)).

path_to_list(Path) when is_list(Path) ->
    Path;
path_to_list(Path) when is_binary(Path) ->
    binary_to_list(Path).
