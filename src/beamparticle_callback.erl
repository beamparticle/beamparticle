%%%-------------------------------------------------------------------
%%% @doc
%%% Defines the behaviour for beamparticle callback modules,
%%% to be used with the `beamparticle_handler' pattern.
%%% The behaviour is letting the caller specify how to handle
%%% common functions for beamparticle operations.
%%%
%%% Specify the `-behaviour(beamparticle_callback).' module attribute
%%% and the rest can then be implemented.
%%% @end
%%%
%%% %CopyrightBegin%
%%%
%%% Copyright (c) 2016, Fred Hebert <mononcqc@ferd.ca>.
%%% Copyright (c) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>.
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

-module(beamparticle_callback).
-ignore_xref([behaviour_info/1]).
-type state() :: term().
-type id() :: binary().
-export_type([id/0]).

-callback init() -> state().
-callback init(term(), [{binary(), binary()}]) -> state().
-callback terminate(state()) -> term().
-callback validate(term(), state()) -> {boolean(), state()}.
-callback create(id() | undefined, term(), state()) ->
            {false | true | {true, id()}, state()}.
-callback read(id(), state()) -> {{ok, term()} | {error, not_found}, state()}.
-callback update(id(), term(), state()) -> {boolean(), state()}.
-callback delete(id(), state()) -> {boolean(), state()}.
