defmodule Nebulex.Adapters.Ecto.GC do
  @moduledoc false
  # Simplest GenServer which is used to delete stale entries

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    %{
      table: table,
      repo: repo,
      gc_timeout: gc_timeout,
      max_amount: max_amount,
      telemetry: telemetry,
      telemetry_prefix: telemetry_prefix
    } = opts

    state = %{
      timer: nil,
      table: table,
      repo: repo,
      timeout: gc_timeout,
      max_amount: max_amount
    }

    state =
      if telemetry do
        Map.put(state, :telemetry_prefix, telemetry_prefix)
      else
        state
      end

    {:ok, restart_timer(state)}
  end

  def handle_info(:tick, %{telemetry_prefix: prefix} = state) do
    :telemetry.span(prefix ++ [:gc], %{}, fn -> {collect_garbage(state), %{}} end)
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
    %{repo: repo, table: table, max_amount: max_amount} = state
    import Ecto.Query

    now = :erlang.monotonic_time(:millisecond)

    # Remove stale entries
    repo.delete_all(from(x in table, where: x.touched_at + x.ttl < ^now))

    # Remove oldest and exceeding entries
    repo.delete_all(
      from(x in table,
        where:
          ctid() in subquery(
            from(x in table, select: ctid(), order_by: x.touched_at, offset: ^max_amount)
          )
      )
    )

    repo.query!("VACUUM #{table}")
    :ok
  end
end
