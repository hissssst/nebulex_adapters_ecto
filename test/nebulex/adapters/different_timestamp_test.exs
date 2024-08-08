defmodule Nebulex.Adapters.Ecto.DifferentTimestampTest do
  use ExUnit.Case, async: false

  alias Nebulex.Adapters.Ecto.GC
  alias Nebulex.Adapters.EctoTest.Repo

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex_adapters_ecto,
      adapter: Nebulex.Adapters.Ecto
  end

  setup_all do
    Repo.start_link()
    Cache.start_link(timestamp_mfa: {Function, :identity, [123]})

    :ok
  end

  setup do
    Cache.delete_all()
    [{_, gc, _, _}] = Supervisor.which_children(Cache)
    GC.force_gc(gc)
    :ok
  end

  test "Touched at set correctly" do
    import Ecto.Query

    Cache.put(:x, 1)

    assert [123] == Repo.all(from(x in "cache_table", select: x.touched_at))
  end
end
