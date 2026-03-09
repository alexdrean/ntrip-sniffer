-module(ntrip_caster).
-export([start_link/0, accept_loop_init/1]).

-define(NTRIP_PORT, 2101).

start_link() ->
    proc_lib:start_link(?MODULE, accept_loop_init, [self()]).

accept_loop_init(Parent) ->
    {ok, ListenSock} = gen_tcp:listen(?NTRIP_PORT, [
        binary, {active, false}, {reuseaddr, true}, {packet, raw}
    ]),
    io:format("[ntrip] listening on TCP port ~B~n", [?NTRIP_PORT]),
    proc_lib:init_ack(Parent, {ok, self()}),
    accept_loop(ListenSock).

accept_loop(ListenSock) ->
    {ok, Socket} = gen_tcp:accept(ListenSock),
    spawn(fun() -> handle_client(Socket) end),
    accept_loop(ListenSock).

handle_client(Socket) ->
    case gen_tcp:recv(Socket, 0, 10000) of
        {ok, Data} ->
            case ntrip_protocol:parse_ntrip_request(Data) of
                {ok, <<"GET">>, <<"/">>, _Auth} ->
                    send_sourcetable(Socket);
                {ok, <<"GET">>, <<"/", Mountpoint/binary>>, Auth}
                  when byte_size(Mountpoint) > 0 ->
                    case ntrip_auth:check_auth(Auth) of
                        ok ->
                            start_stream(Socket, Mountpoint);
                        {error, 401} ->
                            gen_tcp:send(Socket, <<"HTTP/1.0 401 Unauthorized\r\n"
                                                   "WWW-Authenticate: Basic realm=\"NTRIP\"\r\n\r\n">>),
                            gen_tcp:close(Socket)
                    end;
                {ok, <<"GET">>, _, _} ->
                    gen_tcp:send(Socket, <<"HTTP/1.0 404 Not Found\r\n\r\n">>),
                    gen_tcp:close(Socket);
                {ok, _, _, _} ->
                    gen_tcp:send(Socket, <<"HTTP/1.0 405 Method Not Allowed\r\n\r\n">>),
                    gen_tcp:close(Socket);
                error ->
                    gen_tcp:close(Socket)
            end;
        {error, _} ->
            gen_tcp:close(Socket)
    end.

send_sourcetable(Socket) ->
    Mountpoints = ntrip_clients:get_mountpoints(),
    AuthField = case persistent_term:get(ntrip_users, none) of
        none -> <<"N">>;
        _ -> <<"B">>
    end,
    Entries = [
        [<<"STR;">>, MP, <<";RTCM3;RTCM 3.3;;;;;0.00;0.00;0;0;;none;">>,
         AuthField, <<";N;;\r\n">>]
        || MP <- Mountpoints
    ],
    Response = iolist_to_binary([
        <<"SOURCETABLE 200 OK\r\n">>,
        <<"Content-Type: text/plain\r\n">>,
        <<"\r\n">>,
        Entries,
        <<"ENDSOURCETABLE\r\n">>
    ]),
    gen_tcp:send(Socket, Response),
    gen_tcp:close(Socket).

start_stream(Socket, Mountpoint) ->
    {ok, Addr} = inet:peername(Socket),
    io:format("[ntrip] client connected: ~s -> /~s~n", [format_addr(Addr), Mountpoint]),
    gen_tcp:send(Socket, <<"ICY 200 OK\r\n\r\n">>),
    ClientPid = spawn(fun() -> client_loop(Socket) end),
    gen_tcp:controlling_process(Socket, ClientPid),
    ntrip_clients:register_client(ClientPid, Socket, Addr, Mountpoint).

client_loop(Socket) ->
    receive
        {rtcm3, Data} ->
            case gen_tcp:send(Socket, Data) of
                ok -> client_loop(Socket);
                {error, _} -> gen_tcp:close(Socket)
            end
    end.

format_addr({IP, Port}) ->
    io_lib:format("~s:~B", [inet:ntoa(IP), Port]).
