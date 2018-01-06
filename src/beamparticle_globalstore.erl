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
-module(beamparticle_globalstore).

-export([create/2, create_or_update/2, read/1, update/2, delete/1]).

-type key() :: term().
-type val() :: term().

-spec create(key(), val()) -> boolean().
create(K, V) ->
    beamparticle_seq_write_store:create(K, V).

-spec create_or_update(key(), val()) -> boolean().
create_or_update(K, V) ->
    beamparticle_seq_write_store:create_or_update(K, V).

-spec read(key()) -> {ok, term()} | {error, not_found}.
read(K) ->
    beamparticle_seq_write_store:read(K).

-spec update(key(), val()) -> boolean().
update(K, V) ->
    beamparticle_seq_write_store:update(K, V).

-spec delete(key()) -> boolean().
delete(K) ->
    beamparticle_seq_write_store:delete(K).

