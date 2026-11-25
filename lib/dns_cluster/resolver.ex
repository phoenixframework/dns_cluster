defmodule DNSCluster.Resolver do
  @moduledoc false

  require Logger
  require Record
  Record.defrecord(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

  def basename(node_name) when is_atom(node_name) do
    [basename, _] = String.split(to_string(node_name), "@")
    basename
  end

  def connect_node(node_name) when is_atom(node_name), do: Node.connect(node_name)

  def list_nodes, do: Node.list(:visible)

  def lookup(query, type) when is_binary(query) and type in [:a, :aaaa] do
    query
    |> getbyname(type)
    |> addr_list(query, type)
  end

  def lookup(query, type) when is_binary(query) and type in [:srv] do
    query
    |> getbyname(type)
    |> addr_list(query, type)
    |> lookup_hosts()
  end

  defp getbyname(query, type), do: :inet_res.getbyname(~c"#{query}", type)

  @doc false
  def addr_list({:ok, hostent(h_addr_list: addr_list)}, _query, _type), do: addr_list
  def addr_list({:error, reason}, query, type), do: lookup_failed(query, type, reason)

  # :nodata only means the name exists without records of this type (for
  # example no AAAA record), which is expected with the default resource types.
  defp lookup_failed(_query, _type, :nodata), do: []

  defp lookup_failed(query, type, reason) do
    Logger.warning(
      "DNSCluster could not resolve #{inspect(query)} (#{inspect(type)}): #{inspect(reason)}"
    )

    []
  end

  defp lookup_hosts(srv_list) do
    srv_list
    |> Enum.flat_map(fn {_prio, _weight, _port, host_name} ->
      case :inet.gethostbyname(host_name) do
        {:ok, hostent(h_addr_list: addr_list)} -> addr_list
        {:error, _} -> []
      end
    end)
  end
end
