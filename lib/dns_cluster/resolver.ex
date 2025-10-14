defmodule DNSCluster.Resolver do
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

  def lookup(query, type) when is_binary(query) and type in [:srv] do
    case :inet_res.getbyname(~c"#{query}", type) do
      {:ok, hostent(h_addr_list: srv_list)} ->
        lookup_hosts(srv_list)

      {:error, _} ->
        []
    end
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
