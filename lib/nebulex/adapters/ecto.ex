defmodule Nebulex.Adapters.Ecto do
  @moduledoc """
  Adapter backed by generic Ecto table.
  Designed to be used as a highest level cache for data persistence.
  """

  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Transaction
  @behaviour Nebulex.Adapter.Queryable

  @compile :inline

  require Logger
  use Nebulex.Adapter.Stats

  alias Nebulex.Adapter.Stats
  alias Nebulex.Adapters.Ecto.GC
  import Nebulex.Adapter, only: [defspan: 2]

  import :erlang, only: [term_to_binary: 1, binary_to_term: 1]
  import Ecto.Query

  ## Nebulex.Adapter

  @impl true
  def init(opts) do
    stats_counter = Stats.init(opts)
    %{repo: repo, table: table} = opts = Map.new(opts)
    check(repo, table)

    opts =
      %{
        gc_timeout: :timer.hours(1),
        strategy: :lrw,
        max_amount: 100_000
      }
      |> Map.merge(opts)
      |> Map.put(:stats_counter, stats_counter)

    child_spec = GC.child_spec(opts)
    {:ok, child_spec, opts}
  end

  @impl true
  defmacro __before_compile__(_) do
    :ok
  end

  ## Nebulex.Adapter.Entry

  defspan delete(meta, key, _opts) do
    %{repo: repo, table: table} = meta
    key = term_to_binary(key)
    repo.delete_all(from(x in table, where: x.key == ^key))
    :ok
  end

  defspan expire(meta, key, ttl) do
    %{repo: repo, table: table} = meta

    table
    |> base_query(key, meta)
    |> repo.update_all(set: [ttl: ttl])
    |> hit?()
  end

  defspan get(meta, key, _opts) do
    %{repo: repo, table: table, strategy: strategy} = meta

    case strategy do
      :lrw ->
        table
        |> base_query(key, meta)
        |> select([x], x.value)
        |> repo.all()
        |> case do
          [value] -> binary_to_term(value)
          [] -> nil
        end

      :lru ->
        table
        |> base_query(key, meta)
        |> select([x], x.value)
        |> repo.update_all(set: [touched_at: now(meta)])
        |> case do
          {1, [value]} -> binary_to_term(value)
          {0, []} -> nil
        end
    end
  end

  defspan get_all(meta, keys, _opts) do
    %{repo: repo, table: table, strategy: strategy} = meta
    now = now(meta)
    keys = Enum.map(keys, &term_to_binary/1)

    case strategy do
      :lrw ->
        from(x in table,
          where:
            (is_nil(x.ttl) or x.touched_at + x.ttl >= ^now) and
              x.key in ^keys,
          select: {x.key, x.value}
        )
        |> repo.all()

      :lru ->
        from(x in table,
          where:
            (is_nil(x.ttl) or x.touched_at + x.ttl >= ^now) and
              x.key in ^keys,
          select: {x.key, x.value}
        )
        |> repo.update_all(set: [touched_at: now(meta)])
        |> elem(1)
    end
    |> Map.new(fn {key, value} ->
      {binary_to_term(key), binary_to_term(value)}
    end)
  end

  defspan has_key?(meta, key) do
    %{repo: repo, table: table, strategy: strategy} = meta

    query = base_query(table, key, meta)

    case strategy do
      :lrw ->
        query
        |> select([x], 1)
        |> repo.all()
        |> case do
          [] -> false
          [_] -> true
        end

      :lru ->
        query
        |> select([x], 1)
        |> repo.update_all(set: [touched_at: now(meta)])
        |> case do
          {0, _} -> false
          {1, _} -> true
        end
    end
  end

  defspan put(state, key, value, ttl, kind, opts) do
    do_put(state, key, value, ttl, kind, opts)
  end

  @doc false
  def do_put(%{repo: repo, table: table} = meta, key, value, ttl, :put, _opts) do
    entry = to_entry(key, value, ttl, now(meta))

    table
    |> repo.insert_all([entry],
      on_conflict: {:replace, [:value, :ttl, :touched_at]},
      conflict_target: :key
    )
    |> hit?()
  end

  def do_put(%{repo: repo, table: table} = meta, key, value, ttl, :put_new, _opts) do
    entry = to_entry(key, value, ttl, now(meta))

    table
    |> repo.insert_all([entry], on_conflict: :nothing, conflict_target: :key)
    |> hit?()
  end

  def do_put(%{repo: repo, table: table} = meta, key, value, ttl, :replace, _opts) do
    ttl = with :infinity <- ttl, do: nil

    to_set = [
      value: term_to_binary(value),
      ttl: ttl,
      touched_at: now(meta)
    ]

    table
    |> base_query(key, meta)
    |> repo.update_all(set: to_set)
    |> hit?()
  end

  defspan put_all(meta, entries, ttl, on_write, _opts) do
    do_put_all(meta, entries, ttl, on_write)
  end

  @doc false
  def do_put_all(%{repo: repo, table: table} = meta, entries, ttl, :put) do
    now = now(meta)
    entries = Enum.map(entries, fn {key, value} -> to_entry(key, value, ttl, now) end)

    table
    |> repo.insert_all(entries,
      on_conflict: {:replace, [:value, :ttl, :touched_at]},
      conflict_target: :key
    )
    |> hit?()
  end

  def do_put_all(%{repo: repo, table: table} = meta, entries, ttl, :put_new) do
    now = now(meta)
    entries = Enum.map(entries, fn {key, value} -> to_entry(key, value, ttl, now) end)

    table
    |> repo.insert_all(entries, on_conflict: :nothing, conflict_target: :key)
    |> hit?()
  end

  defspan take(meta, key, _opts) do
    %{repo: repo, table: table} = meta

    table
    |> base_query(key, meta)
    |> select([x], x.value)
    |> repo.delete_all()
    |> case do
      {1, [value]} -> binary_to_term(value)
      {0, []} -> nil
    end
  end

  defspan touch(meta, key) do
    %{repo: repo, table: table} = meta

    table
    |> base_query(key, meta)
    |> repo.update_all(set: [touched_at: now(meta)])
    |> hit?()
  end

  defspan ttl(meta, key) do
    %{repo: repo, table: table} = meta

    table
    |> base_query(key, meta)
    |> select([x], x.ttl)
    |> repo.all()
    |> case do
      [ttl] -> ttl
      [] -> nil
    end
  end

  defspan update_counter(meta, key, amount, ttl, default, _opts) do
    %{repo: repo} = meta

    {:ok, result} =
      repo.transaction(fn ->
        case get(meta, key, []) do
          int when is_integer(int) ->
            value = int + amount
            put(meta, key, value, ttl, :put, [])
            value

          _ ->
            put(meta, key, default, ttl, :put, [])
            default
        end
      end)

    result
  end

  ## Nebulex.Adapter.Transaction

  defspan transaction(meta, _opts, func) do
    %{repo: repo} = meta
    {:ok, result} = repo.transaction(func)
    result
  end

  defspan in_transaction?(meta) do
    %{repo: repo} = meta
    repo.in_transaction?()
  end

  ## Nebulex.Adapter.Queryable

  defspan execute(state, kind, query, opts) do
    do_execute(state, kind, query, opts)
  end

  @doc false
  def do_execute(%{repo: repo, table: table} = meta, :all, nil, _opts) do
    now = now(meta)

    from(x in table,
      where: is_nil(x.ttl) or x.touched_at + x.ttl >= ^now,
      select: x.value
    )
    |> repo.all()
    |> Enum.map(&binary_to_term/1)
  end

  def do_execute(%{repo: repo, table: table} = meta, :count_all, nil, _opts) do
    now = now(meta)

    from(x in table,
      where: is_nil(x.ttl) or x.touched_at + x.ttl >= ^now,
      select: x.value
    )
    |> repo.aggregate(:count)
  end

  def do_execute(%{repo: repo, table: table}, :delete_all, nil, _opts) do
    {count, _} = repo.delete_all(table)
    count
  end

  def do_execute(_, _, query, _) do
    raise Nebulex.QueryError,
      message: "Ecto adapter supports only nil queries. Got #{inspect(query)}"
  end

  defspan stream(meta, query, _opts) do
    case query do
      nil ->
        %{repo: repo, table: table} = meta

        from(x in table, select: x.value)
        |> repo.stream()
        |> Stream.map(&binary_to_term/1)

      _ ->
        raise Nebulex.QueryError,
          message: "Ecto adapter supports only nil queries. Got #{inspect(query)}"
    end
  end

  ## Helpers

  defp to_entry(key, value, ttl, now) do
    ttl = with :infinity <- ttl, do: nil

    %{
      value: term_to_binary(value),
      key: term_to_binary(key),
      ttl: ttl,
      touched_at: now
    }
  end

  defp base_query(table, key, meta) do
    key = term_to_binary(key)

    now = now(meta)

    from(x in table,
      where:
        (is_nil(x.ttl) or x.touched_at + x.ttl >= ^now) and
          x.key == ^key
    )
  end

  @doc false
  def now(meta) do
    {m, f, a} = Map.get(meta, :timestamp_mfa, {:erlang, :monotonic_time, [:millisecond]})
    apply(m, f, a)
  end

  defp hit?({0, _}), do: false
  defp hit?({_, _}), do: true

  defp check(repo, table) do
    repo.query!("SELECT 1")
    repo.query!("SELECT * FROM #{table} LIMIT 1")
    :ok
  rescue
    e ->
      Logger.error(
        "It seems that your database is not yet configured for " <>
          "Nebulex.Adapters.Ecto. Please, refer to the documentation"
      )

      reraise e, __STACKTRACE__
  end
end
