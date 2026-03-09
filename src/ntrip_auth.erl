-module(ntrip_auth).
-export([load_users/0, check_auth/1]).

-define(USERS_FILE, "users.conf").

load_users() ->
    case file:read_file(?USERS_FILE) of
        {ok, Data} ->
            Users = parse_users(Data),
            persistent_term:put(ntrip_users, Users),
            io:format("[auth] loaded ~B users from ~s~n", [map_size(Users), ?USERS_FILE]);
        {error, enoent} ->
            persistent_term:put(ntrip_users, none),
            io:format("[auth] no ~s found, authentication disabled~n", [?USERS_FILE])
    end.

parse_users(Data) ->
    Lines = binary:split(Data, <<"\n">>, [global]),
    lists:foldl(fun parse_user_line/2, #{}, Lines).

parse_user_line(Line, Acc) ->
    Clean = binary:replace(Line, <<"\r">>, <<>>, [global]),
    case Clean of
        <<>> -> Acc;
        <<"#", _/binary>> -> Acc;
        _ ->
            case binary:split(Clean, <<":">>) of
                [User, Pass] when byte_size(User) > 0 -> Acc#{User => Pass};
                _ -> Acc
            end
    end.

check_auth(Auth) ->
    case persistent_term:get(ntrip_users, none) of
        none -> ok;
        Users -> verify(Auth, Users)
    end.

verify(none, _Users) -> {error, 401};
verify({basic, User, Pass}, Users) ->
    case maps:find(User, Users) of
        {ok, Pass} -> ok;
        _ -> {error, 401}
    end.
