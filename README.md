# Nebulex.Adapters.Ecto

Extremely simple Ecto Postgres adapter for Nebulex Cache library.
Designed to be used as the last level adapter inside multilevel cache.

This adapter implements:
1. Basic key-value cache interface.
2. Cache transactions.
3. Basic queries without patterns.

Cache eviction strategy is LRW or LRU based on the last touched timestamp.

## Installation

In `mix.exs`:
```elixir
defp deps do
  [
    {:nebulex_adapters_ecto, "~> 1.0"}
  ]
end
```

## Setup

### Configuration

In your `runtime.exs`:
```elixir
config :my_app, MyApp.Cache,
  # Available strategies are LRW and LRU
  strategy: :lrw,

  # Repository to be used to access table with cache
  repo: MyApp.Repo,

  # The table as a string (or Schema) which will hold cache data
  table: "cache_table",

  # Maximum amount of data present in the table (in rows)
  max_amount: 1000,

  # Timeout of garbage collection in milliseconds
  gc_timeout: :timer.hours(2)
```

### Table

The most simple migration for cache table would look like this:

```elixir
defmodule Nebulex.Adapters.EctoTest.Repo.Migrations.CreateCacheTable do
  use Ecto.Migration

  def change do
    create table "cache_table" do
      add :key, :binary, primary_key: true
      add :value, :binary
      add :touched_at, :bigint
      add :ttl, :integer
    end

    create unique_index("cache_table", :key)
  end
end
```

However, feel free to create your own indexes. For example, to speed up
garbage collection, I'd suggest using `touched_at + ttl` btree index.
