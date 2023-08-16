import Config

config :nebulex_adapters_ecto, Nebulex.Adapters.EctoTest.Repo,
  database: "nebulex_adapters_ecto_repo",
  password: System.fetch_env!("POSTGRES_PASSWORD"),
  hostname: System.fetch_env!("POSTGRES_HOST"),
  username: System.fetch_env!("POSTGRES_USER"),
  port: System.fetch_env!("POSTGRES_PORT")

config :nebulex_adapters_ecto, ecto_repos: [Nebulex.Adapters.EctoTest.Repo]

import_config "#{config_env()}.exs"
