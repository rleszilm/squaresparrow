-module(squaresparrow_example).
-behavior(gen_server).

-include_lib("eunit/include/eunit.hrl").

%% API functions
-export([start_link/0, start_link/1, t/0]).

%% GenServer exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%====================================================================
%% API functions
%%====================================================================
start_link()     -> gen_server:start_link(?MODULE, [],   []).
start_link(Args) -> gen_server:start_link(?MODULE, Args, []).

%%====================================================================
%% gen_server functions
%%====================================================================
-spec init(term()) -> gen_spec:gs_init_res(#{}).
%% @doc Initialize a squaresparrow.
%% @end
init(Spec) ->
	{ok, Spec}.

-spec handle_call(term(), gen_spec:from(), #{}) -> term().
%% @doc Handle requests.
%% @end
handle_call(_, _, S) ->
	{reply, S, S}.

-spec handle_cast(term(), #{}) -> gen_spec:gs_cast_res(#{}).
%% @doc Handle cast notifications.
%% @end
handle_cast(_, S) ->
	{noreply, S}.

-spec handle_info(term(), #{}) -> gen_spec:gs_info_res(#{}).
%% @doc Handle info notifications.
%% @end
handle_info(_, S) ->
	{noreply, S}.

-spec terminate(normal | shutdown | {shutdown, term()} | term(), #{}) -> no_return().
%% @doc Perform any last second cleanup.
%% @end
terminate(_, _S) ->
	ok.

-spec code_change({down, term()} | term(), #{}, term()) -> {ok, #{}} | {error, term()}.
%% @doc Handle state changes across revisions.
%% @end
code_change(Old, State, Extra) -> squaresparrow_revisions:migrate(Old, State, Extra).

%%====================================================================
%% Test functions
%%====================================================================
mfa3_test() ->
	{ok, P} = squaresparrow:start_link({?MODULE, start_link, []}),
	ok      = squaresparrow:add_workers(P, 2),
	ok      = squaresparrow:add_workers(P, 2, [apple]).

spec_test() ->
	{ok, P} = squaresparrow:start_link(#{start => {?MODULE, start_link, []}, workers => 3}),
	ok      = squaresparrow:add_workers(P, 1, [1]),
	ok      = squaresparrow:add_workers(P, 2, [2]),
	ok      = squaresparrow:add_workers(P, 3, [3]),
	ok.

shard_test() ->
	{ok, P} = squaresparrow:start_link(#{start => {?MODULE, start_link, []}}),
	erlang:unlink(P),
	ok      = squaresparrow:add_workers(P, 1, [0]),
	ok      = squaresparrow:add_workers(P, 1, [1]),
	ok      = squaresparrow:add_workers(P, 1, [2]),
	0       = squaresparrow:call_shard(P, 0, test),
	1       = squaresparrow:call_shard(P, 1, test),
	2       = squaresparrow:call_shard(P, 2, test).

t() ->
	{ok, P}  = squaresparrow:start_link({?MODULE, start_link, []}),
	ok       = squaresparrow:add_workers(P, 1),
	_        = squaresparrow:send(P, crash),
	P.



