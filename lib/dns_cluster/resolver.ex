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

  def lookup(query, {:srv, :hostnames}), do: lookup_by_name(query, :srv)

  def lookup(query, {:srv, :ips}) do
    query
    |> lookup_by_name(:srv)
    |> Enum.flat_map(&lookup_host_by_name/1)
  end

  def lookup(query, resource_type) when resource_type in [:a, :aaaa] do
    lookup_by_name(query, resource_type)
  end

  defp lookup_by_name(query, resource_type) do
    case :inet_res.getbyname(~c"#{query}", resource_type) do
      {:ok, hostent(h_addr_list: addr_list)} ->
        if resource_type == :srv do
          for {_prio, _weight, _port, address} <- addr_list, do: address
        else
          addr_list
        end

      {:error, _reason} ->
        []
    end
  end

  defp lookup_host_by_name(query) do
    case :inet_res.gethostbyname(query) do
      {:ok, hostent(h_addr_list: addr_list)} -> addr_list
      {:error, _reason} -> []
    end
  end
end
