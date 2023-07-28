# DNSCluster

Simple DNS clustering for distributed Elixir nodes.

## Installation

The package can be installed by adding `dns_cluster` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dns_cluster, "~> 0.1.0"}
  ]
end
```

Next, you can configure and start the cluster by adding it to your supservision
tree in your `application.ex`:

```elixir
children = [
  {Phoenix.PubSub, ...},
  {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
  MyAppWeb.Endpoint
]
```

If you are deploying with Elixir releases, you may consider setting these environment variables
in your `rel/env.sh.eex`:

```sh
# run distribution across hosts
export RELEASE_DISTRIBUTION=name

# set if nodes are connected with IPv6
export ERL_AFLAGS="-proto_dist inet6_tcp"
```
