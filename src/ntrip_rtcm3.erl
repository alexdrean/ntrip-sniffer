-module(ntrip_rtcm3).
-export([init_crc_table/0, crc24q/1, extract_frames/1]).

-define(CRC24Q_POLY, 16#1864CFB).

%% Build the 256-entry CRC-24Q lookup table and store in persistent_term.
init_crc_table() ->
    Table = list_to_tuple([crc_entry(I) || I <- lists:seq(0, 255)]),
    persistent_term:put(crc24q_table, Table).

crc_entry(I) ->
    crc_bits(I bsl 16, 8).

crc_bits(CRC, 0) ->
    CRC band 16#FFFFFF;
crc_bits(CRC, N) ->
    CRC1 = CRC bsl 1,
    CRC2 = case CRC1 band 16#1000000 of
        0 -> CRC1;
        _ -> CRC1 bxor ?CRC24Q_POLY
    end,
    crc_bits(CRC2, N - 1).

%% Compute CRC-24Q over a binary.
crc24q(Bin) ->
    Table = persistent_term:get(crc24q_table),
    crc24q(Bin, Table, 0).

crc24q(<<>>, _Table, CRC) ->
    CRC;
crc24q(<<B, Rest/binary>>, Table, CRC) ->
    Index = ((CRC bsr 16) bxor B) band 16#FF,
    CRC1 = (element(Index + 1, Table) bxor (CRC bsl 8)) band 16#FFFFFF,
    crc24q(Rest, Table, CRC1).

%% Extract validated RTCM3 frames from a binary payload.
%% Returns a list of validated frame binaries.
extract_frames(Payload) ->
    extract_frames(Payload, []).

extract_frames(<<>>, Acc) ->
    lists:reverse(Acc);
extract_frames(<<16#D3, 0:6, Length:10, Rest/binary>>, Acc) when byte_size(Rest) >= Length + 3 ->
    <<Body:Length/binary, CRCHi, CRCMid, CRCLo, Remaining/binary>> = Rest,
    ExpectedCRC = (CRCHi bsl 16) bor (CRCMid bsl 8) bor CRCLo,
    Header = <<16#D3, 0:6, Length:10>>,
    case crc24q(<<Header/binary, Body/binary>>) of
        ExpectedCRC ->
            Frame = <<Header/binary, Body/binary, CRCHi, CRCMid, CRCLo>>,
            extract_frames(Remaining, [Frame | Acc]);
        _ ->
            extract_frames(<<0:6, Length:10, Rest/binary>>, Acc)
    end;
extract_frames(<<16#D3, _/binary>>, Acc) ->
    %% Not enough data for a complete frame
    lists:reverse(Acc);
extract_frames(<<_, Rest/binary>>, Acc) ->
    extract_frames(Rest, Acc).
