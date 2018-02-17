%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% Containerization of generic processes.
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
-module(beamparticle_container_util).

%%-include_lib("alcove/include/alcove.hrl").

-export([create_driver/2,
         create_child/7]).

-export_type([create_option/0]).

-type create_option() :: ctldir
    | rlimit_fsize
    | rlimit_nofile
    | rlimit_nproc
    | chroot_path
    %% following are specifically used for namespaces
    | cgroup_name
    | cpuset_cpus
    | cpuset_mems
    | memory_memsw_limit_in_bytes
    | memory_limit_in_bytes.

%% API

%%%===================================================================
%%% API
%%%===================================================================

-spec create_driver(simple | sandbox | namespace, Opts :: [{create_option(), term()}]) ->
    {ok, Drv :: alcove_drv:ref()}.
create_driver(simple, [{ctldir, CtlDir}]) ->
    alcove_drv:start_link([{ctldir, CtlDir}]);
create_driver(sandbox, [{ctldir, CtlDir}]) ->
    %% sudo is required for using chroot later
    %% ensure that alcove binary has capabilities set via sudoers
    %% -----
    %% sudo visudo -f /etc/sudoers.d/99_alcove
    %% <user> ALL = NOPASSWD: /path/to/alcove/priv/alcove
    %% Defaults!/path/to/alcove/priv/alcove !requiretty
    %% -----
    %% chown root:root priv/alcove
    %% chmod u+s priv/alcove
    %% -----
    alcove_drv:start([{exec, "sudo -n"}, {ctldir, CtlDir}]);
create_driver(namespace, Opts) ->
    %% ensure settings same as that for sandbox above
    CtlDir = proplists:get_value(ctldir, Opts),
    {ok, Drv} = alcove_drv:start_link([{exec, "sudo -n"}, {ctldir, CtlDir}]),
    GroupName = proplists:get_value(cgroup_name, Opts),
    ok = alcove_cgroup:create(Drv, [], GroupName),
    %% http://man7.org/linux/man-pages/man7/cpuset.7.html
    case proplists:get_value(cpuset_cpus, Opts) of
        undefined ->
            ok;
        CpusetCpus ->
            {ok, _} = alcove_cgroup:set(Drv, [], <<"cpuset">>, <<"alcove">>,
                                        <<"cpuset.cpus">>, CpusetCpus)
    end,
    case proplists:get_value(cpuset_mems, Opts) of
        undefined ->
            ok;
        CpusetMems ->
            {ok, _} = alcove_cgroup:set(Drv, [], <<"cpuset">>, <<"alcove">>,
                                        <<"cpuset.mems">>, CpusetMems)
    end,
    case proplists:get_value(memory_memsw_limit_in_bytes, Opts) of
        undefined ->
            ok;
        MemswLimitOctets ->
            {ok, _} = alcove_cgroup:set(Drv, [], <<"memory">>, <<"alcove">>,
                                        <<"memory.memsw.limit_in_bytes">>,
                                        MemswLimitOctets)
    end,

    case proplists:get_value(memory_limit_in_bytes, Opts) of
        undefined ->
            ok;
        MemoryLimitOctets ->
            {ok, _} = alcove_cgroup:set(Drv, [], <<"memory">>, <<"alcove">>,
                                        <<"memory.limit_in_bytes">>,
                                        MemoryLimitOctets)
    end,
    {ok, Drv}.


%% Note that Arg0 is absolute filename (that is with absolute path)
%% Note that EnvironmentVars must be like the following
%% ```
%%     EnvironmentVars = ["HOME=/", "PATH="/bin:/sbin:"] 
%% '''
-spec create_child(simple | sandbox | namespace,
                   Drv :: alcove_drv:ref(), GroupName :: binary(),
                   Arg0 :: string(), Args :: [string()],
                   EnvironmentVars :: [string()],
                   Opts :: [{atom(), term()}]) ->
    {ok, ChildPID :: alcove:pid_t()}.
create_child(simple, Drv, _GroupName, Arg0, Args, EnvironmentVars, _Opts) ->
    {ok, ChildPID} = alcove:fork(Drv, []),
    %% ensure child get sighup when parent dies
    {ok, _, _, _, _, _} = alcove:prctl(Drv, [ChildPID], pr_set_pdeathsig, 9, 0, 0, 0),
    %% execute app
    ok = alcove:execve(Drv, [ChildPID], Arg0, [Arg0 | Args], EnvironmentVars),
    {ok, ChildPID}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


