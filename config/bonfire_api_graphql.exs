import Config

config :bonfire_api_graphql,
  otp_app: :your_app_name,
  env: Mix.env(),
  repo_module: Bonfire.Repo
