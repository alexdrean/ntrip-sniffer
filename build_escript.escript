#!/usr/bin/env escript

main(_) ->
    {ok, Files} = file:list_dir("ebin"),
    Entries = [{filename:join("ntrip_bridge/ebin", F),
                element(2, file:read_file(filename:join("ebin", F)))}
               || F <- Files],
    {ok, {_, Zip}} = zip:create("ntrip_bridge.zip", Entries, [memory]),
    Header = <<"#!/usr/bin/env escript\n">>,
    Script = <<Header/binary, Zip/binary>>,
    ok = file:write_file("ntrip_bridge", Script),
    io:format("Built: ./ntrip_bridge~n").
