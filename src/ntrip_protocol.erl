-module(ntrip_protocol).
-export([strip_tzsp/1, extract_ip_payload/1, parse_ntrip_request/1]).

%% Strip TZSP header and tagged fields, return the encapsulated frame.
strip_tzsp(<<_Ver, _Type, _Proto:16, Rest/binary>>) ->
    walk_tags(Rest);
strip_tzsp(_) ->
    error.

walk_tags(<<16#01, Rest/binary>>) ->
    %% End tag
    {ok, Rest};
walk_tags(<<16#00, Rest/binary>>) ->
    %% Padding
    walk_tags(Rest);
walk_tags(<<_Tag, Len, Rest/binary>>) when byte_size(Rest) >= Len ->
    <<_Value:Len/binary, Remaining/binary>> = Rest,
    walk_tags(Remaining);
walk_tags(<<>>) ->
    error;
walk_tags(_) ->
    error.

%% Given an Ethernet or raw-IP frame, extract the transport payload.
extract_ip_payload(<<4:4, IHL:4, _:64, Proto, _Checksum:16, _Src:32, _Dst:32, Rest/binary>>) ->
    %% Raw IPv4
    OptionsLen = (IHL - 5) * 4,
    case Rest of
        <<_Options:OptionsLen/binary, TransportData/binary>> ->
            extract_transport(Proto, TransportData);
        _ ->
            error
    end;
extract_ip_payload(<<_EthDst:6/binary, _EthSrc:6/binary, _EthType:16,
                     4:4, IHL:4, _:64, Proto, _Checksum:16, _Src:32, _Dst:32, Rest/binary>>) ->
    %% Ethernet + IPv4
    OptionsLen = (IHL - 5) * 4,
    case Rest of
        <<_Options:OptionsLen/binary, TransportData/binary>> ->
            extract_transport(Proto, TransportData);
        _ ->
            error
    end;
extract_ip_payload(_) ->
    error.

extract_transport(17, <<_SrcPort:16, _DstPort:16, _Len:16, _Checksum:16, Payload/binary>>) ->
    %% UDP
    {ok, Payload};
extract_transport(6, <<_SrcPort:16, _DstPort:16, _Seq:32, _Ack:32, Offset:4, _:12, _Window:16,
                       _Checksum:16, _Urgent:16, Rest/binary>>) ->
    %% TCP — data offset is in 32-bit words, first 5 words already consumed (20 bytes)
    OptionsLen = (Offset - 5) * 4,
    case Rest of
        <<_Options:OptionsLen/binary, Payload/binary>> when byte_size(Payload) > 0 ->
            {ok, Payload};
        _ ->
            error
    end;
extract_transport(_, _) ->
    error.

%% Parse an HTTP request line, return {Method, Path} or error.
parse_ntrip_request(Data) when is_binary(Data) ->
    case binary:split(Data, <<"\r\n">>) of
        [Line | _] ->
            case binary:split(Line, <<" ">>, [global]) of
                [Method, Path | _] -> {ok, Method, Path};
                _ -> error
            end;
        _ ->
            error
    end.
