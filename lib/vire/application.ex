defmodule Vire.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Vire.Repo,
      Vire.Ingest.Decoder,
      Vire.Ingest.Garmin.TokenCache,
      {Oban, Application.fetch_env!(:vire, Oban)},
      {Phoenix.PubSub, name: Vire.PubSub},
      VireWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Vire.Supervisor)
  end
end
