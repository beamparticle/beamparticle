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
-module(beamparticle_dynamic).

-export([execute/1, get_result/1, get_result/2]).
-export([transform_result/1]).


execute(Expression) when is_binary(Expression) ->
    try
        F = beamparticle_erlparser:evaluate_erlang_expression(binary_to_list(Expression)),
        case is_function(F, 0) of
            true ->
                try
                    apply(F, [])
                catch
                    throw:{error, R} ->
                        {text, R}
                end;
            false ->
                lager:error("Function F = ~p is invalid", [F]),
                {error, invalid_function}
        end
    catch
        Class:Error ->
            lager:error("~p:~p", [Class, Error]),
            {error, {Class, Error}}
    end;
execute({DynamicFunctionName, Arguments}) ->
    ArgBin = list_to_binary(lists:join(",", [io_lib:format("~p", [Y]) || Y <- Arguments])),
    FunctionBody = <<"fun() -> ", DynamicFunctionName/binary, "(", ArgBin/binary, ")\nend.">>,
    lager:debug("Running function = ~p", [FunctionBody]),
    execute(FunctionBody).

get_result(FunctionName, Arguments) when is_binary(FunctionName) andalso is_list(Arguments) ->
    lager:debug("get_response(~p, ~p)", [FunctionName, Arguments]),
    Result = execute({FunctionName, Arguments}),
    transform_result(Result).

get_result(Expression) when is_binary(Expression) ->
    lager:debug("get_response(~p)", [Expression]),
    Result = execute(Expression),
    transform_result(Result).

transform_result(Result) ->
    case Result of
        {error, invalid_function} ->
            Msg = <<"It is not a valid Erlang expression!">>,
            HtmlResponse = <<"">>,
            Json = #{},
            [{<<"speak">>, Msg},
             {<<"text">>, Msg},
             {<<"html">>, HtmlResponse},
             {<<"json">>, Json}];
        _ ->
            lager:debug("Result2 = ~p", [Result]),
            {Msg, HtmlResponse, Json} = case Result of
                                      {direct, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {speak, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {text, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {html, M} when is_binary(M) ->
                                          {<<"">>, M, #{}};
                                      {json, M} when is_map(M) ->
                                          {<<"">>, <<"">>, M};
                                      _ ->
                                          {<<"">>, list_to_binary(
                                            io_lib:format("~p", [Result])), #{}}
                                  end,
            [{<<"speak">>, Msg},
             {<<"text">>, Msg},
             {<<"html">>, HtmlResponse},
             {<<"json">>, Json}]
    end.
