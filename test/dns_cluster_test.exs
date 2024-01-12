defmodule DNSClusterTest do
  use ExUnit.Case

  @ips %{
    already_known: ~c"fdaa:0:36c9:a7b:db:400e:1352:1",
    new: ~c"fdaa:0:36c9:a7b:db:400e:1352:2",
    no_connect_diff_base: ~c"fdaa:0:36c9:a7b:db:400e:1352:3",
    connect_diff_base: ~c"fdaa:0:36c9:a7b:db:400e:1352:4"
  }

  @new_node :"app@#{@ips.new}"
  def connect_node(@new_node) do
    send(__MODULE__, {:try_connect, @new_node})
    true
  end

  @no_connect_node :"app@#{@ips.no_connect_diff_base}"
  def connect_node(@no_connect_node) do
    false
  end

  @specified_base_node :"specified@#{@ips.connect_diff_base}"
  def connect_node(@specified_base_node) do
    send(__MODULE__, {:try_connect, @specified_base_node})
    true
  end

  def connect_node(_), do: false

  def basename(_node_name), do: "app"

  def lookup(_query, _type) do
    {:ok, dns_ip1} = :inet.parse_address(@ips.already_known)
    {:ok, dns_ip2} = :inet.parse_address(@ips.new)
    {:ok, dns_ip3} = :inet.parse_address(@ips.no_connect_diff_base)
    {:ok, dns_ip4} = :inet.parse_address(@ips.connect_diff_base)

    [dns_ip1, dns_ip2, dns_ip3, dns_ip4]
  end

  def list_nodes do
    [:"app@#{@ips.already_known}"]
  end

  defp wait_for_node_discovery(cluster) do
    :sys.get_state(cluster)
    :ok
  end

  test "discovers nodes", config do
    Process.register(self(), __MODULE__)

    {:ok, cluster} =
      start_supervised(
        {DNSCluster, name: config.test, query: "app.internal", resolver: __MODULE__}
      )

    wait_for_node_discovery(cluster)

    new_node = :"app@#{@ips.new}"
    no_connect_node = :"app@#{@ips.no_connect_diff_base}"
    assert_receive {:try_connect, ^new_node}
    refute_receive {:try_connect, ^no_connect_node}
    refute_receive _
  end

  test "discovers nodes with differing basenames if specified", config do
    Process.register(self(), __MODULE__)

    {:ok, cluster} =
      start_supervised(
        {DNSCluster,
         name: config.test,
         query: ["app.internal", {"specified", "app.internal"}],
         resolver: __MODULE__}
      )

    wait_for_node_discovery(cluster)

    new_node = :"app@#{@ips.new}"
    specified_base_node = :"specified@#{@ips.connect_diff_base}"
    assert_receive {:try_connect, ^new_node}
    assert_receive {:try_connect, ^specified_base_node}
    refute_receive _
  end

  test "discovers nodes with a list of queries", config do
    Process.register(self(), __MODULE__)

    {:ok, cluster} =
      start_supervised(
        {DNSCluster, name: config.test, query: ["app.internal"], resolver: __MODULE__}
      )

    wait_for_node_discovery(cluster)

    new_node = :"app@#{@ips.new}"
    no_connect_node = :"app@#{@ips.no_connect_diff_base}"
    assert_receive {:try_connect, ^new_node}
    refute_receive {:try_connect, ^no_connect_node}
    refute_receive _
  end

  test "query with :ignore does not start child" do
    assert DNSCluster.start_link(query: :ignore) == :ignore
  end
end
