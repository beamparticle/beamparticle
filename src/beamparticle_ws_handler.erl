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
    case beamparticle_auth:authenticate_user(Req, websocket) of
        {true, _, _} ->
            Opts = #{
              idle_timeout => 86400000},  %% 24 hours
            {cowboy_websocket, Req, State, Opts};
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

websocket_handle({text, <<"save ", Text/binary>>}, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
websocket_handle({text, <<"write ", Text/binary>>}, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
websocket_handle({text, <<"open ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
websocket_handle({text, <<"edit ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
websocket_handle({text, <<"log open ", Text/binary>>}, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
websocket_handle({text, <<"hist open ", Text/binary>>}, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
websocket_handle({text, <<"help">>}, State) ->
    handle_help_command(State);
websocket_handle({text, <<"help ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_help_command(FullFunctionName, State);
websocket_handle({text, <<"whatis explain ", Text/binary>>}, State) ->
    WhatIsText = beamparticle_util:trimbin(Text),
    handle_whatis_explain_command(WhatIsText, State);
websocket_handle({text, <<"whatis save ", Text/binary>>}, State) ->
    [Name, Body] = binary:split(Text, <<"\n">>),
    Name = beamparticle_util:trimbin(Name),
    handle_whatis_save_command(Name, Body, State);
websocket_handle({text, <<"whatis delete ", Text/binary>>}, State) ->
    Name = beamparticle_util:trimbin(Text),
    handle_whatis_delete_command(Name, State);
websocket_handle({text, <<"whatis list ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_whatis_list_command(Prefix, State);
websocket_handle({text, <<"whatis list">>}, State) ->
    handle_whatis_list_command(<<>>, State);
websocket_handle({text, <<"delete ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
websocket_handle({text, <<"remove ", Text/binary>>}, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
websocket_handle({text, <<"purge ", Text/binary>>}, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
websocket_handle({text, <<"destroy ", Text/binary>>}, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
websocket_handle({text, <<"run ", Text/binary>>}, State) ->
    FunctionBody = <<"fun() -> ", Text/binary, "\nend.">>,
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<"execute ", Text/binary>>}, State) ->
    FunctionBody = <<"fun() -> ", Text/binary, "\nend.">>,
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<"runeditor ", Text/binary>>}, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    [_, Expressions] = binary:split(Text, <<"\n">>),
    FunctionBody = <<"fun() -> ", Expressions/binary, "\nend.">>,
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<"runeditor\n", Expressions/binary>>}, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    FunctionBody = <<"fun() -> ", Expressions/binary, "\nend.">>,
    handle_run_command(FunctionBody, State);
websocket_handle({text, <<"ls">>}, State) ->
    handle_list_command(State);
websocket_handle({text, <<"list">>}, State) ->
    handle_list_command(State);
websocket_handle({text, <<"ls ", Text/binary>>}, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
websocket_handle({text, <<"list ", Text/binary>>}, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
websocket_handle({text, <<"log list ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<"hist ", Text/binary>>}, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
websocket_handle({text, <<"listbackup">>}, State) ->
    handle_listbackup_command(disk, State);
websocket_handle({text, <<"backup">>}, State) ->
    handle_backup_command(disk, State);
websocket_handle({text, <<"backup ", _Text/binary>>}, State) ->
    handle_backup_command(disk, State);
websocket_handle({text, <<"restore ", Text/binary>>}, State) ->
    DateText = beamparticle_util:trimbin(Text),
    handle_restore_command(DateText, disk, State);
websocket_handle({text, <<"atomics fun restore ", Text/binary>>}, State) ->
    VersionText = beamparticle_util:trimbin(Text),
    handle_restore_command(VersionText, atomics, State);
websocket_handle({text, <<"network fun restore ", Text/binary>>}, State) ->
    Url = beamparticle_util:trimbin(Text),
    handle_restore_command({archive, Url}, network, State);
websocket_handle({text, <<"ping">>}, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
websocket_handle({text, <<"ping ">>}, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
websocket_handle({text, <<"test">>}, State) ->
    handle_test_command(<<"image">>, State);
websocket_handle({text, <<"test ", Msg/binary>>}, State) ->
    handle_test_command(Msg, State);
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
        F = beamparticle_erlparser:evaluate_erlang_expression(binary_to_list(FunctionBody)),
        case is_function(F) of
            true ->
                {arity, Arity} = erlang:fun_info(F, arity),
                Msg = list_to_binary(
                        io_lib:format("The function ~s/~p looks good to me.",
                                     [FunctionName, Arity])),
                HtmlResponse = <<"">>,
                ArityBin = list_to_binary(integer_to_list(Arity)),
                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                TrimmedFunctionBody = beamparticle_util:trimbin(FunctionBody),
                true = beamparticle_storage_util:write(FullFunctionName, TrimmedFunctionBody, function),
                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
            false ->
                Msg = <<"It is not a valid Erlang function!">>,
                HtmlResponse = <<"">>,
                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
        end
    catch
        throw:{error, invalid_function_name} ->
            Msg2 = <<"The function name has '/' which is not allowed. Please remove '/' and try again!">>,
            HtmlResponse2 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate};
        _Class:_Error ->
            Msg2 = <<"It is not a valid Erlang function!">>,
            HtmlResponse2 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
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
    Commands = [{<<"<save | write> <name>/<arity>">>,
                 <<"Save a function with a given name.">>},
                {<<"<open | edit> <name>/<arity>">>,
                 <<"Get function definition with the given name.">>},
                {<<"<log open | hist open> <name>/<arity>-<uuid>">>,
                 <<"Get historic definition of a function.">>},
                {<<"help">>,
                 <<"This help.">>},
                {<<"help <name>/<arity>">>,
                 <<"Show what the function is supposed to do.">>},
                {<<"whatis explain <term>">>,
                 <<"Explain the purpose of a given terminology.">>},
                {<<"whatis save <term>">>,
                 <<"Save explaination of a given terminology from editor window.">>},
                {<<"whatis list">>,
                 <<"List all the whatis words available in the knowledgebase.">>},
                {<<"whatis list <prefix>">>,
                 <<"List all whatis words starting with prefix available in the knowledgebase.">>},
                {<<"whatis delete <term>">>,
                 <<"Delete a whatis word from the knowledgebase.">>},
                {<<"<delete | remove> <name>/<arity>">>,
                 <<"Delete function from knowledgebase but retain its history (DANGEROUS).">>},
                {<<"<purge | destory> <name>/<arity>">>,
                 <<"Delete function from knowledgebase along with its history (VERY DANGEROUS).">>},
                {<<"<run | execute> <Erlang Expression>">>,
                 <<"Evaluate (compile and run) an Erlang expression.">>},
                {<<"runeditor">>,
                 <<"Evaluate (compile and run) Erlang expressions (DONT write '.' dot at the end) in the code editor.">>},
                {<<"<ls | list>">>,
                 <<"List all the functions available in the knowledgebase.">>},
                {<<"<ls | list> <prefix>">>,
                 <<"List functions starting with prefix in the knowledgebase.">>},
                {<<"<log | hist> list <prefix>">>,
                 <<"List all historic versions functions starting with prefix.">>},
                {<<"listbackup">>,
                 <<"List all backups of the knowledgebase on disk.">>},
                {<<"backup">>,
                 <<"Backup knowledgebase of all functions and histories to disk.">>},
                {<<"restore">>,
                 <<"Restore knowledgebase of all functions and histories from disk.">>},
                {<<"atomics fun restore <version>">>,
                 <<"Restore knowledgebase of all functions from atomics store, where version is say v0.1.0  (see <a href=\"https://github.com/beamparticle/beamparticle-atomics/releases\">releases</a>)">>},
                {<<"network fun restore <http(s)-get-url>">>,
                 <<"Restore knowledgebase of all functions from network http(s) GET url">>},
                {<<"test">>,
                 <<"Send a test responce for UI testing.">>},
                {<<"ping">>,
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
            Comments = lists:reverse(erl_comment_scan:scan_lines(binary_to_list(ErlCode))),
            {Msg, HtmlResponse} = case Comments of
                                      [] ->
                                          {<<"No documentation available for ", FullFunctionName/binary>>, <<"">>};
                                      _ ->
                                          CommentWithHtmlBreak = [["<tr><td>", beamparticle_util:escape(X), "</td></tr>"] || {_, _, _, X} <- Comments],
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
    Msg = <<"I have saved whatis '", Name/binary, "' in my knowledgebase.">>,
    HtmlResponse = <<"">>,
    TrimmedBody = beamparticle_util:trimbin(Body),
    true = beamparticle_storage_util:write(Name, TrimmedBody, whatis),
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Delete whatis from knowledgebase
handle_whatis_delete_command(Name, State) when is_binary(Name) ->
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
        erlang:put(?CALL_TRACE_KEY, []),
        T = erlang:monotonic_time(micro_seconds),
        erlang:put(?CALL_TRACE_BASE_TIME, T),
        Result = beamparticle_dynamic:get_result(FunctionBody),
        CallTrace = erlang:get(?CALL_TRACE_KEY),
        erlang:erase(?CALL_TRACE_KEY),
        CallTraceResp = beamparticle_erlparser:calltrace_to_json_map(CallTrace),
        %% CallTraceResp = list_to_binary(io_lib:format("~p", [CallTrace])),
        T1 = erlang:monotonic_time(micro_seconds),
        {reply, {text, jsx:encode([{calltractime_usec, T1 - T}, {calltrace, CallTraceResp} |  Result])}, State, hibernate}
    catch
        Class:Error ->
            Msg2 = list_to_binary(io_lib:format("Error: ~p:~p", [Class, Error])),
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
                                      {_, _, _, OrigComment} = CommentConstruct,
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
    HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                       <<"<th scope='col'>Type</th><th scope='col'>Filename</th>">>,
                       <<"</tr></thead><tbody>">>],
    BodyFunctions = [ [<<"<tr><td>Function</td><td>">>, X, <<"</td></tr>">>] || X <- TarGzFilenames],
    BodyFunctionHistories = [ [<<"<tr><td>Function History</td><td>">>, X, <<"</td></tr>">>] || X <- HistoryTarGzFilenames],
    BodyWhatis = [ [<<"<tr><td>Whatis</td><td>">>, X, <<"</td></tr>">>] || X <- WhatisTarGzFilenames],
    HtmlTableBody = [BodyFunctions, BodyFunctionHistories, BodyWhatis],
    HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Backup knowledgebase of all functions and histories to disk
handle_backup_command(disk, State) ->
    {ok, TarGzFilename} = beamparticle_storage_util:create_function_snapshot(),
    {ok, HistoryTarGzFilename} = beamparticle_storage_util:create_function_history_snapshot(),
    {ok, WhatisTarGzFilename} = beamparticle_storage_util:create_whatis_snapshot(),
    Resp = [list_to_binary(TarGzFilename),
            list_to_binary(HistoryTarGzFilename),
            list_to_binary(WhatisTarGzFilename)],
    HtmlResponse = iolist_to_binary([<<"<pre>">>, lists:join(<<", ">>, Resp), <<"</pre>">>]),
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Restore knowledgebase of all functions and histories from disk
handle_restore_command(DateText, disk, State) ->
    TarGzFilename = binary_to_list(DateText) ++ "_archive.tar.gz",
    HistoryTarGzFilename = binary_to_list(DateText) ++ "_archive_history.tar.gz",
    WhatisTarGzFilename = binary_to_list(DateText) ++ "_archive_whatis.tar.gz",
    ImportResp = beamparticle_storage_util:import_functions(file, TarGzFilename),
    HistoryImportResp = beamparticle_storage_util:import_functions_history(HistoryTarGzFilename),
    WhatisImportResp = beamparticle_storage_util:import_whatis(WhatisTarGzFilename),
    HtmlResponse = <<"">>,
    Msg = list_to_binary(io_lib:format("Function import ~p, history import ~p, whatis import ~p",
                                       [ImportResp, HistoryImportResp, WhatisImportResp])),
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
handle_restore_command(Version, atomics, State) when is_binary(Version) ->
    %% Example:
    %% https://github.com/beamparticle/beamparticle-atomics/archive/v0.1.0.tar.gz
    case Version of
        <<>> ->
            Msg = <<"Empty reference given, so cannot import">>,
            HtmlResponse = <<>>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            VersionStr = binary_to_list(Version),
            NetworkUrl = "https://github.com/beamparticle/beamparticle-atomics/archive/" ++ VersionStr ++ ".tar.gz",
            handle_restore_command({archive, NetworkUrl}, network, State)
    end;
handle_restore_command({archive, Url}, network, State) when is_binary(Url) orelse is_list(Url) ->
    %% Only allow archive, but no history, no whatis and tar.gz archive files
    UrlStr = case is_binary(Url) of
                 true ->
                     binary_to_list(Url);
                 false ->
                     Url
             end,
    ImportResp = beamparticle_storage_util:import_functions(network, UrlStr),
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
        F = beamparticle_erlparser:evaluate_erlang_expression(binary_to_list(FunctionBody)),
        %% TODO we know that arity of this function is 1
        case is_function(F, 1) of
            true ->
                case apply(F, [Text]) of
                    {error, _} ->
                        get_answer(Rest, Text, State);
                    Result ->
                        lager:info("Result = ~p", [Result]),
                        {Msg, HtmlResponse} = case Result of
                                                  {direct, M} ->
                                                      {M, <<"">>};
                                                  {html, M} ->
                                                      {<<"">>, M};
                                                  _ ->
                                                      list_to_binary(
                                                        io_lib:format("The function returned ~p", [Result]))
                                              end,
                        {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
                end;
            false ->
                get_answer(Rest, Text, State)
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
