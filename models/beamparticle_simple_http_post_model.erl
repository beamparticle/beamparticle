%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% Only HTTP POST must be allowed.
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

-module(beamparticle_simple_http_post_model).
-behaviour(beamparticle_callback).
-export([init/0, init/2, terminate/1, % CRUD
         validate/2, create/3, read/2, update/3, delete/2]).
-export_type([beamparticle_fn_body/0]).

-include("beamparticle_constants.hrl").

-record(state, {
          id = undefined :: undefined | binary(),
          qsproplist = [] :: [{binary(), binary()}]
         }).

-type beamparticle_fn_body() :: binary().
-type state() :: state().

%%%===================================================================
%%% API
%%%===================================================================

%%%===================================================================
%%% Callbacks
%%%===================================================================

%% @doc Initialize the state that the handler will carry for
%% a specific request throughout its progression. The state
%% is then passed on to each subsequent call to this model.
-spec init() -> state().
init() ->
    #state{}.

-spec init(binary(), [{binary(), binary()}]) -> state().
init(Id, QsProplist) ->
    #state{id = Id, qsproplist = QsProplist}.

%% @doc At the end of a request, the state is passed back in
%% to allow for clean up.
-spec terminate(state()) -> term().
terminate(_State) ->
    ok.

%% @doc Return, via a boolean value, whether the user-submitted
%% data structure is considered to be valid by this model's standard.
-spec validate(beamparticle_fn_body() | term(), state()) -> {boolean(), state()}.
validate(V, State) ->
    {is_binary(V) andalso byte_size(V) > 0, State}.

%% @doc Create a new entry. If the id is `undefined', the user
%% has not submitted an id under which to store the resource:
%% the id needs to be generated by the model, and (if successful),
%% returned via `{true, GeneratedId}'.
%% Otherwise, a given id will be passed, and a simple `true' or
%% `false' value may be returned to confirm the results.
%%
%% The created resource is validated before this function is called.
-spec create(beamparticle_callback:id() | undefined, beamparticle_fn_body(), state()) ->
        {false | true | {true, beamparticle_callback:id()}, state()}.
create(Id, V, State) when is_binary(Id) ->
    get_response(Id, V, State);
create(undefined, _V, State) ->
	{false, State}.

%% @doc Read a given entry from the store based on its Id.
-spec read(beamparticle_callback:id(), state()) ->
        { {ok, beamparticle_fn_body()} | {error, not_found}, state()}.
read(_Id, State) ->
    {{error, not_found}, State}.

%% @doc Update an existing resource.
%%
%% The modified resource is validated before this function is called.
-spec update(beamparticle_callback:id(), beamparticle_fn_body(), state()) -> {boolean(), state()}.
update(Id, V, State) ->
    get_response(Id, V, State).

%% @doc Delete an existing resource.
-spec delete(beamparticle_callback:id(), state()) -> {boolean(), state()}.
delete(_Id, State) ->
    {false, State}.

%%%===================================================================
%%% Internal
%%%===================================================================

get_response(Id, V, #state{qsproplist = QsProplist} = State) when is_binary(Id) ->
	%% Map = jsx:decode(V, [return_maps]),
    lager:debug("Request body = ~p, QsProplist = ~p", [V, QsProplist]),
    case proplists:get_value(<<"env">>, QsProplist) of
        <<"2">> ->
            erlang:put(?CALL_ENV_KEY, stage);
        _ ->
            %% actors are reusable, so set environment variable always
            erlang:put(?CALL_ENV_KEY, prod)
    end,
    ContextBin = jiffy:encode(maps:from_list(QsProplist)),
    Arguments = [V, ContextBin],
    Result = beamparticle_dynamic:get_raw_result(Id, Arguments),
    %% as part of dynamic call configurations could be set,
    %% so lets erase that before the next reuse
    beamparticle_dynamic:erase_config(),
    {Result, State}.

