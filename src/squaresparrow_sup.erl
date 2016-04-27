-module(squaresparrow_sup).
-behavior(supervisor).

%% Supervisor exports
-export([init/1]).

%% API Exports
-export([start_link/1]).

%%====================================================================
%% API functions
%%====================================================================
start_link(MFA = {_,_}) ->
	start_link(#{start => MFA});
start_link(MFA = {_,_,_}) ->
	start_link(#{start => MFA});
start_link(Spec) when is_map(Spec) ->
	{M, F, A} = case maps:get(start, Spec) of
		{M1, F1}     -> {M1, F1, []};
		{M1, F1, A1} -> {M1, F1, A1}
	end,

	Spec2 = #{
		start    => {M, F, A},
		id       => maps:get(id,       Spec, M),
		restart  => maps:get(restart,  Spec, permanent),
		shutdown => maps:get(shutdown, Spec, 1000),
		type     => maps:get(type,     Spec, worker),
		modules  => maps:get(modules,  Spec, [M])
	},

	supervisor:start_link(?MODULE, Spec2).


%%====================================================================
%% Supervisor callbacks
%%====================================================================
-spec init(term()) -> {ok, supervisor:strategy(), non_neg_integer(), non_neg_integer(), [supervisor:child_spec()]} | ignore.
%% @doc Initializes the supervisor.
%% @end
init(Spec) ->
	Supervisor = {simple_one_for_one, 10, 5},
	Children   = [
		Spec
	],
	{ok, {Supervisor, Children}}.
