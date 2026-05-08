# DNSCluster

Simple DNS clustering for distributed Elixir nodes.

## Installation

The package can be installed by adding `dns_cluster` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dns_cluster, "~> 0.2"}
  ]
end
```

Next, you can configure and start the cluster by adding it to your supervision
tree in your `application.ex`:

```elixir
children = [
  {Phoenix.PubSub, ...},
  {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
  MyAppWeb.Endpoint
]
```

Then in your config file, add:

```elixir
config :my_app, :dns_cluster_query, ["app.internal"]
```

If you are deploying with Elixir releases, the release must be set to support longnames and
the node must be named, using its IP address by default. These can be set in your
`rel/env.sh.eex` file:

```sh
#!/bin/sh
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="myapp@fully-qualified-ip"
```

By default, nodes from the same release will have the same cookie. If you want different
applications or releases to connect to each other, then you must set the `RELEASE_COOKIE`,
either in your deployment platform or inside `rel/env.sh.eex`:

```sh
#!/bin/sh
...
export RELEASE_COOKIE="my-app-cookie"
```

## SRV target hostnames

DNSCluster also supports SRV lookups:

```elixir
{DNSCluster,
 query: "_nodes._tcp.nodes.example-cluster.internal",
 resource_types: [:srv]}
```

By default, DNSCluster resolves each SRV target hostname to IP addresses before
building node names. To use the SRV target hostnames as the host part of Erlang
longnames, preserve the SRV targets:

```elixir
{DNSCluster,
 query: {"my_app", "_nodes._tcp.nodes.example-cluster.internal"},
 resource_types: [:srv],
 preserve_srv_targets: true}
```

For an SRV target like `node-1.nodes.example-cluster.internal`, DNSCluster will
connect to:

```elixir
:"my_app@node-1.nodes.example-cluster.internal"
```

The release node name must use the same hostname:

```sh
#!/bin/sh
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="my_app@node-1.nodes.example-cluster.internal"
```

With standard Erlang distribution, the SRV port is not used by `Node.connect/1`.
DNSCluster uses SRV for target discovery, and Erlang distribution resolves the
hostname when connecting.
