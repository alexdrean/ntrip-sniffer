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
    {ok, #{socket => Socket, first_rtcm_logged => false}}.

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
                {ok, Payload} ->
                    case ntrip_rtcm3:extract_frames(Payload) of
                        [] ->
                            State;
                        Frames ->
                            Validated = iolist_to_binary(Frames),
                            State1 = maybe_log_first(IP, Port, byte_size(Validated), State),
                            ntrip_clients:broadcast(Validated),
                            State1
                    end;
                error ->
                    State
            end;
        error ->
            State
    end.

maybe_log_first(_IP, _Port, _Size, #{first_rtcm_logged := true} = State) ->
    State;
maybe_log_first(IP, Port, Size, State) ->
    io:format("[tzsp] receiving RTCM3 data from ~s:~B (~B bytes)~n",
              [inet:ntoa(IP), Port, Size]),
    State#{first_rtcm_logged := true}.
