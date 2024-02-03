defmodule DNSCluster do
  @moduledoc """
  Simple DNS based cluster discovery.

  A DNS query is made every `:interval` milliseconds to discover new ips.
  Nodes will only be joined if their node basename matches the basename of the
  current node. For example if `node()` is `myapp-123@fdaa:1:36c9:a7b:198:c4b1:73c6:1`,
  a `Node.connect/1` attempt will be made against every IP returned by the DNS query,
  but will only be successful if there is a node running on the remote host with the same
  basename, for example `myapp-123@fdaa:1:36c9:a7b:198:c4b1:73c6:2`. Nodes running on
  remote hosts, but with different basenames will fail to connect and will be ignored.

  ## Examples

  To start in your supervision tree, add the child:

      children = [
        ...,
        {DNSCluster, query: "myapp.internal"}
      ]

  See the `start_link/1` docs for all available options.

  If you require more advanced clustering options and strategies, see the
  [libcluster](https://hexdocs.pm/libcluster) library.
  """
  use GenServer
  require Logger

  defmodule Resolver do
    @moduledoc false

    require Record
    Record.defrecord(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

    def basename(node_name) when is_atom(node_name) do
      [basename, _] = String.split(to_string(node_name), "@")
      basename
    end

    def connect_node(node_name) when is_atom(node_name), do: Node.connect(node_name)

    def list_nodes, do: Node.list(:visible)

    def lookup(query, type) when is_binary(query) and type in [:a, :aaaa] do
      case :inet_res.getbyname(~c"#{query}", type) do
        {:ok, hostent(h_addr_list: addr_list)} -> addr_list
        {:error, _} -> []
      end
    end
  end

  @doc ~S"""
  Starts DNS based cluster discovery.

  ## Options

    * `:name` - the name of the cluster. Defaults to `DNSCluster`.
    * `:query` - the required DNS query for node discovery, for example: `"myapp.internal"`.
      The value `:ignore` can be used to ignore starting the DNSCluster.
    * `:interval` - the millisec interval between DNS queries. Defaults to `5000`.
    * `:connect_timeout` - the millisec timeout to allow discovered nodes to connect.
      Defaults to `10_000`.

  ## Examples

      iex> DNSCluster.start_link(query: "myapp.internal")
      {:ok, pid}

      iex> DNSCluster.start_link(query: :ignore)
      :ignore
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :query) do
      {:ok, :ignore} ->
        :ignore

      {:ok, query} when is_binary(query) ->
        warn_on_invalid_dist()
        resolver = Keyword.get(opts, :resolver, Resolver)

        state = %{
          interval: Keyword.get(opts, :interval, 5_000),
          basename: resolver.basename(node()),
          query: query,
          log: Keyword.get(opts, :log, false),
          poll_timer: nil,
          connect_timeout: Keyword.get(opts, :connect_timeout, 10_000),
          resolver: resolver
        }

        {:ok, state, {:continue, :discover_ips}}

      {:ok, other} ->
        raise ArgumentError, "expected :query to be a string, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing required :query option in #{inspect(opts)}"
    end
  end

  @impl true
  def handle_continue(:discover_ips, state) do
    {:noreply, do_discovery(state)}
  end

  @impl true
  def handle_info(:discover_ips, state) do
    {:noreply, do_discovery(state)}
  end

  defp do_discovery(state) do
    state
    |> connect_new_nodes()
    |> schedule_next_poll()
  end

  defp connect_new_nodes(%{resolver: resolver, connect_timeout: timeout} = state) do
    node_names = for name <- resolver.list_nodes(), into: MapSet.new(), do: to_string(name)

    ips = discover_ips(state)

    _results =
      ips
      |> Enum.map(fn ip -> "#{state.basename}@#{ip}" end)
      |> Enum.filter(fn node_name -> !Enum.member?(node_names, node_name) end)
      |> Task.async_stream(
        fn new_name ->
          if resolver.connect_node(:"#{new_name}") do
            log(state, "#{node()} connected to #{new_name}")
          end
        end,
        max_concurrency: max(1, length(ips)),
        timeout: timeout
      )
      |> Enum.to_list()

    state
  end

  defp log(state, msg) do
    if level = state.log, do: Logger.log(level, msg)
  end

  defp schedule_next_poll(state) do
    %{state | poll_timer: Process.send_after(self(), :discover_ips, state.interval)}
  end

  defp discover_ips(%{resolver: resolver, query: query}) do
    [:a, :aaaa]
    |> Enum.flat_map(&resolver.lookup(query, &1))
    |> Enum.uniq()
    |> Enum.map(&to_string(:inet.ntoa(&1)))
  end

  defp warn_on_invalid_dist do
    release? = is_binary(System.get_env("RELEASE_NAME"))
    net_state = if function_exported?(:net_kernel, :get_state, 0), do: :net_kernel.get_state()

    cond do
      !net_state ->
        :ok

      net_state.started == :no and release? ->
        Logger.warning("""
        node not running in distributed mode. Ensure the following exports are set in your rel/env.sh.eex file:

            #!/bin/sh

            export RELEASE_DISTRIBUTION=name
            export RELEASE_NODE="myapp@fully-qualified-host-or-ip"
        """)

      net_state.started == :no or
          (!release? and net_state.started != :no and net_state[:name_domain] != :longnames) ->
        Logger.warning("""
        node not running in distributed mode. When running outside of a release, you must start net_kernel manually with
        longnames.
        https://www.erlang.org/doc/man/net_kernel.html#start-2
        """)

      net_state[:name_domain] != :longnames and release? ->
        Logger.warning("""
        node not running with longnames which are required for DNS discovery.
        Ensure the following exports are set in your rel/env.sh.eex file:

            #!/bin/sh

            export RELEASE_DISTRIBUTION=name
            export RELEASE_NODE="myapp@fully-qualified-host-or-ip"
        """)

      true ->
        :ok
    end
  end
end
