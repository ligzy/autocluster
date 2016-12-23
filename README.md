autocluster - Automatic clustering for Erlang nodes
=====

Add this application to your own Erlang programs to enable automatic clustering for new nodes.

configuration
=====

This app can be be included from source with [rebar3](https://www.rebar3.org/) by adding it as a [dependency](https://www.rebar3.org/docs/dependencies):

```erlang
{deps,[
    {autocluster, {git, "git://github.com/shaneutt/autocluster.git", {branch, "master"}}}
]}.
```

Once it is added, you can configure it via `app.config`:

```erlang
[
    {autocluster, [
        {heartbeat_interval, 5000},
        {ipaddr, {127,0,0,1}},
        {maddr, {224,0,0,1}},
        {port, 62476},
        {socket_opts, [
            binary, inet,
            {active, true},
            {ip, {127,0,0,1}},
            {multicast_ttl, 255},
            {multicast_loop, true},
            {add_membership, {{127,0,0,1}, {224,0,0,1}}}
        ]},
        {logger, {module, function}}
    ]},
    %% other configurations
].
```

(The entries in the above configuration, except for `logger`, are the defaults set for each option unless set otherwise)

For the `socket_opts` option, check [the gen_udp documentation](http://erlang.org/doc/man/gen_udp.html) (note that `active` will be forced to "true" as a requirement of the application).

The `logger` option allows you to define a module and function that logs will be sent to. This function should accept one argument of the following type:

```erlang
my_logger_function({Status :: atom(), Message :: string()}) -> ok.
```

usage
=====

Using the above configuration, two or more nodes that can reach eachother via multicast (and the `socket_opts` provided) will be joined:

* Once a node becomes a member of a cluster, it stops sending out a heartbeat (but listens for the heartbeats of others)

* Once a node receives a heartbeat it will attempt to join that node and log any failures

