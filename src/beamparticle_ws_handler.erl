%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% @end
%%% %CopyrightBegin%
%%%
%%% Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
%%% All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% %CopyrightEnd%
%%%-------------------------------------------------------------------
-module(beamparticle_ws_handler).
-author("neerajsharma").

%-behaviour(cowboy_http_handler).
%-behaviour(cowboy_websocket_handler).

-include("beamparticle_constants.hrl").

%% API

-export([init/2]).
-export([
  websocket_handle/2,
  websocket_info/2
]).

%% This is the default nlp-function-prefix
-define(DEFAULT_TEXT_FUNCTION_PREFIX, <<"nlpfn">>).

%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    %% Note that the passed on State is a list, so use it as proplist
    case beamparticle_auth:authenticate_user(Req, websocket) of
        {true, _, _} ->
            Opts = #{
              idle_timeout => 86400000},  %% 24 hours
            State2 = [{calltrace, false} | State],
            {cowboy_websocket, Req, State2, Opts};
        _ ->
            Req2 = cowboy_req:reply(
                     401,
                     #{<<"content-type">> => <<"text/html">>,
                       <<"www-authenticate">> => <<"basic realm=\"beamparticle\"">>},
                     Req),
            {ok, Req2, State}
    end.

%handle(Req, State) ->
%  lager:debug("Request not expected: ~p", [Req]),
%  {ok, Req2} = cowboy_http_req:reply(404, [{'Content-Type', <<"text/html">>}]),
%  {ok, Req2, State}.

%% In case you need to initialize use websocket_init/1 instead
%% of init/2.
%%websocket_init(State) ->
%%  lager:info("init websocket"),
%%  {ok, State}.

websocket_handle({text, <<".save ", Text/binary>>}, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
websocket_handle({text, <<".write ", Text/binary>>}, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
websocket_handle({text, <<".open ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
websocket_handle({text, <<".edit ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
websocket_handle({text, <<".log open ", Text/binary>>}, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
websocket_handle({text, <<".hist open ", Text/binary>>}, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
websocket_handle({text, <<".help">>}, State) ->
    handle_help_command(State);
websocket_handle({text, <<".help ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_help_command(FullFunctionName, State);
websocket_handle({text, <<".deps ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_deps_command(FullFunctionName, State);
websocket_handle({text, <<".uses ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_uses_command(FullFunctionName, State);
websocket_handle({text, <<".reindex functions">>}, State) ->
    handle_reindex_functions_command(State);
websocket_handle({text, <<".whatis explain ", Text/binary>>}, State) ->
    WhatIsText = beamparticle_util:trimbin(Text),
    handle_whatis_explain_command(WhatIsText, State);
websocket_handle({text, <<".whatis save ", Text/binary>>}, State) ->
    [Name, Body] = binary:split(Text, <<"\n">>),
    Name = beamparticle_util:trimbin(Name),
    handle_whatis_save_command(Name, Body, State);
websocket_handle({text, <<".whatis delete ", Text/binary>>}, State) ->
    Name = beamparticle_util:trimbin(Text),
    handle_whatis_delete_command(Name, State);
websocket_handle({text, <<".whatis list ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_whatis_list_command(Prefix, State);
websocket_handle({text, <<".whatis list">>}, State) ->
    handle_whatis_list_command(<<>>, State);
websocket_handle({text, <<".delete ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
websocket_handle({text, <<".remove ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
websocket_handle({text, <<".purge ", Text/binary>>}, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
websocket_handle({text, <<".destroy ", Text/binary>>}, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
websocket_handle({text, <<".run ", Text/binary>>}, State) ->
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Text),
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<".execute ", Text/binary>>}, State) ->
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Text),
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<".runeditor ", Text/binary>>}, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    [_, Expressions] = binary:split(Text, <<"\n">>),
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Expressions),
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<".runeditor\n", Expressions/binary>>}, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Expressions),
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<".ls">>}, State) ->
    handle_list_command(State);
websocket_handle({text, <<".list">>}, State) ->
    handle_list_command(State);
websocket_handle({text, <<".ls ", Text/binary>>}, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
websocket_handle({text, <<".list ", Text/binary>>}, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
websocket_handle({text, <<".log ls">>}, State) ->
    handle_log_list_command(<<>>, State);
websocket_handle({text, <<".log list">>}, State) ->
    handle_log_list_command(<<>>, State);
websocket_handle({text, <<".log list ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<".log ls ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<".hist ls">>}, State) ->
    handle_log_list_command(<<>>, State);
websocket_handle({text, <<".hist list">>}, State) ->
    handle_log_list_command(<<>>, State);
websocket_handle({text, <<".hist list ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<".hist ls ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<".hist ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<".listbackup">>}, State) ->
    handle_listbackup_command(disk, State);
websocket_handle({text, <<".backup">>}, State) ->
    handle_backup_command(disk, State);
websocket_handle({text, <<".backup ", _Text/binary>>}, State) ->
    handle_backup_command(disk, State);
websocket_handle({text, <<".restore ", Text/binary>>}, State) ->
    DateText = beamparticle_util:trimbin(Text),
    handle_restore_command(DateText, disk, State);
websocket_handle({text, <<".atomics fun restore ", Text/binary>>}, State) ->
    VersionText = beamparticle_util:trimbin(Text),
    handle_restore_command(VersionText, atomics, State);
websocket_handle({text, <<".network fun restore ", Text/binary>>}, State) ->
    Url = beamparticle_util:trimbin(Text),
    handle_restore_command({archive, Url}, network, State);
websocket_handle({text, <<".ping">>}, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
websocket_handle({text, <<".ping ">>}, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
websocket_handle({text, <<".test">>}, State) ->
    handle_test_command(<<"image">>, State);
websocket_handle({text, <<".test ", Msg/binary>>}, State) ->
    handle_test_command(Msg, State);
websocket_handle({text, <<".ct">>}, State) ->
    handle_toggle_calltrace_command(State);
websocket_handle({text, Text}, State) ->
    handle_freetext(Text, State);
websocket_handle(_Any, State) ->
  {reply, {text, << "what?" >>}, State, hibernate}.

websocket_info({timeout, _Ref, Msg}, State) ->
  {reply, {text, Msg}, State, hibernate};
websocket_info(_Info, State) ->
  lager:debug("websocket info"),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% @private
%% @doc Save a function with a given name
handle_save_command(FunctionName, FunctionBody, State) ->
    try
        case binary:split(FunctionName, <<"/">>) of
            [<<>>] ->
                erlang:throw({error, invalid_function_name});
            [_] ->
                ok;
            [_ | _] ->
                erlang:throw({error, invalid_function_name})
        end,
        F = beamparticle_erlparser:evaluate_expression(binary_to_list(FunctionBody)),
        case is_function(F) of
            true ->
                {arity, Arity} = erlang:fun_info(F, arity),
                Msg = <<>>,
                ArityBin = list_to_binary(integer_to_list(Arity)),
                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                TrimmedFunctionBody = beamparticle_util:trimbin(FunctionBody),
                %% save function in the cluster
                {_ResponseList, BadNodes} =
                    rpc:multicall([node() | nodes()],
                                  beamparticle_storage_util,
                                  write,
                                  [FullFunctionName,
                                   TrimmedFunctionBody,
                                   function]),
                HtmlResponse = case BadNodes of
                                   [] ->
                                       list_to_binary(
                                           io_lib:format("The function ~s/~p looks good to me.",
                                                         [FunctionName, Arity]));
                                   _ ->
                                       list_to_binary(io_lib:format(
                                           "Function ~s/~p looks good, but <b>could not write to nodes: <p style='color:red'>~p</p></b>",
                                           [FunctionName, Arity, BadNodes]))
                               end,
                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
            false ->
                case F of
                    {php, PhpCode} ->
                        case beamparticle_phpparser:validate_php_function(PhpCode) of
                            {ok, Arity} ->
                                ArityBin = integer_to_binary(Arity),
                                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                                TrimmedFunctionBody = beamparticle_util:trimbin(FunctionBody),
                                Msg = <<>>,
                                %% save function in the cluster
                                {_ResponseList, BadNodes} =
                                    rpc:multicall([node() | nodes()],
                                                  beamparticle_storage_util,
                                                  write,
                                                  [FullFunctionName,
                                                   TrimmedFunctionBody,
                                                   function]),
                                HtmlResponse = case BadNodes of
                                                   [] ->
                                                       list_to_binary(
                                                           io_lib:format("The function ~s/~p looks good to me.",
                                                                         [FunctionName, Arity]));
                                                   _ ->
                                                       list_to_binary(io_lib:format(
                                                           "Function ~s/~p looks good, but <b>could not write to nodes: <p style='color:red'>~p</p></b>",
                                                           [FunctionName, Arity, BadNodes]))
                                               end,
                                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
                            {error, ErrorResponse} ->
                                Msg2 = <<"It is not a valid PHP function! Error = ", ErrorResponse/binary>>,
                                HtmlResponse2 = <<"">>,
                                {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
                        end;
                    _ ->
                        Msg = <<"It is not a valid Erlang/Elixir/Efene function!">>,
                        HtmlResponse = <<"">>,
                        {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
                end
        end
    catch
        throw:{error, invalid_function_name} ->
            Msg3 = <<"The function name has '/' which is not allowed. Please remove '/' and try again!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate};
        _Class:_Error ->
            Msg3 = <<"It is not a valid Erlang/Elixir/Efene/PHP function!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate}
    end.

%% @private
%% @doc Get function definition with the given name
handle_open_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = beamparticle_storage_util:read(FullFunctionName, function),
    case KvResp of
        {ok, FunctionBody} ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            ErlCode = FunctionBody,
            HtmlResponse = <<"">>,
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            ErlCode = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate}
    end.

%% @private
%% @doc Get historic definition of a function
handle_log_open_command(FullHistoricFunctionName, State) when is_binary(FullHistoricFunctionName) ->
    KvResp = beamparticle_storage_util:read(FullHistoricFunctionName, function_history),
    case KvResp of
        {ok, FunctionBody} ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            ErlCode = FunctionBody,
            HtmlResponse = <<"">>,
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            ErlCode = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate}
    end.

%% @private
%% @doc What are the special commands available to me
handle_help_command(State) ->
    Commands = [{<<".<save | write> <name>/<arity>">>,
                 <<"Save a function with a given name.">>},
                {<<".<open | edit> <name>/<arity>">>,
                 <<"Get function definition with the given name.">>},
                {<<".<log open | hist open> <name>/<arity>-<uuid>">>,
                 <<"Get historic definition of a function.">>},
                {<<".ct">>,
                 <<"Toggle call trace, which allows call tracing in websocket.">>},
                {<<".help">>,
                 <<"This help.">>},
                {<<".help <name>/<arity>">>,
                 <<"Show what the function is supposed to do.">>},
                {<<".deps <name>/<arity>">>,
                 <<"Show the list of functions invoked by the given function.">>},
                {<<".uses <name>/<arity>">>,
                 <<"Show the list of functions which invokes the given function.">>},
                {<<".reindex functions">>,
                 <<"Reindex function dependencies and uses.">>},
                {<<".whatis explain <term>">>,
                 <<"Explain the purpose of a given terminology.">>},
                {<<".whatis save <term>">>,
                 <<"Save explaination of a given terminology from editor window.">>},
                {<<".whatis list">>,
                 <<"List all the whatis words available in the knowledgebase.">>},
                {<<".whatis list <prefix>">>,
                 <<"List all whatis words starting with prefix available in the knowledgebase.">>},
                {<<".whatis delete <term>">>,
                 <<"Delete a whatis word from the knowledgebase.">>},
                {<<".<delete | remove> <name>/<arity>">>,
                 <<"Delete function from knowledgebase but retain its history (DANGEROUS).">>},
                {<<".<purge | destory> <name>/<arity>">>,
                 <<"Delete function from knowledgebase along with its history (VERY DANGEROUS).">>},
                {<<".<run | execute> <Erlang Expression>">>,
                 <<"Evaluate (compile and run) an Erlang expression.">>},
                {<<".runeditor">>,
                 <<"Evaluate (compile and run) Erlang expressions (DONT write '.' dot at the end) in the code editor.">>},
                {<<".<ls | list>">>,
                 <<"List all the functions available in the knowledgebase.">>},
                {<<".<ls | list> <prefix>">>,
                 <<"List functions starting with prefix in the knowledgebase.">>},
                {<<".<log | hist> <list | ls>">>,
                 <<"List all historic versions of all functions.">>},
                {<<".<log | hist> <list | ls> <prefix>">>,
                 <<"List all historic versions functions starting with prefix.">>},
                {<<".listbackup">>,
                 <<"List all backups of the knowledgebase on disk.">>},
                {<<".backup">>,
                 <<"Backup knowledgebase of all functions and histories to disk.">>},
                {<<".restore">>,
                 <<"Restore knowledgebase of all functions and histories from disk.">>},
                {<<".atomics fun restore <version>">>,
                 <<"Restore knowledgebase of all functions from atomics store, where version is say v0.1.0  (see <a href=\"https://github.com/beamparticle/beamparticle-atomics/releases\">releases</a>)">>},
                {<<".network fun restore <http(s)-get-url>">>,
                 <<"Restore knowledgebase of all functions from network http(s) GET url">>},
                {<<".test">>,
                 <<"Send a test responce for UI testing.">>},
                {<<".ping">>,
                 <<"Is the server alive?">>},
                {<<"...">>,
                 <<"Handle generic text which is outside regular command.">>}],
    R1 = [[<<"<tr><td><b>">>, beamparticle_util:escape(X), <<"</b></td><td>">>, Y, <<"</td></tr>">>] || {X, Y} <- Commands],
    HtmlTablePrefix = [<<"<table id='newspaper-c'><thead>">>,
                       <<"<tr><th scope='col'>Command</th>">>,
                       <<"<th scope='col'>Description</th></tr></thead><tbody>">>],
    HtmlResponse = iolist_to_binary([HtmlTablePrefix, R1, <<"</tbody></table>">>]),
    {reply, {text, jsx:encode([{<<"speak">>, <<"">>}, {<<"text">>, <<"">>}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, <<"">>}])}, State, hibernate}.

%% @private
%% @doc Show what the function is supposed to do
handle_help_command(<<>>, State) ->
    handle_help_command(State);
handle_help_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = beamparticle_storage_util:read(FullFunctionName, function),
    case KvResp of
        {ok, FunctionBody} ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            ErlCode = FunctionBody,
            %%lager:info("ErlCode = ~p", [ErlCode]),
            Comments = beamparticle_erlparser:extract_comments(ErlCode),
            {Msg, HtmlResponse} = case Comments of
                                      [] ->
                                          {<<"No documentation available for ", FullFunctionName/binary>>, <<"">>};
                                      _ ->
                                          CommentWithHtmlBreak = [["<tr><td>", beamparticle_util:escape(X), "</td></tr>"] || X <- Comments],
                                          FunHelp = iolist_to_binary(lists:flatten(CommentWithHtmlBreak)),
                                          HtmlTablePrefix = [<<"<table id='newspaper-c'><thead>">>,
                                                             <<"<tr><th scope='col'>">>, FullFunctionName, <<"</th>">>,
                                                             <<"</tr></thead><tbody>">>],
                                          HtmlR = iolist_to_binary([HtmlTablePrefix, FunHelp, <<"</tbody></table>">>]),
                                          {<<"">>, HtmlR}
                           end,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

handle_deps_command(<<>>, State) ->
    HtmlResponse = <<"">>,
    Msg = <<"I dont know what you are talking about.">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
handle_deps_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = beamparticle_storage_util:function_deps(FullFunctionName),
    case KvResp of
        {ok, FunctionCalls} ->
            Msg = <<>>,
            FormatFn = fun({M, F, Arity}) ->
                               [M, <<":">>, F, <<"/">>, integer_to_binary(Arity)];
                          ({F, Arity}) ->
                               [F, <<"/">>, integer_to_binary(Arity)]
                       end,
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead>">>,
                               <<"<tr><th scope='col'>">>, FullFunctionName, <<"</th>">>,
                               <<"</tr></thead><tbody>">>],
            FunList = [[<<"<tr><td>">>, FormatFn(X), <<"</td></tr>">>] || X <- FunctionCalls],
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, FunList, <<"</tbody></table>">>]),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

handle_uses_command(<<>>, State) ->
    HtmlResponse = <<"">>,
    Msg = <<"I dont know what you are talking about.">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
handle_uses_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = beamparticle_storage_util:function_uses(FullFunctionName),
    case KvResp of
        {ok, FunctionCalls} ->
            Msg = <<>>,
            FormatFn = fun({M, F, Arity}) ->
                               [M, <<":">>, F, <<"/">>, integer_to_binary(Arity)];
                          ({F, Arity}) ->
                               [F, <<"/">>, integer_to_binary(Arity)]
                       end,
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead>">>,
                               <<"<tr><th scope='col'>">>, FullFunctionName, <<"</th>">>,
                               <<"</tr></thead><tbody>">>],
            FunList = [[<<"<tr><td>">>, FormatFn(X), <<"</td></tr>">>] || X <- FunctionCalls],
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, FunList, <<"</tbody></table>">>]),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

handle_reindex_functions_command(State) ->
    Resp = beamparticle_storage_util:reindex_function_usage(<<>>),
    HtmlResponse = <<"">>,
    Msg = list_to_binary(io_lib:format("~p", [Resp])),
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Explain any given terminology
handle_whatis_explain_command(Text, State) ->
    {Msg, HtmlResponse} = case explain_word(Text) of
                              {error, not_found} ->
                                  {<<"I dont know anything about '", Text/binary, "'">>, <<>>};
                              Meaning ->
                                  HtmlTablePrefix = [<<"<table id='newspaper-c'><thead>">>,
                                                     <<"<tr><th scope='col'>">>, Text, <<"</th>">>,
                                                     <<"</tr></thead><tbody>">>],
                                  Explaination = [<<"<tr><td>">>, Meaning, <<"</td></tr>">>],
                                  Hr = iolist_to_binary([HtmlTablePrefix, Explaination, <<"</tbody></table>">>]),

                                  {<<>>, Hr}
                          end,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Save whatis with a given name
handle_whatis_save_command(Name, Body, State) ->
    Msg = <<>>,
    TrimmedBody = beamparticle_util:trimbin(Body),
    true = beamparticle_storage_util:write(Name, TrimmedBody, whatis),
    %% save function in the cluster
    {_ResponseList, BadNodes} =
        rpc:multicall([node() | nodes()],
                      beamparticle_storage_util,
                      write,
                      [Name, TrimmedBody, whatis]),
    HtmlResponse = case BadNodes of
                       [] ->
                           <<"I have saved whatis '", Name/binary, "' in my knowledgebase.">>;
                       _ ->
                           list_to_binary(io_lib:format(
                               "<b>could not write to nodes: <p style='color:red'>~p</p></b>",
                               [BadNodes]))
                   end,

    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Delete whatis from knowledgebase
handle_whatis_delete_command(Name, State) when is_binary(Name) ->
    %% TODO delete in cluster (though this is dangerous)
    KvResp = beamparticle_storage_util:delete(Name, whatis),
    case KvResp of
        true ->
            HtmlResponse = <<"">>,
            Msg = <<"I have erased that whatis knowledge if I had one.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            %% delete always gives true so this case will never
            %% be invoked
            HtmlResponse = <<"">>,
            Msg = <<"I dont know that yet, so cannot forget.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

%% @private
%% @doc List whatis starting with prefix in the knowledgebase
handle_whatis_list_command(Prefix, State) ->
    Resp = beamparticle_storage_util:similar_whatis(Prefix),
    case Resp of
        [] ->
            HtmlResponse = <<"">>,
            Msg = case Prefix of
                      <<>> -> <<"I know nothing yet.">>;
                      _ -> <<"Dont know anything starting with ", Prefix/binary>>
                  end,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            Title = case Prefix of
                        <<>> ->
                            <<"Whatis">>;
                        _ ->
                            <<"Whatis like ", Prefix/binary, "*">>
                    end,
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                               <<"<th scope='col'>">>, Title, <<"</th>">>,
                               <<"</tr></thead><tbody>">>],
            HtmlTableBody = [ [<<"<tr><td>">>, X, <<"</td></tr>">>] || X <- Resp],
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.


%% @private
%% @doc Delete function from knowledgebase but retain its history
handle_delete_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    %% TODO delete in cluster (though this is dangerous)
    KvResp = beamparticle_storage_util:delete(FullFunctionName, function),
    case KvResp of
        true ->
            HtmlResponse = <<"">>,
            Msg = <<"I have erased that knowledge if I had one.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            %% delete always gives true so this case will never
            %% be invoked
            HtmlResponse = <<"">>,
            Msg = <<"I dont know that yet, so cannot forget.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

%% @private
%% @doc Delete function from knowledgebase along with its history
handle_purge_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    %% TODO delete in cluster (though this is dangerous)
	FunctionHistories = beamparticle_storage_util:function_history(FullFunctionName),
	lists:foreach(fun(E) ->
                          beamparticle_storage_util:delete(E, function_history)
                  end, FunctionHistories),
    KvResp = beamparticle_storage_util:delete(FullFunctionName, function),
    case KvResp of
        true ->
            HtmlResponse = <<"">>,
            Msg = <<"I have erased that knowledge if I had one.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            %% delete always gives true so this case will never
            %% be invoked
            HtmlResponse = <<"">>,
            Msg = <<"I dont know that yet, so cannot forget.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

%% @private
%% @doc Evaluate (compile and run) an Erlang expression
handle_run_command(FunctionBody, State) when is_binary(FunctionBody) ->
    try
        T = erlang:monotonic_time(micro_seconds),
        case proplists:get_value(calltrace, State, false) of
            true ->
                erlang:put(?CALL_TRACE_KEY, []),
                erlang:put(?CALL_TRACE_BASE_TIME, T);
            false ->
                ok
        end,
        Result = beamparticle_dynamic:get_result(FunctionBody),
        case proplists:get_value(calltrace, State, false) of
            true ->
                CallTrace = erlang:get(?CALL_TRACE_KEY),
                erlang:erase(?CALL_TRACE_KEY),
                CallTraceResp = beamparticle_erlparser:calltrace_to_json_map(CallTrace),
                %% CallTraceResp = list_to_binary(io_lib:format("~p", [CallTrace])),
                T1 = erlang:monotonic_time(micro_seconds),
                {reply, {text, jsx:encode([{calltractime_usec, T1 - T}, {calltrace, CallTraceResp} |  Result])}, State, hibernate};
            false ->
                T1 = erlang:monotonic_time(micro_seconds),
                {reply, {text, jsx:encode([{calltractime_usec, T1 - T} |  Result])}, State, hibernate}
        end
    catch
        Class:Error ->
            Msg2 = list_to_binary(io_lib:format("Error: ~p:~p, stacktrace = ~p", [Class, Error, erlang:get_stacktrace()])),
            HtmlResponse2 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
    end.

%% @private
%% @doc List all the functions available in the knowledgebase
handle_list_command(State) ->
    handle_list_command(<<>>, State).

%% @private
%% @doc List functions starting with prefix in the knowledgebase
handle_list_command(Prefix, State) ->
    Resp = beamparticle_storage_util:similar_functions_with_doc(Prefix),
    case Resp of
        [] ->
            HtmlResponse = <<"">>,
            Msg = case Prefix of
                      <<>> -> <<"I know nothing yet.">>;
                      _ -> <<"Dont know anything starting with ", Prefix/binary>>
                  end,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            CommentToHtmlFn = fun(<<>>) ->
                                      <<>>;
                                 (CommentConstruct) ->
                                      OrigComment = CommentConstruct,
                                      %% get rid of "% @doc" if
                                      %% present for nice display
                                      Comment = re:replace(OrigComment, "^ *%+ *@doc", "", [{return, list}]),
                                      iolist_to_binary(beamparticle_util:escape(Comment))
                              end,
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                               <<"<th scope='col'>Function/Arity</th><th scope='col'>Purpose</th>">>,
                               <<"</tr></thead><tbody>">>],
            HtmlTableBody = [ [<<"<tr><td>">>, X, <<"</td><td>">>, CommentToHtmlFn(Y), <<"</td></tr>">>] || {X, Y} <- Resp],
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

%% @private
%% @doc List all historic versions of a given function
handle_log_list_command(Prefix, State) when is_binary(Prefix) ->
	Resp = beamparticle_storage_util:similar_function_history(Prefix),
    case Resp of
        [] ->
            HtmlResponse = <<"">>,
            Msg = <<"There is no history for given function prefix.">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            GetDateOfCreationFn = fun(X) ->
                                          Xstr = binary_to_list(X),
                                          [_, UuidString] = string:split(Xstr, "-", trailing),
                                          UuidBin = beamparticle_util:hex_binary_to_bin(list_to_binary(UuidString)),
                                          list_to_binary(uuid:get_v1_datetime(UuidBin))
                                  end,
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                               <<"<th scope='col'>Function/Arity-Uuid</th><th scope='col'>Date of Creation</th>">>,
                               <<"</tr></thead><tbody>">>],
            HtmlTableBody = [ [<<"<tr><td>">>, X, <<"</td><td>">>, GetDateOfCreationFn(X), <<"</td></tr>">>] || X <- Resp],
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
            %% HtmlResponse = iolist_to_binary([<<"<pre>">>, lists:join(<<", ">>, Resp), <<"</pre>">>]),
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end.

%% @private
%% @doc List all backups of the knowledgebase on disk
handle_listbackup_command(disk, State) ->
    TarGzFilenames = beamparticle_storage_util:get_function_snapshots(),
    HistoryTarGzFilenames = beamparticle_storage_util:get_function_history_snapshots(),
    WhatisTarGzFilenames = beamparticle_storage_util:get_whatis_snapshots(),
    JobTarGzFilenames = beamparticle_storage_util:get_job_snapshots(),
    HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                       <<"<th scope='col'>Type</th><th scope='col'>Filename</th>">>,
                       <<"</tr></thead><tbody>">>],
    BodyFunctions = [ [<<"<tr><td>Function</td><td>">>, X, <<"</td></tr>">>] || X <- TarGzFilenames],
    BodyFunctionHistories = [ [<<"<tr><td>Function History</td><td>">>, X, <<"</td></tr>">>] || X <- HistoryTarGzFilenames],
    BodyWhatis = [ [<<"<tr><td>Whatis</td><td>">>, X, <<"</td></tr>">>] || X <- WhatisTarGzFilenames],
    BodyJob = [ [<<"<tr><td>Job</td><td>">>, X, <<"</td></tr>">>] || X <- JobTarGzFilenames],
    HtmlTableBody = [BodyFunctions, BodyFunctionHistories, BodyWhatis, BodyJob],
    HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Backup knowledgebase of all functions and histories to disk
handle_backup_command(disk, State) ->
    NowDateTime = calendar:now_to_datetime(erlang:timestamp()),
    {ok, TarGzFilename} =
        beamparticle_storage_util:create_function_snapshot(NowDateTime),
    {ok, HistoryTarGzFilename} =
        beamparticle_storage_util:create_function_history_snapshot(NowDateTime),
    {ok, WhatisTarGzFilename} =
        beamparticle_storage_util:create_whatis_snapshot(NowDateTime),
    {ok, JobTarGzFilename} =
        beamparticle_storage_util:create_job_snapshot(NowDateTime),
    Resp = [list_to_binary(TarGzFilename),
            list_to_binary(HistoryTarGzFilename),
            list_to_binary(WhatisTarGzFilename),
            list_to_binary(JobTarGzFilename)],
    HtmlResponse = iolist_to_binary([<<"<pre>">>, lists:join(<<", ">>, Resp), <<"</pre>">>]),
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Restore knowledgebase of all functions and histories from disk
handle_restore_command(DateText, disk, State) ->
    TarGzFilename = binary_to_list(DateText) ++ "_archive.tar.gz",
    HistoryTarGzFilename = binary_to_list(DateText) ++ "_archive_history.tar.gz",
    WhatisTarGzFilename = binary_to_list(DateText) ++ "_archive_whatis.tar.gz",
    JobTarGzFilename = binary_to_list(DateText) ++ "_archive_job.tar.gz",
    ImportResp = beamparticle_storage_util:import_functions(file, TarGzFilename),
    HistoryImportResp = beamparticle_storage_util:import_functions_history(HistoryTarGzFilename),
    WhatisImportResp = beamparticle_storage_util:import_whatis(file, WhatisTarGzFilename),
    JobImportResp = beamparticle_storage_util:import_job(file, JobTarGzFilename),
    HtmlResponse = <<"">>,
    Msg = list_to_binary(io_lib:format("Function import ~p, history import ~p, whatis import ~p, job import ~p",
                                       [ImportResp, HistoryImportResp, WhatisImportResp, JobImportResp])),
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
handle_restore_command(Version, atomics, State) when is_binary(Version) ->
    %% Example:
    %% https://github.com/beamparticle/beamparticle-atomics/archive/v0.1.0.tar.gz
    %% IMPORTANT: Skip Function config_setup_all_config_env/0 or
    %%            config_setup_all_config_env-0.erl.fun because
    %%            This is definitely customized and user do not want
    %%            to overwrite this (for sure).
    case Version of
        <<>> ->
            Msg = <<"Empty reference given, so cannot import">>,
            HtmlResponse = <<>>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            VersionStr = binary_to_list(Version),
            NetworkUrl = "https://github.com/beamparticle/beamparticle-atomics/archive/" ++ VersionStr ++ ".tar.gz",
            ImportResp = beamparticle_storage_util:import_functions(
                           network, {NetworkUrl, ["config_setup_all_config_env-0"]}),
            HtmlResponse = <<"">>,
            Msg = list_to_binary(io_lib:format("Function import ~p. Note that 'config_setup_all_config_env/0' is NOT overwritten.", [ImportResp])),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
    end;
handle_restore_command({archive, Url}, network, State) when is_binary(Url) orelse is_list(Url) ->
    %% Only allow archive, but no history, no whatis and tar.gz archive files
    UrlStr = case is_binary(Url) of
                 true ->
                     binary_to_list(Url);
                 false ->
                     Url
             end,
    ImportResp = beamparticle_storage_util:import_functions(network, {UrlStr, []}),
    HtmlResponse = <<"">>,
    Msg = list_to_binary(io_lib:format("Function import ~p", [ImportResp])),
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Send a test responce for UI testing
handle_test_command(<<"image">> = Msg, State) ->
  HtmlResponse = <<"<img src='/static/images/paris.jpg' class='img-responsive img-rounded'/>">>,
  %%{reply, {text, << "responding to ", Msg/binary >>}, State, hibernate};
  {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
handle_test_command(Msg, State) ->
  HtmlResponse = <<"<div>", Msg/binary, "</div>">>,
  %%{reply, {text, << "responding to ", Msg/binary >>}, State, hibernate}.
  {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Toggle call tracing
handle_toggle_calltrace_command(State) ->
    NewCallTrace = not proplists:get_value(calltrace, State, false),
    NewCallTraceState = case NewCallTrace of
                         true ->
                             <<"on">>;
                         false ->
                             <<"off">>
                     end,
    Msg = <<"call trace is now switched ", NewCallTraceState/binary>>,
    HtmlResponse = <<>>,
    State2 = proplists:delete(calltrace, State),
    State3 = [{calltrace, NewCallTrace} | State2], 
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State3, hibernate}.

%% @private
%% @doc Handle generic text which is outside regular command
handle_freetext(Text, State) ->
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         throw({{ok, R}, S2});
                     %% must have single arity only
                     <<"nlpfn", Krest/binary>> = ExtractedKey ->
                         lager:info("ExtractedKey=~p", [ExtractedKey]),
                         KnameLen = byte_size(Krest) - 2,
                         case Krest of
                             <<_:KnameLen/binary, "/1">> ->
                                 {[{ExtractedKey, V} | R], S2};
                             _ ->
                                 {R, S2}
                         end;
                     _ ->
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, ?DEFAULT_TEXT_FUNCTION_PREFIX, function),
    case Resp of
        [] ->
            HtmlResponse = list_to_binary(io_lib:format("Please teach me some variant say ~shello or ~swhat-is-your-name, etc such that ~s*(<<\"~s\">>) works", [?DEFAULT_TEXT_FUNCTION_PREFIX, ?DEFAULT_TEXT_FUNCTION_PREFIX, ?DEFAULT_TEXT_FUNCTION_PREFIX, Text])),
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            get_answer(Resp, Text, State)
    end.

%% @private
%% @doc Generate response for given erlang expression.
%%
%% This function shall evaluate the given expression as
%% a binary and reply with appropriate response, which
%% can be sent directly over websocket.
%%
get_answer([], _Text, State) ->
    HtmlResponse = <<"I dont have a clue what that means. Please teach me.">>,
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
get_answer([{_K, V} | Rest], Text, State) ->
    FunctionBody = V,
    try
        F = beamparticle_erlparser:evaluate_expression(binary_to_list(FunctionBody)),
        %% TODO we know that arity of this function is 1
        case is_function(F, 1) of
            true ->
                case apply(F, [Text]) of
                    {error, _} ->
                        get_answer(Rest, Text, State);
                    Result ->
                        lager:info("Result = ~p", [Result]),
                        PropResult = beamparticle_dynamic:transform_result(Result),
                        SpeakMsg = proplists:get_value(<<"speak">>, PropResult, <<>>),
                        TextMsg = proplists:get_value(<<"text">>, PropResult, <<>>),
                        HtmlMsg = proplists:get_value(<<"html">>, PropResult, <<>>),
                        JsonMsg = proplists:get_value(<<"json">>, PropResult, <<>>),
                        {reply, {text, jsx:encode([{<<"speak">>, SpeakMsg},
                                                   {<<"text">>, TextMsg},
                                                   {<<"html">>, HtmlMsg},
                                                   {<<"json">>, JsonMsg}])}, State, hibernate}
                end;
            false ->
                case F of
                    {php, PhpCode} ->
                        beamparticle_phpparser:evaluate_php_expression(
                          PhpCode, []);
                    _ ->
                        get_answer(Rest, Text, State)
                end
        end
    catch
        _Class:_Error ->
            get_answer(Rest, Text, State)
    end.

%%explain_word(<<"arity">>) ->
%%    [<<"Arity is the number of arguments (numeric value) accepted by a function">>];
%%explain_word(_) ->
%%    {error, not_found}.
explain_word(Text) ->
    case beamparticle_storage_util:read(Text, whatis) of
        {ok, Data} ->
            Data;
        _ ->
            {error, not_found}
    end.
