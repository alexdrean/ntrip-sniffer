-module(ntrip_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([main/1]).

%% escript entry point
main(_Args) ->
    application:ensure_all_started(ntrip_bridge),
    %% Block forever — supervisor keeps children alive
    receive _ -> ok end.

start(_StartType, _StartArgs) ->
    io:format("TZSP-to-NTRIP bridge starting~n"),
    io:format("  TZSP receiver : UDP 37008~n"),
    io:format("  NTRIP caster  : TCP 2101~n"),
    io:format("  Mountpoints   : dynamic (from TZSP source IPs)~n"),
    ntrip_auth:load_users(),
    io:format("~n"),
    ntrip_rtcm3:init_crc_table(),
    ntrip_sup:start_link().

stop(_State) ->
    ok.
