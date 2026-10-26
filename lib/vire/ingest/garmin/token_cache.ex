defmodule Vire.Ingest.Garmin.TokenCache do
  @moduledoc """
  Holds one Garmin bearer token per provider connection, in memory only, in an
  ETS table this process owns. A token is kept with a digest of the key it was
  exchanged from, so a connection whose key changes reads as having none.
  """

  use GenServer

  alias Vire.Accounts.ProviderConnection
  alias Vire.Ingest.Garmin.Token

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The token cached for `connection`, or `:error`."
  def fetch(%ProviderConnection{id: id} = connection) do
    digest = digest(connection)

    case :ets.lookup(@table, id) do
      [{^id, ^digest, %Token{} = token}] -> {:ok, token}
      _other -> :error
    end
  end

  @doc "Caches `token` for `connection`, replacing the one before."
  def put(%ProviderConnection{id: id} = connection, %Token{} = token) do
    :ets.insert(@table, {id, digest(connection), token})
    :ok
  end

  @doc "Drops the token cached for `connection`."
  def delete(%ProviderConnection{id: id}) do
    :ets.delete(@table, id)
    :ok
  end

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  defp digest(%ProviderConnection{credential: credential}), do: :crypto.hash(:sha256, credential)
end
