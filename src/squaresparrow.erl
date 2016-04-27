-module(squaresparrow).
-behavior(gen_server).

%% GenServer exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% API exports
-export([
	start_link/1, start_link/2,
	add_workers/2, add_workers/3,
	call/2, call/3, call_rr/2, call_rr/3, call_shard/3, call_shard/4,
	cast/2, cast_rr/2, cast_shard/3, cast_all/2, 
	send/2, send_rr/2, send_shard/3, send_all/2
]).

-record(squaresparrow, {
	supervisor    :: pid(),
	workers = #{} :: #{},
	delayed = #{} :: #{},
	count   = 0   :: integer(),
	next    = 0   :: integer()
}).

%%====================================================================
%% API functions
%%====================================================================
-spec start_link(Spec :: {atom(),atom()} | {atom(), atom(), list()} | #{}) -> term().
%% @doc Starts the roundrobin engine.
%% @end
start_link(Spec) -> start_workers(Spec, gen_server:start_link(?MODULE, Spec, [])).

-spec start_link(Name :: term(), Spec :: {atom(),atom()} | {atom(), atom(), list()} | #{}) -> term().
%% @doc Starts a named roundrobin engine.
%%      Same as roundrobin/3 M,F,[]
%% @end
start_link(Name, Spec) -> start_workers(Spec, gen_server:start_link(Name, ?MODULE, Spec, [])).

-spec add_workers(pid() | atom(), Count :: integer()) -> ok | {error, term()}.
%% @doc Adds a worker to the roundrobin pool with the default arguments.
%%      Same as add_worker(default).
%% @end
add_workers(Proc, Count) -> add_workers(Proc, Count, []).

-spec add_workers(pid() | atom(), Count :: integer(), Args :: list()) -> ok | {error, term()}.
%% @doc Adds a worker to the roundrobin pool with specialized arguments.
%% @end
add_workers(Proc, Count, Args) -> gen_server:call(Proc, {add_workers, Count, Args}).

%%====================================================================
%% Call functions
%%====================================================================
call(Proc, Message) ->
	call(Proc, Message, 5000).
call(Proc, Message, Timeout) ->
	call_rr(Proc, Message, Timeout).

call_rr(Proc, Message) ->
	call_rr(Proc, Message, 5000).
call_rr(Proc, Message, Timeout) ->
	gen_call(get_worker(Proc), Message, Timeout).
	
call_shard(Proc, Target, Message) ->
	call_shard(Proc, Target, Message, 5000).
call_shard(Proc, Target, Message, Timeout) ->
	gen_call(get_worker(Proc, Target), Message, Timeout).

gen_call(Proc, Message, Timeout) ->
	case Proc of
		{ok, Worker} ->
			gen_server:call(Worker, Message, Timeout);
		{caution, _} ->
			{error, "Process would call itself"}
	end.

%%====================================================================
%% Cast message functions
%%====================================================================
cast(Proc, Message) ->
	cast_rr(Proc, Message).

cast_rr(Proc, Message) ->
	gen_cast(get_worker(Proc), Message).

cast_shard(Proc, Target, Message) ->
	gen_cast(get_worker(Proc, Target), Message).

gen_cast(Proc, Message) ->
	case Proc of
		{Atom, Worker} when Atom =:= ok orelse Atom =:= caution ->
			gen_server:cast(Worker, Message)
	end.

cast_all(Proc, Message) ->
	gen_server:cast(Proc, {'$cast_all', Message}).

%%====================================================================
%% Send info functions
%%====================================================================
send(Proc, Message) ->
	send_rr(Proc, Message).

send_rr(Proc, Message) ->
	gen_send(get_worker(Proc), Message).

send_shard(Proc, Target, Message) ->
	gen_send(get_worker(Proc, Target), Message).

gen_send(Proc, Message) ->
	case Proc of
		{Atom, Worker} when Atom =:= ok orelse Atom =:= caution ->
			erlang:send(Worker, Message)
	end.

send_all(Proc, Message) ->
	gen_server:cast(Proc, {'$send_all', Message}).

%%====================================================================
%% gen_server functions
%%====================================================================
-spec init(term()) -> gen_spec:gs_init_res(#squaresparrow{}).
%% @doc Initialize a squaresparrow.
%% @end
init(Spec) ->
	case squaresparrow_sup:start_link(Spec) of
		{ok, Supervisor} ->
			
			{ok, #squaresparrow{supervisor = Supervisor}};
		_ ->
			ignore
	end.

-spec handle_call(term(), gen_spec:from(), #squaresparrow{}) -> term().
%% @doc Handle requests.
%% @end
handle_call(
	{add_workers, New, Args},
	_,
	S = #squaresparrow{
		supervisor = Supervisor,
		workers    = Workers,
		count      = Count
	}
) ->
	{Workers2, Count2} = lists:foldl(
		fun(_, {Workers1, Count1}) ->
			{ok, Pid} = supervisor:start_child(Supervisor, Args),
			erlang:monitor(process, Pid),
			{Workers1#{Pid => Count1, Count1 => Pid}, Count1+1}
		end,
		{Workers, Count},
		lists:seq(1, New)
	),
	{reply, ok, S#squaresparrow{workers=Workers2, count=Count2}};

handle_call(
	{get_worker, any, _Caller}, 
	_, 
	S = #squaresparrow{count=0}
) ->
	{reply, {error, "No worker available"}, S};
handle_call({get_worker, any, Caller}, _, S = #squaresparrow{}) ->
	{Result, S2} = get_next_worker(Caller, S),
	{reply, Result, S2};
handle_call(
	{get_worker, Target, Caller}, 
	From, 
	S = #squaresparrow{
		workers = Workers,
		delayed = Delayed,
		count   = Count
	}
) ->
	Target2 = case Target of
		_ when is_integer(Target) -> Target;
		_ -> erlang:phash2(Target, Count)
	end,
	
	case maps:get(Target2, Workers, undefined) of
		undefined  ->
			{reply, {error, {"Invalid target", Target, Target2}}, S};
		restarting ->
			Queue = maps:get(Target2, Delayed, []),
			{noreply, S#squaresparrow{delayed=maps:put(Target2, [From|Queue], Delayed)}};
		Caller     ->
			{reply, {caution, Caller}, S};
		Worker     ->
			{reply, {ok, Worker}, S}
	end;
handle_call(_, _, S) ->
	{reply, {error, unhandled}, S}.

-spec handle_cast(term(), #squaresparrow{}) -> gen_spec:gs_cast_res(#squaresparrow{}).
%% @doc Handle cast notifications.
%% @end
handle_cast({'$cast_all', Message}, S = #squaresparrow{workers = Workers}) ->
	do_for_all(fun gen_server:cast/2, Message, Workers),
	{noreply, S};
handle_cast({'$send_all', Message}, S = #squaresparrow{workers = Workers}) ->
	do_for_all(fun erlang:send/2, Message, Workers),
	{noreply, S};
handle_cast(_, S) ->
	{noreply, S}.

-spec handle_info(term(), #squaresparrow{}) -> gen_spec:gs_info_res(#squaresparrow{}).
%% @doc Handle info notifications.
%% @end
handle_info({'DOWN', _, process, Pid, _}, S = #squaresparrow{workers = Workers}) ->
	erlang:send(self(), '$refresh'),
	{noreply, S#squaresparrow{workers = maps:remove(Pid, maps:put(maps:get(Pid, Workers), restarting, Workers))}};
handle_info(
	'$refresh',
	S = #squaresparrow{
		supervisor = Supervisor,
		workers    = Workers,
		delayed    = Delayed
	}
) ->

	%% Get children that we don't know about	
	Children2 = lists:filtermap(
		fun({_, Child, _, _}) ->
			case maps:get(Child, Workers, undefined) of
				undefined ->
					erlang:monitor(process, Child),
					{true, Child};
				_ ->
					false
			end
		end,
		supervisor:which_children(Supervisor)
	),

	%% Get the keys that need a child
	Keys = lists:filter(
		fun
			(K) when is_integer(K) ->
				case maps:get(K, Workers) of
					restarting -> true;
					_          -> false
				end;
			(_) ->
				false
		end,
		maps:keys(Workers)
	),

	%% Stich new to keys
	Updates  = lists:zip(Keys, Children2),
	%% Update workers map
	Workers2 = lists:foldl(
		fun({Key, Child}, Acc) ->
			Acc2 = maps:put(Key, Child, Acc),
			maps:put(Child, Key, Acc2)
		end,
		Workers,
		Updates
	),
	%% Notify those waiting for a specific instance 
	Delayed2 = lists:foldl(
		fun({Key, Child}, Acc) ->
			lists:foreach(fun(X) -> gen_server:reply(X, {ok, Child}) end, maps:get(Key, Acc, [])),
			maps:put(Key, [], Acc)
		end,
		Delayed,
		Updates
	),

	%% If we had more keys then children we need to refresh again
	Refresh = length(Keys) > length(Children2),
	case Refresh of
		false -> ok;
		true  -> erlang:send_after(500, self(), '$refresh')
	end,

	{noreply, S#squaresparrow{workers = Workers2, delayed = Delayed2}};
handle_info(_, S) ->
	{noreply, S}.

-spec terminate(normal | shutdown | {shutdown, term()} | term(), #squaresparrow{}) -> no_return().
%% @doc Perform any last second cleanup.
%% @end
terminate(_, _S) ->
	ok.

-spec code_change({down, term()} | term(), #squaresparrow{}, term()) -> {ok, #squaresparrow{}} | {error, term()}.
%% @doc Handle state changes across revisions.
%% @end
code_change(_, S, _) -> {ok, S}.

%%====================================================================
%% Internal functions
%%====================================================================
start_workers(Spec, {ok, Pid}) when is_map(Spec) ->
	add_workers(Pid, maps:get(workers, Spec, 0)),
	{ok, Pid};
start_workers(_, Else) -> Else.

-spec get_worker(pid() | atom()) -> {ok, pid() | atom()} | {error, term()}.
%% @doc Gets a worker.
%% @end
get_worker(Proc) ->
	get_worker(Proc, any).
get_worker(Proc, Target) ->
	gen_server:call(Proc, {get_worker, Target, self()}).

get_next_worker(Caller, State) ->
	get_next_worker(Caller, State, 0).
get_next_worker(
	_,
	State = #squaresparrow{
		count = Count
	},
	Count
) ->
	{{error, "No worker available"}, State};
get_next_worker(
	Caller,
	State = #squaresparrow{
		workers = Workers,
		count   = Count,
		next    = Next
	},
	Checked
) ->
	case maps:get(Next, Workers) of
		restarting ->
			get_next_worker(Caller, State#squaresparrow{next=(Next+1) rem Count}, Checked+1);
		Worker when Worker =:= Caller ->
			{{caution, Worker}, State#squaresparrow{next=(Next+1) rem Count}};
		Worker ->
			{{ok, Worker}, State#squaresparrow{next=(Next+1) rem Count}}
	end.

do_for_all(Fun, Message, Workers) ->
	lists:foreach(
		fun
			(Worker) when not is_integer(Worker) ->
				case maps:get(Worker, Workers) of
					restarting -> ok;
					Worker2    -> Fun(Worker2, Message)
				end;
			(_) -> ok
		end,
		maps:keys(Workers)
	).
