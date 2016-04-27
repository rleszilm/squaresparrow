#squaresparrow
OTP library that provides round robin access to a pool of gen_servers.

##Starting an instance
###Creation
	Config = {Module, Function, Args} | 
	         #{
	         	id => child_id(),
			    start => mfargs(),
			    restart => restart(),
			    shutdown => shutdown(),
			    type => worker(),
			    modules => modules()
			 } 


    {ok, Pid :: pid()} = squaresparrow:start_link(Config).

Creates a process that manages a simple_one_for_one supervisor basd on the mfargs() or child_spec() provided. Only the map form if child_spec() is accepted. The map representing a child_spec() may optionally be extended with a workers => Count :: integer() pairing. Doing so will cause Count workers to be started automatically. If this field is ommitted no workers will be started until add_workers is called.

###Adding workers
	ok = squaresparrow:add_workers(Pid, Count),
	ok = squaresparrow:add_workers(Pid, Count, Args :: [Arg1, Arg2...]),

Adds Count workers to the squaresparrow.

##Using 
Three methods are provided to interact with the workers, cast, call, send. The functions call and cast mirror thier gen_server equivalents. The send function mirrors erlang:send.

###_rr
For each function there is a _rr version. The base function is an alias for this method. These methods send thier messages to an available worker in a round robin fashion.

###_shard
For each function there is a _shard version. These functions take an addional key parameter after the pid and before the message to send. Providing a key causes the message to be sent to a specific worker instance. This is not gauranteed if additional workers are added between calls.

#Building
    $ rebar3 compile
