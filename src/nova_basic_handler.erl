-module(nova_basic_handler).
-export([
         handle_json/4,
         handle_ok/4,
         handle_status/4,
         handle_redirect/4,
         handle_cowboy_req/4
        ]).

-include_lib("nova/include/nova.hrl").

-type mod_fun() :: {Module :: atom(), Function :: atom()} | undefined.
-type erlydtl_vars() :: map() | [{Key :: atom() | binary() | string(), Value :: any()}].


%%--------------------------------------------------------------------
%% @doc
%% Handler for JSON. It takes two different return objects:
%%   - {json, JSON :: map()} which returns the JSON encoded to the user.
%%     If the operation was a POST the HTTP-status code will be 201, otherwise
%%     200.
%%   - {json, StatusCode :: integer(), Headers :: map(), JSON :: map()} - Same
%%     operation as the above except you can set custom status code and custom
%%     headers.
%% @end
%%--------------------------------------------------------------------
-spec handle_json({json, JSON :: map()} | {json, StatusCode :: integer(), Headers :: map(), JSON :: map()},
                  ModFun :: mod_fun(), Req :: cowboy_req:req(), State :: nova_http_handler:nova_http_state()) ->
                         nova_handlers:handler_return() | no_return().
handle_json({json, StatusCode, Headers, JSON}, _ModFun, Req, State) ->
    try json:encode(JSON, [binary, maps]) of
        EncodedJSON ->
            Headers0 = maps:merge(#{<<"content-type">> => <<"application/json">>}, Headers),
            {ok, StatusCode, Headers0, EncodedJSON, State}
    catch
        ?WITH_STACKTRACE(Type, Reason, Stacktrace)
          ?ERROR("Error while processing JSON. Type: ~p Reason: ~p Stacktrace: ~p", [Type, Reason, Stacktrace]),
          handle_status({status, 500}, undefined, Req, State)
    end;
handle_json({json, JSON}, ModFun, Req = #{method := Method}, State) ->
    case Method of
        <<"POST">> ->
            handle_json({json, 201, #{}, JSON}, ModFun, Req, State);
        _ ->
            handle_json({json, 200, #{}, JSON}, ModFun, Req, State)
    end.



%%--------------------------------------------------------------------
%% @doc
%% Handler for regular views.
%% @end
%%--------------------------------------------------------------------
-spec handle_ok({ok, Variables :: erlydtl_vars()} | {ok, Variables :: erlydtl_vars(), Options :: map()},
                ModFun :: mod_fun(), Req :: cowboy_req:req(), State :: nova_http_handler:nova_http_state()) ->
                       nova_handlers:handler_return() | no_return().
handle_ok({ok, Variables}, {Mod, _Func}, _Req, State) ->
    %% Derive the view from module
    ViewNameAtom = get_view_name(Mod),
    handle_view(ViewNameAtom, Variables, #{}, State);
handle_ok({ok, Variables, Options}, {Mod, _Func}, _Req, State) ->
    View =
        case maps:get(view, Options, undefined) of
            undefined ->
                ViewName = atom_to_list(Mod) ++ "_dtl",
                list_to_atom(ViewName);
            CustomView when is_atom(CustomView) ->
                ViewName = atom_to_list(CustomView) ++ "_dtl",
                list_to_atom(ViewName);
            CustomView ->
                list_to_atom(CustomView ++ "_dtl")
        end,
    handle_view(View, Variables, Options, State).

-spec handle_status({status, StatusCode :: integer()} | {status, StatusCode :: integer(), ExtraHeaders :: map()},
                    ModFun :: mod_fun(), Req :: cowboy_req:req(), State :: nova_http_handler:nova_http_state()) ->
                           nova_handlers:handler_return().
handle_status({status, Status, ExtraHeaders}, _ModFun, Req, State) ->
    {ok, _StatusCode, StatusHeaders, StatusBody, _} = nova_router:status_page(Status, Req),
    Headers0 = maps:merge(ExtraHeaders, StatusHeaders),
    {ok, Status, Headers0, StatusBody, State};
handle_status({status, Status}, ModFun, Req, State) ->
    handle_status({status, Status, #{}}, ModFun, Req, State).


-spec handle_redirect({redirect, Route :: list()}, ModFun :: mod_fun(), Req :: cowboy_req:req(),
                      State :: nova_http_handler:nova_http_state()) ->
                             nova_handlers:handler_return().
handle_redirect({redirect, Route}, _ModFun, _Req, State) ->
    Headers = #{<<"Location">> => list_to_binary(Route)},
    {ok, 302, Headers, <<>>, State}.

handle_cowboy_req({cowboy_req, CowboyReq}, _ModFun, _Req, State) ->
    {ok, CowboyReq, State}.






%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_view(View, Variables, Options, State) ->
    {ok, HTML} = render_dtl(View, Variables, []),
    Headers =
        case maps:get(headers, Options, undefined) of
            undefined ->
                #{<<"content-type">> => <<"text/html">>};
            UserHeaders ->
                UserHeaders
        end,
    StatusCode = maps:get(status_code, Options, 200),
    {ok, StatusCode, Headers, HTML, State}.


render_dtl(View, Variables, Options) ->
    case code:is_loaded(View) of
        false ->
            %% Cast a warning since the module could not be found
            ?ERROR("Could not render ~p cause it's not loaded.", [View]);
        _ ->
            View:render(Variables, Options)
    end.


get_view_name(Mod) when is_atom(Mod) ->
    StrName = get_view_name(erlang:atom_to_list(Mod)),
    erlang:list_to_atom(StrName);
get_view_name([$_, $c, $o, $n, $t, $r, $o, $l, $l, $e, $r]) ->
    "_dtl";
get_view_name([H|T]) ->
    [H|get_view_name(T)].