defmodule Nebulex.Adapters.Ecto.GC do
  @moduledoc false
  # Simplest GenServer which is used to delete stale entries

  alias Nebulex.Telemetry
  alias Nebulex.Telemetry.StatsHandler

  use GenServer

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec force_gc(pid() | GenServer.name(), timeout()) :: :ok
  def force_gc(name, timeout \\ 30_000) do
    GenServer.call(name, :force_gc, timeout)
  end

  def init(opts) do
    %{
      table: table,
      repo: repo,
      gc_timeout: gc_timeout,
      max_amount: max_amount,
      telemetry: telemetry,
      stats_counter: stats_counter,
      telemetry_prefix: telemetry_prefix
    } = opts

    state = %{
      opts: opts,
      timer: nil,
      table: table,
      repo: repo,
      timeout: gc_timeout,
      max_amount: max_amount,
      stats_counter: stats_counter
    }

    state =
      if telemetry do
        Map.put(state, :telemetry_prefix, telemetry_prefix)
      else
        state
      end

    {:ok, restart_timer(state), {:continue, :attach_stats_handler}}
  end

  def handle_continue(:attach_stats_handler, %{stats_counter: nil} = state) do
    {:noreply, state}
  end

  def handle_continue(:attach_stats_handler, %{stats_counter: stats_counter} = state) do
    Telemetry.attach_many(
      stats_counter,
      [state.telemetry_prefix ++ [:command, :stop]],
      &StatsHandler.handle_event/4,
      stats_counter
    )

    {:noreply, state}
  end

  def handle_call(:force_gc, _from, %{timer: timer, telemetry_prefix: prefix} = state) do
    timer && Process.cancel_timer(timer)
    Telemetry.span(prefix ++ [:gc], %{}, fn -> {collect_garbage(state), %{}} end)
    {:reply, :ok, restart_timer(state)}
  end

  def handle_info(:tick, %{telemetry_prefix: prefix} = state) do
    Telemetry.span(prefix ++ [:gc], %{}, fn -> {collect_garbage(state), %{}} end)
    {:noreply, restart_timer(state)}
  end

  def handle_info(:tick, state) do
    collect_garbage(state)
    {:noreply, restart_timer(state)}
  end

  defp restart_timer(%{timer: timer, timeout: timeout} = state) do
    timer && Process.cancel_timer(timer)
    timer = Process.send_after(self(), :tick, timeout)
    %{state | timer: timer}
  end

  defmacrop ctid, do: quote(do: fragment("ctid"))

  defp collect_garbage(state) do
    %{repo: repo, table: table, max_amount: max_amount, opts: opts} = state
    import Ecto.Query

    now = Nebulex.Adapters.Ecto.now(opts)

    # Remove stale entries
    repo.delete_all(from(x in table, where: x.touched_at + x.ttl < ^now))

    # Remove oldest and exceeding entries
    repo.delete_all(
      from(x in table,
        where:
          ctid() in subquery(
            from(x in table, select: ctid(), order_by: [desc: x.touched_at], offset: ^max_amount)
          )
      )
    )

    repo.query!("VACUUM #{table}")
    :ok
  end
end
