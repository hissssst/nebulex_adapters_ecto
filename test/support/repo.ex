defmodule Nebulex.Adapters.EctoTest.Repo do
  use Ecto.Repo,
    otp_app: :nebulex_adapters_ecto,
    adapter: Ecto.Adapters.Postgres
end
