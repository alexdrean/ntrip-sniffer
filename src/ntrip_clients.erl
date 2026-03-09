-module(ntrip_clients).
-behaviour(gen_server).

-export([start_link/0, register_client/3, broadcast/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_client(Pid, Socket, Addr) ->
    gen_server:cast(?MODULE, {register, Pid, Socket, Addr}).

broadcast(Data) ->
    gen_server:cast(?MODULE, {broadcast, Data}).

%% gen_server callbacks

init([]) ->
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({register, Pid, Socket, Addr}, State) ->
    monitor(process, Pid),
    {noreply, State#{Pid => {Socket, Addr}}};
handle_cast({broadcast, Data}, State) ->
    Msg = {rtcm3, Data},
    maps:fold(fun(Pid, _, _) -> Pid ! Msg end, ok, State),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    case maps:find(Pid, State) of
        {ok, {_Socket, Addr}} ->
            io:format("[ntrip] client disconnected: ~s~n", [format_addr(Addr)]);
        error ->
            ok
    end,
    {noreply, maps:remove(Pid, State)};
handle_info(_Info, State) ->
    {noreply, State}.

format_addr({IP, Port}) ->
    io_lib:format("~s:~B", [inet:ntoa(IP), Port]);
format_addr(Other) ->
    io_lib:format("~p", [Other]).
