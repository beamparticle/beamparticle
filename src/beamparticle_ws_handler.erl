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
  websocket_info/2,
  websocket_init/1
]).

-export([handle_run_command/2, run_query/3]).

%% This is the default nlp-function
-define(DEFAULT_NLP_FUNCTION, <<"nlpfn">>).

%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    Opts = #{
      idle_timeout => 86400000},  %% 24 hours
    %% userinfo must be a map of user meta information
    lager:debug("beamparticle_ws_handler:init(~p, ~p)", [Req, State]),
    Cookies = cowboy_req:parse_cookies(Req),
    Token = case lists:keyfind(<<"jwt">>, 1, Cookies) of
                {_, CookieJwtToken} -> CookieJwtToken;
                _ -> <<>>
            end,
    State2 = case Token of
                 <<>> ->
                    [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                 _ ->
                     JwtToken = string:trim(Token),
                     case beamparticle_auth:decode_jwt_token(JwtToken) of
                         {ok, Claims} ->
                             %% TODO validate jwt iss
                             #{<<"sub">> := Username} = Claims,
                             case beamparticle_auth:read_userinfo(Username, websocket, false) of
                                 {error, _} ->
                                     [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                                 UserInfo ->
                                     [{calltrace, false}, {userinfo, UserInfo}, {dialogue, []} | State]
                             end;
                         _ ->
                            [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State]
                     end
             end,
    {cowboy_websocket, Req, State2, Opts}.

%handle(Req, State) ->
%  lager:debug("Request not expected: ~p", [Req]),
%  {ok, Req2} = cowboy_http_req:reply(404, [{'Content-Type', <<"text/html">>}]),
%  {ok, Req2, State}.

%% In case you need to initialize use websocket_init/1 instead
%% of init/2.
websocket_init(State) ->
    %% Notice that init/2 is not called within the websocket actor,
    %% which websocket_init/1 is in the connected actor, so any
    %% changes to process dictionary here is correct.
    case beamparticle_config:save_to_production() of
        true ->
            erlang:put(?CALL_ENV_KEY, prod);
        false ->
            erlang:put(?CALL_ENV_KEY, stage)
    end,
    lager:debug("init websocket"),
    {ok, State}.

websocket_handle({text, Query}, State) ->
    run_query(fun handle_query/2, Query, State);
websocket_handle(Text, State) when is_binary(Text) ->
    %% sometimes the text is received directly as binary,
    %% so re-route it to core handler.
    websocket_handle({text, Text}, State);
websocket_handle(Any, State) ->
    AnyBin = list_to_binary(io_lib:format("~p", [Any])),
    Resp = <<"what did you mean by '", AnyBin/binary, "'?">>,
    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp}]),
    {reply, {text, Response}, State, hibernate}.

handle_query(<<".release">>, State) ->
    handle_release_command(State);
handle_query(<<".release ", _/binary>>, State) ->
    handle_release_command(State);
handle_query(<<".revert ", Text/binary>>, State) ->
    FunctionName = beamparticle_util:trimbin(Text),
    handle_revert_command(FunctionName, State);
handle_query(<<".diff ", Text/binary>>, State) ->
    FunctionName = beamparticle_util:trimbin(Text),
    handle_diff_command(FunctionName, State);
handle_query(<<".save ", Text/binary>>, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
handle_query(<<".write ", Text/binary>>, State) ->
    [Name, FunctionBody] = binary:split(Text, <<"\n">>),
    FunctionName = beamparticle_util:trimbin(Name),
    handle_save_command(FunctionName, FunctionBody, State);
handle_query(<<".open ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
handle_query(<<".edit ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_open_command(FullFunctionName, State);
handle_query(<<".config open ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_config_open_command(FullFunctionName, State);
handle_query(<<".config save ", Text/binary>>, State) ->
    %% <name>/<arity>
    [Name, Body] = binary:split(Text, <<"\n">>),
    FullFunctionName = beamparticle_util:trimbin(Name),
    handle_config_save_command(FullFunctionName, Body, State);
handle_query(<<".config ls">>, State) ->
    handle_config_list_command(<<>>, State);
handle_query(<<".config ls ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_config_list_command(Prefix, State);
handle_query(<<".config delete ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_config_save_command(FullFunctionName, <<>>, State);
handle_query(<<".log open ", Text/binary>>, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
handle_query(<<".hist open ", Text/binary>>, State) ->
    %% <name>/<arity>-<uuid>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_log_open_command(FullFunctionName, State);
handle_query(<<".help">>, State) ->
    handle_help_command(State);
handle_query(<<".help ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_help_command(FullFunctionName, State);
handle_query(<<".deps ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_deps_command(FullFunctionName, State);
handle_query(<<".uses ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_uses_command(FullFunctionName, State);
handle_query(<<".reindex functions">>, State) ->
    handle_reindex_functions_command(State);
handle_query(<<".whatis explain ", Text/binary>>, State) ->
    WhatIsText = beamparticle_util:trimbin(Text),
    handle_whatis_explain_command(WhatIsText, State);
handle_query(<<".whatis save ", Text/binary>>, State) ->
    [Name, Body] = binary:split(Text, <<"\n">>),
    Name = beamparticle_util:trimbin(Name),
    handle_whatis_save_command(Name, Body, State);
handle_query(<<".whatis delete ", Text/binary>>, State) ->
    Name = beamparticle_util:trimbin(Text),
    handle_whatis_delete_command(Name, State);
handle_query(<<".whatis list ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_whatis_list_command(Prefix, State);
handle_query(<<".whatis list">>, State) ->
    handle_whatis_list_command(<<>>, State);
handle_query(<<".delete ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
handle_query(<<".remove ", Text/binary>>, State) ->
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_delete_command(FullFunctionName, State);
handle_query(<<".purge ", Text/binary>>, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
handle_query(<<".destroy ", Text/binary>>, State) ->
    %% delete function with all history (DANGEROUS)
    %% <name>/<arity>
    FullFunctionName = beamparticle_util:trimbin(Text),
    handle_purge_command(FullFunctionName, State);
handle_query(<<".run ", Text/binary>>, State) ->
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Text),
    handle_run_command(FunctionBody, State);
handle_query(<<".execute ", Text/binary>>, State) ->
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Text),
    handle_run_command(FunctionBody, State);
handle_query(<<".runeditor ", Text/binary>>, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    [_, Expressions] = binary:split(Text, <<"\n">>),
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Expressions),
    handle_run_command(FunctionBody, State);
handle_query(<<".runeditor\n", Expressions/binary>>, State) ->
    %% NOTE: This function is for convinience to run
    %% code which is in the editor without creating a new function
    %% and not to be exposed to the client directly via help
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Expressions),
    handle_run_command(FunctionBody, State);
handle_query(<<".ls">>, State) ->
    handle_list_command(State);
handle_query(<<".list">>, State) ->
    handle_list_command(State);
handle_query(<<".ls ", Text/binary>>, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
handle_query(<<".list ", Text/binary>>, State) ->
    handle_list_command(beamparticle_util:trimbin(Text), State);
handle_query(<<".log ls">>, State) ->
    handle_log_list_command(<<>>, State);
handle_query(<<".log list">>, State) ->
    handle_log_list_command(<<>>, State);
handle_query(<<".log list ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
handle_query(<<".log ls ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
handle_query(<<".hist ls">>, State) ->
    handle_log_list_command(<<>>, State);
handle_query(<<".hist list">>, State) ->
    handle_log_list_command(<<>>, State);
handle_query(<<".hist list ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
handle_query(<<".hist ls ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
handle_query(<<".hist ", Text/binary>>, State) ->
    Prefix = beamparticle_util:trimbin(Text),
    handle_log_list_command(Prefix, State);
handle_query(<<".listbackup">>, State) ->
    handle_listbackup_command(disk, State);
handle_query(<<".backup">>, State) ->
    handle_backup_command(disk, State);
handle_query(<<".backup ", _Text/binary>>, State) ->
    handle_backup_command(disk, State);
handle_query(<<".restore ", Text/binary>>, State) ->
    DateText = beamparticle_util:trimbin(Text),
    handle_restore_command(DateText, disk, State);
handle_query(<<".atomics fun restore ", Text/binary>>, State) ->
    VersionText = beamparticle_util:trimbin(Text),
    handle_restore_command(VersionText, atomics, State);
handle_query(<<".network fun restore ", Text/binary>>, State) ->
    Url = beamparticle_util:trimbin(Text),
    handle_restore_command({archive, Url}, network, State);
handle_query(<<".ping">>, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
handle_query(<<".ping ">>, State) ->
  {reply, {text, << "pong">>}, State, hibernate};
handle_query(<<".test">>, State) ->
    handle_test_command(<<"image">>, State);
handle_query(<<".test ", Msg/binary>>, State) ->
    handle_test_command(Msg, State);
handle_query(<<".ct">>, State) ->
    handle_toggle_calltrace_command(State);
handle_query(Text, State) ->
    lager:info("Query: ~s", [Text]),
    FnName = ?DEFAULT_NLP_FUNCTION,
    SafeText = iolist_to_binary(string:replace(Text, <<"\"">>, <<>>, all)),
    NlpCall = <<FnName/binary, "(<<\"", SafeText/binary, "\">>)">>,
    FunctionBody = beamparticle_erlparser:create_anonymous_function(NlpCall),
    handle_run_command(FunctionBody, State).

websocket_info({timeout, _Ref, Msg}, State) ->
  {reply, {text, Msg}, State, hibernate};
websocket_info(_Info, State) ->
  lager:debug("websocket info"),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

handle_release_command(State) ->
    %% TODO It is not easy to selectively release only few of the
    %% functions.
    %% release all functions
    FunctionPrefix = <<>>,
    Type = function_stage,
    %% Resp = beamparticle_storage_util:similar_functions(Prefix, function_stage),
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, Type) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         {[{ExtractedKey, V} | R], S2};
                     _ ->
                         %% prefix no longer met, so return
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, Type),

    %% TODO send data to registered nodes and not
    %% just to available nodes, which is done at present
    Nodes = [node() | nodes()],
    FailureNodes = lists:foldl(fun({FullFunctionName, SourceCode}, AccIn) ->
                          {ResponseList, BadNodes} =
                          rpc:multicall(Nodes,
                                        beamparticle_storage_util,
                                        write,
                                        [FullFunctionName,
                                        SourceCode,
                                        function,
                                        true]),
                          RemainingNodes = Nodes -- BadNodes,
                          BadResponseNodes = lists:foldl(
                                               fun({NodeName, NodeResp}, AccIn2) ->
                                                       case NodeResp of
                                                           true ->
                                                               AccIn;
                                                           _ ->
                                                               lager:info("Node ~p failed to save function ~p, error = ~p", [NodeName, FullFunctionName, NodeResp]),
                                                               [NodeName | AccIn2]
                                                       end
                                               end,
                                               [],
                                               lists:zip(RemainingNodes,
                                                         ResponseList)),
                          TotalBadNodes = BadResponseNodes ++ BadNodes,
                          case TotalBadNodes of
                              [] ->
                                  %% remove staged version post release
                                  %% on best effort basis
                                  %% TODO check return value for errors
                                  rpc:multicall(Nodes,
                                                beamparticle_storage_util,
                                                delete,
                                                [FullFunctionName,
                                                function_stage]),

                                  AccIn;
                              _ ->
                                  %% do not delete unless all the nodes have functions
                                  %% in production
                                  TotalBadNodes ++ AccIn
                          end
                  end, [], Resp),
    UniqueFailureNodes = lists:usort(FailureNodes),
    Msg = case UniqueFailureNodes of
              [] ->
                  <<"Released staging to production.">>;
              _ ->
                  FailNodesBin = list_to_binary(
                                   io_lib:format("~p", [UniqueFailureNodes])),
                  <<"Release failed on the following nodes ", FailNodesBin/binary>>
          end,
    HtmlResponse = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Revert a staged function with a given name
handle_revert_command(FullFunctionName, State) ->
    try
        case binary:split(FullFunctionName, <<"/">>) of
            [<<>>] ->
                erlang:throw({error, invalid_function_name});
            [_] ->
                erlang:throw({error, invalid_function_name});
            [_ | _] ->
                ok
        end,
        Msg2 = case beamparticle_storage_util:delete(FullFunctionName,
                                                     function_stage) of
                   true ->
                       <<"Successfully reverted staged function ",
                         FullFunctionName/binary>>;
                   _ ->
                       <<"Function ",
                         FullFunctionName/binary, " is not staged.">>
               end,
        HtmlResponse2 = <<"">>,
        {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
    catch
        throw:{error, invalid_function_name} ->
            Msg3 = <<"The function name is missing has '/' which is mandatory.">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate}
    end.

%% @private
%% @doc Difference of a staged function versus production with a given name
handle_diff_command(FullFunctionName, State) ->
    try
        case binary:split(FullFunctionName, <<"/">>) of
            [<<>>] ->
                erlang:throw({error, invalid_function_name});
            [_] ->
                erlang:throw({error, invalid_function_name});
            [_ | _] ->
                ok
        end,
        {Msg2, HtmlResponse2} = case beamparticle_storage_util:read(
                                       FullFunctionName,
                                       function_stage) of
                                    {ok, StageFunctionBody} ->
                                        OrigCode = case beamparticle_storage_util:read(FullFunctionName, function) of
                                                       {ok, ProdFunctionBody} ->
                                                           ProdFunctionBody;
                                                       _ ->
                                                           <<"">>
                                                   end,
                                        Diff = tdiff:format_diff_lines(
                                          tdiff:diff_binaries(OrigCode, StageFunctionBody)),
                                        EscapedDiff = beamparticle_util:escape(
                                                        lists:flatten(Diff)),
                                        {<<"">>,
                                         iolist_to_binary([<<"<pre>">>,
                                                           list_to_binary(EscapedDiff),
                                                           <<"</pre>">>])};
                                    _ ->
                                        {<<"Function ",
                                          FullFunctionName/binary,
                                          " is not staged.">>, <<"">>}
                                end,
        {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
    catch
        throw:{error, invalid_function_name} ->
            Msg3 = <<"The function name is missing has '/' which is mandatory.">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate}
    end.


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
        %% TODO: dont save function_stage to cluster!
        FunctionType = get_function_type(),
        FResp = beamparticle_erlparser:evaluate_expression(FunctionBody),
        case FResp of
            {F, Config} when is_function(F) ->
                {arity, Arity} = erlang:fun_info(F, arity),
                Msg = <<>>,
                ArityBin = list_to_binary(integer_to_list(Arity)),
                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                TrimmedInputFunctionBody = beamparticle_util:trimbin(
                                             FunctionBody),
                TrimmedFunctionBody = case Config of
                                          <<>> ->
                                              merge_function_with_older_config(
                                                FullFunctionName, TrimmedInputFunctionBody);
                                          _ ->
                                              case validate_json_config(Config) of
                                                  true -> ok;
                                                  false -> erlang:throw(bad_config)
                                              end,
                                              TrimmedInputFunctionBody
                                      end,
                %% TODO: read the nodes from cluster configuration (in storage)
                %% because if any of the nodes is down then that will go
                %% unnoticed since the value of nodes() shall not have that
                %% node name (being down). Hence change
                %% beamparticle_cluster_monitor and start recoding new nodes
                %% in storage when available. NOTE: for removal this needs
                %% to be manual step.
                NodesToSave = case FunctionType of
                                  function -> [node() | nodes()];
                                  function_stage -> [node()]
                              end,
                %% save function in the cluster
                {_ResponseList, BadNodes} =
                    rpc:multicall(NodesToSave,
                                  beamparticle_storage_util,
                                  write,
                                  [FullFunctionName,
                                   TrimmedFunctionBody,
                                   FunctionType,
                                   true]),
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
            _ ->
                case FResp of
                    {php, PhpCode, Config, _CompileType} ->
                        case validate_json_config(Config) of
                            true -> ok;
                            false -> erlang:throw(bad_config)
                        end,
                        case beamparticle_phpparser:validate_php_function(PhpCode) of
                            {ok, Arity} ->
                                ArityBin = integer_to_binary(Arity),
                                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                                TrimmedInputFunctionBody = beamparticle_util:trimbin(FunctionBody),
                                TrimmedFunctionBody = case Config of
                                                          <<>> ->
                                                              merge_function_with_older_config(
                                                                FullFunctionName, TrimmedInputFunctionBody);
                                                          _ ->
                                                              case validate_json_config(Config) of
                                                                  true -> ok;
                                                                  false -> erlang:throw(bad_config)
                                                              end,
                                                              TrimmedInputFunctionBody
                                                      end,
                                Msg = <<>>,
                                %% save function in the cluster
                                {_ResponseList, BadNodes} =
                                    rpc:multicall([node() | nodes()],
                                                  beamparticle_storage_util,
                                                  write,
                                                  [FullFunctionName,
                                                   TrimmedFunctionBody,
                                                   FunctionType,
                                                   true]),
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
                    {ProgrammingLanguage, SourceCode, Config, _CompileType}
                      when ProgrammingLanguage == python orelse ProgrammingLanguage == java ->
                        {ParserM, ParserF} = case ProgrammingLanguage of
                                                 python ->
                                                     {beamparticle_pythonparser,
                                                      validate_python_function};
                                                 java ->
                                                     {beamparticle_javaparser,
                                                      validate_java_function}
                                             end,
                        case ParserM:ParserF(FunctionName, SourceCode) of
                            {ok, Arity} ->
                                ArityBin = integer_to_binary(Arity),
                                FullFunctionName = <<FunctionName/binary, $/, ArityBin/binary>>,
                                TrimmedInputFunctionBody = beamparticle_util:trimbin(FunctionBody),
                                TrimmedFunctionBody = case Config of
                                                          <<>> ->
                                                              merge_function_with_older_config(
                                                                FullFunctionName, TrimmedInputFunctionBody);
                                                          _ ->
                                                              case validate_json_config(Config) of
                                                                  true -> ok;
                                                                  false -> erlang:throw(bad_config)
                                                              end,
                                                              TrimmedInputFunctionBody
                                                      end,
                                Msg = <<>>,
                                %% save function in the cluster
                                {_ResponseList, BadNodes} =
                                    rpc:multicall([node() | nodes()],
                                                  beamparticle_storage_util,
                                                  write,
                                                  [FullFunctionName,
                                                   TrimmedFunctionBody,
                                                   FunctionType,
                                                   true]),
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
                                LanguageBin = atom_to_binary(ProgrammingLanguage, utf8),
                                Msg2 = <<"It is not a valid ", LanguageBin/binary,
                                         " function! Error = ", ErrorResponse/binary>>,
                                HtmlResponse2 = <<"">>,
                                {reply, {text, jsx:encode([{<<"speak">>, Msg2}, {<<"text">>, Msg2}, {<<"html">>, HtmlResponse2}])}, State, hibernate}
                        end;
                    _ ->
                        Msg = <<"It is not a valid Erlang/Elixir/Efene/Php/Python/Java function!">>,
                        HtmlResponse = <<"">>,
                        {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
                end
        end
    catch
        throw:{error, invalid_function_name} ->
            Msg3 = <<"The function name has '/' which is not allowed. Please remove '/' and try again!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate};
        throw:bad_config ->
            Msg3 = <<"Bad JSON configuration.">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate};
        _Class:_Error ->
            Msg3 = <<"It is not a valid Erlang/Elixir/Efene/PHP/Python/Java function!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate}
    end.

%% @private
%% @doc Get function definition with the given name
handle_open_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = read_function_with_fallback(FullFunctionName),
    case KvResp of
        {ok, FunctionBody} ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            {_, ErlCode} = beamparticle_erlparser:extract_config(FunctionBody),
            HtmlResponse = <<"">>,
            Msg = <<"">>,
            {LangAtom, _, _Config, _} = beamparticle_erlparser:detect_language(FunctionBody),
            Lang = atom_to_binary(LangAtom, utf8),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}, {<<"lang">>, Lang}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            ErlCode = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate}
    end.

%% @private
%% @doc Get function configuration with the given name
handle_config_open_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    KvResp = read_function_with_fallback(FullFunctionName),
    case KvResp of
        {ok, FunctionBody} ->
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            HtmlResponse = <<"">>,
            Msg = <<"">>,
            {LangAtom, _, Config, _} = beamparticle_erlparser:detect_language(
                                          FunctionBody),
            %% TODO: add a new category in json response, which must be
            %% configuration.
            %% There is no code, so emulate code with a configuration instead
            %% for now.
            ErlCode = Config,
            Lang = atom_to_binary(LangAtom, utf8),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}, {<<"lang">>, Lang}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            ErlCode = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate}
    end.

%% @private
%% @doc Save a function configuration with a given name
%% In order to delete a configuration, then pass Config as <<>>
handle_config_save_command(FullFunctionName, Config, State) ->
    try
        case binary:split(FullFunctionName, <<"/">>) of
            [_] ->
                erlang:throw({error, invalid_function_name});
            [_ | _] ->
                ok
        end,
        %% TODO: dont save function_stage to cluster!
        FunctionType = get_function_type(),
        case Config of
            <<>> ->
                ok;
            _ ->
               case validate_json_config(Config) of
                   true -> ok;
                   false -> erlang:throw(bad_config)
               end
        end,
        TrimmedFunctionBody = merge_function_with_new_config(
                                FullFunctionName, Config),
        case is_binary(TrimmedFunctionBody) of
            true ->
                %% TODO: read the nodes from cluster configuration (in storage)
                %% because if any of the nodes is down then that will go
                %% unnoticed since the value of nodes() shall not have that
                %% node name (being down). Hence change
                %% beamparticle_cluster_monitor and start recoding new nodes
                %% in storage when available. NOTE: for removal this needs
                %% to be manual step.
                NodesToSave = case FunctionType of
                                  function -> [node() | nodes()];
                                  function_stage -> [node()]
                              end,
                %% save function in the cluster
                {_ResponseList, BadNodes} =
                    rpc:multicall(NodesToSave,
                                  beamparticle_storage_util,
                                  write,
                                  [FullFunctionName,
                                   TrimmedFunctionBody,
                                   FunctionType,
                                   true]),
                HtmlResponse = case BadNodes of
                    [] ->
                        list_to_binary(
                            io_lib:format("The function ~s looks good to me.",
                                          [FullFunctionName]));
                    _ ->
                        list_to_binary(io_lib:format(
                            "Function ~s looks good, but <b>could not write to nodes: <p style='color:red'>~p</p></b>",
                            [FullFunctionName, BadNodes]))
                end,
                Msg = <<>>,
                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
            false ->
                Msg = <<"Cannot find function in knowledgebase.">>,
                HtmlResponse = <<"">>,
                {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
        end
    catch
        throw:{error, invalid_function_name} ->
            Msg3 = <<"The function name has '/' which is not allowed. Please remove '/' and try again!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate};
        throw:bad_config ->
            Msg3 = <<"Bad JSON configuration.">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate};
        _Class:_Error ->
            Msg3 = <<"It is not a valid Erlang/Elixir/Efene/PHP/Python/Java function!">>,
            HtmlResponse3 = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg3}, {<<"text">>, Msg3}, {<<"html">>, HtmlResponse3}])}, State, hibernate}
    end.

%% @private
%% @doc List functions with configuration starting with prefix in the knowledgebase
handle_config_list_command(Prefix, State) ->
    Resp = beamparticle_storage_util:similar_functions_with_config(Prefix,
                                                                   function),
    StageResp = beamparticle_storage_util:similar_functions_with_config(Prefix, function_stage),
    case {Resp, StageResp} of
        {[], []} ->
            HtmlResponse = <<"">>,
            Msg = case Prefix of
                      <<>> -> <<"I know nothing yet.">>;
                      _ -> <<"Dont know anything starting with ", Prefix/binary>>
                  end,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            NonStageResp = lists:filter(fun(E) ->
                                                {Fname, _} = E,
                                                case lists:keyfind(Fname, 1, StageResp) of
                                                    false -> true;
                                                    _ -> false
                                                end
                                        end, Resp),
            %% if you do not convert iolist to binary then
            %% jsx:encode/1 will add a comma at start and end of Body because
            %% iolist is basically a list.
            HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                               <<"<th scope='col'>Function/Arity</th><th scope='col'>Configuration</th>">>,
                               <<"</tr></thead><tbody>">>],
            NonStageHtmlTableBody = [ [<<"<tr><td class='beamparticle-function'>">>, X, <<"</td><td>">>, Y, <<"</td></tr>">>] || {X, Y} <- NonStageResp],
            StageHtmlTableBody = [ [<<"<tr><td style='color:red' class='beamparticle-function'>">>, X, <<"</font></td><td>">>, Y, <<"</td></tr>">>] || {X, Y} <- StageResp],
            HtmlTableBody = StageHtmlTableBody ++ NonStageHtmlTableBody,
            HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
            Msg = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}
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
            {_, ErlCode} = beamparticle_erlparser:extract_config(FunctionBody),
            HtmlResponse = <<"">>,
            Msg = <<"">>,
            {LangAtom, _, _Config, _} = beamparticle_erlparser:detect_language(FunctionBody),
            Lang = atom_to_binary(LangAtom, utf8),
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}, {<<"lang">>, Lang}])}, State, hibernate};
        _ ->
            HtmlResponse = <<"">>,
            Msg = <<"I dont know what you are talking about.">>,
            ErlCode = <<"">>,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}, {<<"erlcode">>, ErlCode}])}, State, hibernate}
    end.

%% @private
%% @doc What are the special commands available to me
handle_help_command(State) ->
    Commands = [{<<".release">>,
                 <<"Release staged functions to production.">>},
                {<<".revert <name>/<arity>">>,
                 <<"Revert a staged function with a given name.">>},
                {<<".diff <name>/<arity>">>,
                 <<"Display diff of a staged function versus production with a given name.">>},
                {<<".<save | write> <name>/<arity>">>,
                 <<"Save a function with a given name.">>},
                {<<".<open | edit> <name>/<arity>">>,
                 <<"Get function definition with the given name.">>},
                {<<".config open <name>/<arity>">>,
                 <<"Get configuration of a function.">>},
                {<<".config save <name>/<arity>">>,
                 <<"Save configuration of a function.">>},
                {<<".config ls">>,
                 <<"List all the functions with configuration available.">>},
                {<<".config ls <prefix>">>,
                 <<"List functions with configurations starting with prefix.">>},
                {<<".config delete <name>/<arity>">>,
                 <<"Delete configuration of a function.">>},
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
    KvResp = read_function_with_fallback(FullFunctionName),
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
%%
%% Delete in stage if available and in prod when not present in
%% stage.
handle_delete_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    %% TODO delete in cluster (though this is dangerous)
    KvResp = case beamparticle_storage_util:delete(FullFunctionName, function_stage) of
                 true ->
                     true;
                 _ ->
                     beamparticle_storage_util:delete(FullFunctionName, function)
             end,
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
%%
%% Delete in stage and in prod.
handle_purge_command(FullFunctionName, State) when is_binary(FullFunctionName) ->
    %% TODO delete in cluster (though this is dangerous)
    FunctionHistories = beamparticle_storage_util:function_history(FullFunctionName),
    lists:foreach(fun(E) ->
                          beamparticle_storage_util:delete(E, function_history)
                  end, FunctionHistories),
    %% best effort delete in stage first
    beamparticle_storage_util:delete(FullFunctionName, function_stage),
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
        erlang:erase(?LOG_ENV_KEY),
        case proplists:get_value(calltrace, State, false) of
            true ->
                erlang:put(?CALL_TRACE_ENV_KEY, []),
                erlang:put(?CALL_TRACE_BASE_TIME, T);
            false ->
                ok
        end,
        Result = beamparticle_dynamic:get_result(FunctionBody),
        case proplists:get_value(calltrace, State, false) of
            true ->
                CallTrace = erlang:get(?CALL_TRACE_ENV_KEY),
                erlang:erase(?CALL_TRACE_ENV_KEY),
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
    StageResp = beamparticle_storage_util:similar_functions_with_doc(Prefix, function_stage),
    case {Resp, StageResp} of
        {[], StageResp} ->
            HtmlResponse = <<"">>,
            Msg = case Prefix of
                      <<>> -> <<"I know nothing yet.">>;
                      _ -> <<"Dont know anything starting with ", Prefix/binary>>
                  end,
            {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate};
        _ ->
            NonStageResp = lists:filter(fun(E) ->
                                                {Fname, _} = E,
                                                case lists:keyfind(Fname, 1, StageResp) of
                                                    false -> true;
                                                    _ -> false
                                                end
                                        end, Resp),
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
            NonStageHtmlTableBody = [ [<<"<tr><td class='beamparticle-function'>">>, X, <<"</td><td>">>, CommentToHtmlFn(Y), <<"</td></tr>">>] || {X, Y} <- NonStageResp],
            StageHtmlTableBody = [ [<<"<tr><td style='color:red' class='beamparticle-function'>">>, X, <<"</font></td><td>">>, CommentToHtmlFn(Y), <<"</td></tr>">>] || {X, Y} <- StageResp],
            HtmlTableBody = StageHtmlTableBody ++ NonStageHtmlTableBody,
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
    StageTarGzFilenames = beamparticle_storage_util:get_function_snapshots(function_stage),
    HistoryTarGzFilenames = beamparticle_storage_util:get_function_history_snapshots(),
    WhatisTarGzFilenames = beamparticle_storage_util:get_whatis_snapshots(),
    JobTarGzFilenames = beamparticle_storage_util:get_job_snapshots(),
    HtmlTablePrefix = [<<"<table id='newspaper-c'><thead><tr>">>,
                       <<"<th scope='col'>Type</th><th scope='col'>Filename</th>">>,
                       <<"</tr></thead><tbody>">>],
    BodyStageFunctions = [ [<<"<tr><td>Function</td><td>">>, X, <<"</td></tr>">>] || X <- StageTarGzFilenames],
    BodyFunctions = [ [<<"<tr><td>Function</td><td>">>, X, <<"</td></tr>">>] || X <- TarGzFilenames],
    BodyFunctionHistories = [ [<<"<tr><td>Function History</td><td>">>, X, <<"</td></tr>">>] || X <- HistoryTarGzFilenames],
    BodyWhatis = [ [<<"<tr><td>Whatis</td><td>">>, X, <<"</td></tr>">>] || X <- WhatisTarGzFilenames],
    BodyJob = [ [<<"<tr><td>Job</td><td>">>, X, <<"</td></tr>">>] || X <- JobTarGzFilenames],
    HtmlTableBody = [BodyStageFunctions, BodyFunctions, BodyFunctionHistories, BodyWhatis, BodyJob],
    HtmlResponse = iolist_to_binary([HtmlTablePrefix, HtmlTableBody, <<"</tbody></table>">>]),
    Msg = <<"">>,
    {reply, {text, jsx:encode([{<<"speak">>, Msg}, {<<"text">>, Msg}, {<<"html">>, HtmlResponse}])}, State, hibernate}.

%% @private
%% @doc Backup knowledgebase of all functions and histories to disk
handle_backup_command(disk, State) ->
    NowDateTime = calendar:now_to_datetime(erlang:timestamp()),
    {ok, TarGzFilename} =
        beamparticle_storage_util:create_function_snapshot(NowDateTime),
    {ok, StageTarGzFilename} =
        beamparticle_storage_util:create_function_snapshot(NowDateTime,
                                                          function_stage),
    {ok, HistoryTarGzFilename} =
        beamparticle_storage_util:create_function_history_snapshot(NowDateTime),
    {ok, WhatisTarGzFilename} =
        beamparticle_storage_util:create_whatis_snapshot(NowDateTime),
    {ok, JobTarGzFilename} =
        beamparticle_storage_util:create_job_snapshot(NowDateTime),
    Resp = [list_to_binary(TarGzFilename),
            list_to_binary(StageTarGzFilename),
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
    StageTarGzFilename = binary_to_list(DateText) ++ "_stage_archive.tar.gz",
    HistoryTarGzFilename = binary_to_list(DateText) ++ "_archive_history.tar.gz",
    WhatisTarGzFilename = binary_to_list(DateText) ++ "_archive_whatis.tar.gz",
    JobTarGzFilename = binary_to_list(DateText) ++ "_archive_job.tar.gz",
        
    ImportResp = beamparticle_storage_util:import_functions(file, TarGzFilename),
    StageImportResp = beamparticle_storage_util:import_functions(file, StageTarGzFilename, function_stage),
    HistoryImportResp = beamparticle_storage_util:import_functions_history(HistoryTarGzFilename),
    WhatisImportResp = beamparticle_storage_util:import_whatis(file, WhatisTarGzFilename),
    JobImportResp = beamparticle_storage_util:import_job(file, JobTarGzFilename),
    HtmlResponse = <<"">>,
    Msg = list_to_binary(io_lib:format("Function import ~p, stage ~p, history import ~p, whatis import ~p, job import ~p",
                                       [ImportResp, StageImportResp, HistoryImportResp, WhatisImportResp, JobImportResp])),
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
            FunctionType = get_function_type(),
            ImportResp = beamparticle_storage_util:import_functions(
                           network,
                           {NetworkUrl, ["config_setup_all_config_env-0"]},
                           FunctionType),
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
    FunctionType = get_function_type(),
    ImportResp = beamparticle_storage_util:import_functions(
                   network, {UrlStr, []}, FunctionType),
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

%% @private
%% @doc get function type for current actor
-spec get_function_type() -> function | function_stage.
get_function_type() ->
    case erlang:get(?CALL_ENV_KEY) of
        undefined -> function;
        prod -> function;
        stage -> function_stage
    end.

read_function_with_fallback(FullFunctionName) ->
    case get_function_type() of
        function ->
            beamparticle_storage_util:read(
              FullFunctionName, function);
        FunctionType ->
            case beamparticle_storage_util:read(
                   FullFunctionName, FunctionType) of
                {ok, _} = R ->
                    R;
                _ ->
                    beamparticle_storage_util:read(
                      FullFunctionName, function)
            end
    end.

%% @private
%% @doc Validate json configuration
-spec validate_json_config(binary()) -> boolean().
validate_json_config(<<>>) ->
    true;
validate_json_config(Config) when is_binary(Config) ->
    try
        jiffy:decode(Config, [return_maps]),
        true
    catch
        _C:_E ->
            false
    end.

merge_function_with_older_config(FullFunctionName,
                                 NewSourceCode) ->
    KvResp = read_function_with_fallback(FullFunctionName),
    case KvResp of
        {ok, FunctionBody} ->
            {Config, _ErlCode} = beamparticle_erlparser:extract_config(
                                  FunctionBody),
            case Config of
                <<>> ->
                    NewSourceCode;
                _ ->
                    iolist_to_binary([Config, <<"||||\n">>, NewSourceCode])
            end;
        _ ->
            NewSourceCode
    end.

merge_function_with_new_config(FullFunctionName, Config) ->
    KvResp = read_function_with_fallback(FullFunctionName),
    case KvResp of
        {ok, FunctionBody} ->
            {_OldConfig, ErlCode} = beamparticle_erlparser:extract_config(
                                  FunctionBody),
            case Config of
                <<>> ->
                    ErlCode;
                _ ->
                    iolist_to_binary([Config, <<"||||\n">>, ErlCode])
            end;
        _ ->
            {error, not_found}
    end.

run_query(F, Query, State) ->
    case proplists:get_value(userinfo, State) of
        undefined ->
            case beamparticle_nlp_dialogue:all() of
                [{attempt, N}] ->
                    %% Query2 = string:trim(Query),
                    Resp = case N of
                               _ when N < 5 ->
                                   <<"Let's start over, shall we? Please type your email address.">>;
                               _ ->
                                   <<"Huh! It is better that you contact the administrator to reset your password. I don't want to be nit-pick, but arn't you tired of starting over-and over. Anyways, if you insist then type your email address again.">>
                           end,
                    HtmlResponse = get_oauth_signin_msg(),
                    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp},
                                           {<<"html">>, HtmlResponse}, {<<"secure_input">>, <<"false">>}]),
                    beamparticle_nlp_dialogue:push(require_username),
                    {reply, {text, Response}, State, hibernate};
                [] ->
                    %% Query2 = string:trim(Query),
                    Resp = <<"Please sign-in with g+ login or identify yourself for secure access by typing your email address.">>,
                    HtmlResponse = get_oauth_signin_msg(),
                    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp},
                                           {<<"html">>, HtmlResponse}, {<<"secure_input">>, <<"false">>}]),
                    beamparticle_nlp_dialogue:push(require_username),
                    {reply, {text, Response}, State, hibernate};
                [require_username | _ ] = _Dialogues ->
                    Username = string:trim(Query),
                    Resp = <<"Please type your password.">>,
                    %% secure_input, so that the text field become secure (astrix)
                    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp},
                                             {<<"secure_input">>, <<"true">>}]),
                    beamparticle_nlp_dialogue:push({username, Username}),
                    {reply, {text, Response}, State, hibernate};
                [{username, Username} | _ ] = _Dialogues ->
                    Password = string:trim(Query),
                    ShouldWeRestart = case string:lowercase(Password) of
                                          <<"ok">> -> true;
                                          _ -> false
                                      end,
                    case ShouldWeRestart of
                        false ->
                            case beamparticle_auth:authenticate_user(Username, Password, websocket) of
                                {true, UserInfo} ->
                                    Resp = <<"Welcome! You can now access the system. What can I do for you today?">>,
                                    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp},
                                                             {<<"secure_input">>, <<"false">>}]),
                                    beamparticle_nlp_dialogue:reset([]),
                                    State2 = proplists:delete(userinfo, State),
                                    State3 = [{userinfo, UserInfo} | State2],
                                    {reply, {text, Response}, State3, hibernate};
                                {false, _} ->
                                    Hint = case string:uppercase(Password) of
                                               Password ->
                                                   <<"It appears that your CAPS key is on. ">>;
                                               _ ->
                                                   <<>>
                                           end,
                                    Resp = <<Hint/binary, "I am sorry, but I cannot authenticate you. Please type OK to start over or type your password again.">>,
                                    HtmlResponse = get_oauth_signin_msg(),
                                    %% secure_input, so that the text field become secure (astrix)
                                    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp},
                                                           {<<"html">>, HtmlResponse}, {<<"secure_input">>, <<"true">>}]),
                                    {reply, {text, Response}, State, hibernate}
                            end;
                        true ->
                            Dialogues = beamparticle_nlp_dialogue:all(),
                            case lists:reverse(Dialogues) of
                                [{attempt, N} | _] ->
                                    beamparticle_nlp_dialogue:reset([{attempt, N+1}]);
                                _ ->
                                    beamparticle_nlp_dialogue:reset([{attempt, 1}])
                            end,
                            websocket_handle(Query, State)
                    end
            end;
        UserInfo ->
            erlang:put(?USERINFO_ENV_KEY, UserInfo),
            F(Query, State)
    end.

get_oauth_signin_msg() ->
    <<"<div class='oauth-image-links'><small><p>Sign in with <a href='/auth/google/login'><img src='static/images/google_login.png' /></a></p></small></div>">>.
