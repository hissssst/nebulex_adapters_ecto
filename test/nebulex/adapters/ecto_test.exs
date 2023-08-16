defmodule Nebulex.Adapters.EctoTest do
  use ExUnit.Case
  doctest Nebulex.Adapters.Ecto

  alias Nebulex.Adapters.EctoTest.Repo

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex_adapters_ecto,
      adapter: Nebulex.Adapters.Ecto
  end

  setup_all do
    Repo.start_link()
    Cache.start_link()
    :ok
  end

  setup do
    Cache.delete_all()
    :ok
  end

  test "put and get" do
    assert Cache.put("key1", "value1")
    assert "value1" == Cache.get("key1")
  end

  test "put with ttl" do
    assert Cache.put("key2", "value", ttl: 10)
    Process.sleep(20)
    assert nil == Cache.get("key2")
  end

  test "ttl gc" do
    import Ecto.Query

    assert Cache.put("key3", "value3", ttl: 10)
    assert Cache.put("key4", "value4", ttl: :timer.hours(2))
    Process.sleep(11)
    refute Cache.has_key?("key3")
    assert Cache.has_key?("key4")

    # Because GC timeout is 1 second
    Process.sleep(1000)
    refute Cache.has_key?("key3")
    assert Cache.has_key?("key4")
    key3 = :erlang.term_to_binary("key3")
    assert [] == Repo.all(from(x in "cache_table", select: 1, where: x.key == ^key3))
  end

  test "amount gc" do
    import Ecto.Query

    keys =
      for i <- 1000..2010 do
        key = "key#{i}"
        Cache.put(key, "value#{i}", ttl: :timer.hours(10))
        :erlang.term_to_binary(key)
      end

    # Because GC timeout is 1 second
    Process.sleep(1111)
    amount = Repo.aggregate(from(x in "cache_table", where: x.key in ^keys), :count)
    assert 1000 == amount
  end

  test "put and get_all" do
    assert Cache.put("key5", "value5")
    assert Cache.put("key6", "value6")
    assert Cache.put("key7", "value7")
    assert %{"key5" => "value5", "key6" => "value6"} == Cache.get_all(["key5", "key6"])
  end

  test "put and has_key?" do
    refute Cache.has_key?("key8")
    assert Cache.put("key8", "value8")
    assert Cache.has_key?("key8")
  end

  test "put and delete and has_key?" do
    assert Cache.put("key9", "value9")
    assert Cache.delete("key9")
    refute Cache.has_key?("key9")
  end
end
