-module(autocluster_server).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_HEARTBEAT_INTERVAL, timer:seconds(5)).
-define(DEFAULT_IPADDR, {127,0,0,1}).
-define(DEFAULT_MADDR, {224,0,0,1}).
-define(DEFAULT_PORT, 62476).
-define(DEFAULT_LOGGER, fun(Args) -> io:format("~p~n", [Args]) end).
-define(DEFAULT_SOCKET_OPTS, [
    binary, inet,
    {active, true},
    {ip, ?DEFAULT_IPADDR},
    {multicast_ttl, 255},
    {multicast_loop, true},
    {add_membership, {?DEFAULT_IPADDR, ?DEFAULT_MADDR}}
 ]).

-record(state, {socket, heartbeat_timer, ipaddr, port, logger}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    %% set up the heartbeat
    {ok, #state{
        socket = setup_multicast_socket(),
        heartbeat_timer = setup_heartbeat(),
        ipaddr = application:get_env(?SERVER, ipaddr, ?DEFAULT_IPADDR),
        port = application:get_env(?SERVER, port, ?DEFAULT_PORT),
        logger = application:get_env(?SERVER, logger, ?DEFAULT_LOGGER)
    }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(Request, From, State) ->
    logger(State#state.logger, {info, io_lib:format("Received call from ~p: ~p~n", [From, Request])}),
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, State) ->
    logger(State#state.logger, {info, io_lib:format("Received Cast: ~p~n", [Msg])}),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(heartbeat, State = #state{socket=Socket, port=Port, ipaddr=IPAddr}) ->
    case nodes([connected]) of
        [] ->
            Message = {heartbeat, node()},
            ok = gen_udp:send(Socket, IPAddr, Port, term_to_binary(Message));
        _  ->
            timer:cancel(State#state.heartbeat_timer)
    end,
    {noreply, State};
handle_info({udp, _Ref, IPAddr, _Port, _Msg}, State = #state{ipaddr=IPAddr, logger=Logger}) ->
    logger(Logger, {error, heartbeat_loop}),
    {noreply, State};
handle_info({udp, _Ref, _IPAddr, _Port, Msg}, State = #state{logger=Logger}) ->
    handle_heartbeat(Msg, Logger),
    {noreply, State};
handle_info(Info, State = #state{logger=Logger}) ->
    logger(Logger, {error, {unrecognized_message, Info}}),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Creates a heartbeat timer to send a heartbeat message on interval
%%
%% @spec setup_heartbeat() -> TRef.
%% @end
%%--------------------------------------------------------------------
setup_heartbeat() ->
    Interval = application:get_env(?SERVER, heartbeat_interval, ?DEFAULT_HEARTBEAT_INTERVAL),
    {ok, TRef} = timer:send_interval(Interval, heartbeat),
    TRef.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Opens a multicast socket and sets this process as the controller
%%
%% @spec setup_multicast_socket(IPAddress, MAddress, Port) -> Socket.
%% @end
%%--------------------------------------------------------------------
setup_multicast_socket() ->
    Port = application:get_env(?SERVER, port, ?DEFAULT_PORT),
    Opts = application:get_env(?SERVER, socket_opts, ?DEFAULT_SOCKET_OPTS),
    Opts2 = proplists:delete(active, Opts),
    case gen_udp:open(Port, [{active, true}|Opts2]) of
        {ok, Socket} ->
            ok = set_socket_controller(Socket),
            Socket;
        {error, Reason} ->
            throw({cant_open_socket, Reason})
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Sets this process as the controller of a socket
%%
%% @spec set_socket_controller(Socket) -> ok.
%% @end
%%--------------------------------------------------------------------
set_socket_controller(Socket) ->
    case gen_udp:controlling_process(Socket, self()) of
        ok ->
            ok;
        {error, Reason} ->
            throw({cant_set_socket_controller, Reason})
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs events using a predefined function
%%
%% @spec logger(Fun, Args) -> ok.
%% @end
%%--------------------------------------------------------------------
logger({Module, Function}, Args) when is_atom(Module), is_atom(Function) ->
    erlang:apply(Module, Function, [Args]),
    ok;
logger(Function, Args) when is_function(Function) ->
    erlang:apply(Function, [Args]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks incoming multicast messages for node heartbeats, and tries
%% to join any nodes that are found.
%%
%% @spec logger(Fun, Args) -> ok.
%% @end
%%--------------------------------------------------------------------
handle_heartbeat(Msg, Logger) ->
    try binary_to_term(Msg) of
        {heartbeat, Node} when is_atom(Node) ->
            join_node(Node, Logger)
    catch
        error:badarg ->
            logger(Logger, {error, {malformed_heartbeat, Msg}});
        Type:Pattern ->
            logger(Logger, {error, {Type, Pattern}})
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Joins a node or logs a failure.
%%
%% @spec logger(Fun, Args) -> ok.
%% @end
%%--------------------------------------------------------------------
join_node(Node, Logger) ->
    case net_adm:ping(Node) of
        pong ->
            ok;
        pang ->
            logger(Logger, {error, {misconfigured_node, Node}})
    end.
