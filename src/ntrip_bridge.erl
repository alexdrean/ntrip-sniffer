-module(ntrip_bridge).
-export([main/1]).

main(_Args) ->
    application:ensure_all_started(ntrip_bridge),
    receive _ -> ok end.
