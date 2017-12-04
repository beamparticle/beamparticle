%%%-------------------------------------------------------------------
%%% @doc
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
-module(beamparticle_cache_util).
-author("neerajsharma").

-include("beamparticle_constants.hrl").

%% API
-export([available_caches/0]).
-export([cache_start_link/2]).
-export([put/3, get/2, remove/2]).
-export([async_put/3, async_remove/2]).

-export([put/2, get/1, remove/1]).
-export([async_put/2, async_remove/1]).


available_caches() ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    lists:foldl(fun({CacheName, CacheOptions}, AccIn) ->
                        PropList = [{convert_to_binary(X), convert_to_binary(Y)} || {X, Y} <- CacheOptions],
                        M = maps:from_list(PropList),
                        M2 = M#{<<"_name">> => convert_to_binary(CacheName)},
                        [M2 | AccIn]
                end, [], Caches).

%% TODO at present caches are not part of supervison tree
%% ADD them, so that they are restarted automatically on error
cache_start_link(CacheOptions, CacheName) ->
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            %% drops cache if it exists already
            %% cache:drop(?CACHE_NAME),
            MemoryBytes = proplists:get_value(
                            memory_bytes, CacheOptions, ?DEFAULT_CACHE_MEMORY_BYTES),
            Segments = proplists:get_value(
                         segments, CacheOptions, ?DEFAULT_CACHE_SEGMENTS),
            TtlSec = proplists:get_value(
                       ttl_sec, CacheOptions, ?DEFAULT_CACHE_TTL_SEC),
            {ok, _} = cache:start_link(CacheName,
                [
                    {memory, MemoryBytes},
                    {n, Segments},
                    {ttl, TtlSec}
                ]);
        _ ->
            ok
    end.

get(Key, CacheName) ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    CacheOptions = proplists:get_value(CacheName, Caches, []),
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            %% lager:debug("Get ~p from local", [Key]),
            Value = cache:get(CacheName, Key),
            case Value of
                undefined -> {error, not_found};
                Data -> {ok, Data}
            end;
        false ->
            {error, not_found}
    end.

put(Key, Data, CacheName) ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    CacheOptions = proplists:get_value(CacheName, Caches, []),
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            cache:put(CacheName, Key, Data);
        false ->
            ok
    end.

async_put(Key, Data, CacheName) ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    CacheOptions = proplists:get_value(CacheName, Caches, []),
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            cache:put_(CacheName, Key, Data);
        false ->
            ok
    end.

remove(Key, CacheName) ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    CacheOptions = proplists:get_value(CacheName, Caches, []),
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            cache:remove(CacheName, Key);
        false ->
            ok
    end.

async_remove(Key, CacheName) ->
    Caches = application:get_env(?APPLICATION_NAME, caches, []),
    CacheOptions = proplists:get_value(CacheName, Caches, []),
    case proplists:get_value(enable, CacheOptions, false) of
        true ->
            cache:remove_(CacheName, Key);
        false ->
            ok
    end.

get(Key) ->
    get(Key, ?CACHE_NAME).

put(Key, Data) ->
    put(Key, Data, ?CACHE_NAME).

async_put(Key, Data) ->
    async_put(Key, Data, ?CACHE_NAME).

remove(Key) ->
    remove(Key, ?CACHE_NAME).

async_remove(Key) ->
    async_remove(Key, ?CACHE_NAME).

%%%===================================================================
%%% Internal functions
%%%===================================================================

convert_to_binary(X) when is_binary(X) ->
    X;
convert_to_binary(X) when is_atom(X) ->
    atom_to_binary(X, utf8);
convert_to_binary(X) when is_integer(X) ->
    integer_to_binary(X);
convert_to_binary(X) when is_list(X) ->
    list_to_binary(X).
