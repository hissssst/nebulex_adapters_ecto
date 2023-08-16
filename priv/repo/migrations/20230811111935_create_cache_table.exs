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
