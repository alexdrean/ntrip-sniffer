-module(ntrip_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => ntrip_clients,
          start => {ntrip_clients, start_link, []},
          type => worker},
        #{id => ntrip_tzsp,
          start => {ntrip_tzsp, start_link, []},
          type => worker},
        #{id => ntrip_caster,
          start => {ntrip_caster, start_link, []},
          type => worker}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.
