-module(ntrip_tzsp).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TZSP_PORT, 37008).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, Socket} = gen_udp:open(?TZSP_PORT, [binary, {active, true}, {reuseaddr, true}]),
    io:format("[tzsp] listening on UDP port ~B~n", [?TZSP_PORT]),
    {ok, #{socket => Socket, logged_sources => #{}}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({udp, _Socket, IP, Port, Data}, State) ->
    State1 = process_packet(Data, IP, Port, State),
    {noreply, State1};
handle_info(_Info, State) ->
    {noreply, State}.

process_packet(Data, IP, Port, State) ->
    case ntrip_protocol:strip_tzsp(Data) of
        {ok, Frame} ->
            case ntrip_protocol:extract_ip_payload(Frame) of
                {ok, SrcIP, Payload} ->
                    case ntrip_rtcm3:extract_frames(Payload) of
                        [] ->
                            State;
                        Frames ->
                            Validated = iolist_to_binary(Frames),
                            State1 = maybe_log_first(SrcIP, IP, Port, byte_size(Validated), State),
                            ntrip_clients:broadcast(SrcIP, Validated),
                            State1
                    end;
                error ->
                    State
            end;
        error ->
            State
    end.

maybe_log_first(SrcIP, IP, Port, Size, #{logged_sources := Logged} = State) ->
    case maps:is_key(SrcIP, Logged) of
        true -> State;
        false -> log_new_source(SrcIP, IP, Port, Size, Logged, State)
    end.

log_new_source(SrcIP, IP, Port, Size, Logged, State) ->
    io:format("[tzsp] RTCM3 source ~s (via ~s:~B, ~B bytes) -> /~s~n",
              [SrcIP, inet:ntoa(IP), Port, Size, SrcIP]),
    ntrip_clients:notify_mountpoint(SrcIP),
    State#{logged_sources := Logged#{SrcIP => true}}.
