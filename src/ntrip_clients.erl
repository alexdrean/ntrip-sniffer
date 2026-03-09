-module(ntrip_clients).
-behaviour(gen_server).

-export([start_link/0, register_client/4, broadcast/2,
         notify_mountpoint/1, get_mountpoints/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_client(Pid, Socket, Addr, Mountpoint) ->
    gen_server:cast(?MODULE, {register, Pid, Socket, Addr, Mountpoint}).

broadcast(Mountpoint, Data) ->
    gen_server:cast(?MODULE, {broadcast, Mountpoint, Data}).

notify_mountpoint(Mountpoint) ->
    gen_server:cast(?MODULE, {mountpoint, Mountpoint}).

get_mountpoints() ->
    gen_server:call(?MODULE, get_mountpoints).

%% gen_server callbacks

init([]) ->
    {ok, #{clients => #{}, mountpoints => #{}}}.

handle_call(get_mountpoints, _From, #{mountpoints := MPs} = State) ->
    {reply, maps:keys(MPs), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({register, Pid, Socket, Addr, Mountpoint}, #{clients := Clients} = State) ->
    monitor(process, Pid),
    {noreply, State#{clients := Clients#{Pid => {Socket, Addr, Mountpoint}}}};
handle_cast({broadcast, Mountpoint, Data}, #{clients := Clients} = State) ->
    Msg = {rtcm3, Data},
    maps:fold(fun(Pid, {_, _, MP}, _) ->
        case MP of
            Mountpoint -> Pid ! Msg;
            _ -> ok
        end
    end, ok, Clients),
    {noreply, State};
handle_cast({mountpoint, MP}, #{mountpoints := MPs} = State) ->
    {noreply, State#{mountpoints := MPs#{MP => true}}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #{clients := Clients} = State) ->
    case maps:find(Pid, Clients) of
        {ok, {_Socket, Addr, Mountpoint}} ->
            io:format("[ntrip] client disconnected: ~s (was on /~s)~n",
                      [format_addr(Addr), Mountpoint]);
        error ->
            ok
    end,
    {noreply, State#{clients := maps:remove(Pid, Clients)}};
handle_info(_Info, State) ->
    {noreply, State}.

format_addr({IP, Port}) ->
    io_lib:format("~s:~B", [inet:ntoa(IP), Port]);
format_addr(Other) ->
    io_lib:format("~p", [Other]).
