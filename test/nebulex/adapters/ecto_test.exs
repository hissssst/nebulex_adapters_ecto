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

  test "put_new and get" do
    assert Cache.put_new("key1", "value1")
    refute Cache.put_new("key1", "value2")
    assert "value1" == Cache.get("key1")
  end

  test "put and take" do
    assert Cache.put(:x, 1)
    assert 1 == Cache.take(:x)
    refute Cache.take(:x)
  end

  test "touch" do
    Cache.put(:x, 1, ttl: 200)
    Process.sleep(100)
    assert Cache.touch(:x)
    Process.sleep(110)
    assert Cache.has_key?(:x)
  end

  test "ttl" do
    Cache.put(:x, 1, ttl: 200)
    assert Cache.ttl(:x) == 200
  end

  test "put and replace and get" do
    assert Cache.put("key1", "value1")
    assert Cache.replace("key1", "value11")
    refute Cache.replace("key2", "value22")
    assert "value11" == Cache.get("key1")
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

  test "put_all and get_all" do
    assert Cache.put_all([
             {"key5", "value5"},
             {"key6", "value6"},
             {"key7", "value7"}
           ])

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

  test "count_all" do
    Cache.put_all(for i <- 1..100, do: {i, i})
    assert Cache.count_all() == 100
  end

  test "decr" do
    Cache.decr(:x, 1, default: 10)
    Cache.decr(:x, 1, default: 10)
    assert Cache.get(:x) == 9
  end

  test "incr" do
    Cache.incr(:x, 1, default: 10)
    Cache.incr(:x, 1, default: 10)
    assert Cache.get(:x) == 11
  end

  test "expire" do
    Cache.put(:x, 1)
    assert Cache.expire(:x, 10)
    Process.sleep(11)
    refute Cache.has_key?(:x)
  end

  test "stats" do
    assert %Nebulex.Stats{} = Cache.stats()
  end

  test "GC removes oldest entries" do
    import Ecto.Query

    Cache.put_all(for i <- 1..1000, do: {i, i})
    Process.sleep(500)
    Cache.put_all(for i <- 1001..2000, do: {i, i})
    Process.sleep(500)

    assert 1000 == Repo.aggregate("cache_table", :count)
    present = :erlang.term_to_binary(1500)
    removed = :erlang.term_to_binary(500)

    assert Repo.exists?(from(x in "cache_table", where: x.key == ^present))
    refute Repo.exists?(from(x in "cache_table", where: x.key == ^removed))
  end
end
