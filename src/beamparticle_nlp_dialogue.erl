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
-module(beamparticle_nlp_dialogue).

-include("beamparticle_constants.hrl").

-export([all/0, push/1, pop/0, reset/1]).

%% @doc Get all dialogues from process dictionary
-spec all() -> list().
all() ->
    case erlang:get(?DIALOGUE_ENV_KEY) of
        undefined -> [];
        Dialogues -> Dialogues
    end.

%% @doc Stack new dialogue on top while returning the earlier dialogues.
push(D) ->
    Dialogues = [D | all()],
    erlang:put(?DIALOGUE_ENV_KEY, Dialogues).

pop() ->
    case all() of
        [] ->
            undefined;
        [D | Dialogues] ->
            erlang:put(?DIALOGUE_ENV_KEY, Dialogues),
            D
    end.

reset(Dialogues) ->
    erlang:put(?DIALOGUE_ENV_KEY, Dialogues).

