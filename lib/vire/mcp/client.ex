defmodule Vire.Mcp.Client do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_redirect_uris 10

  schema "mcp_clients" do
    field :client_id, :string
    field :client_secret_hash, :string, redact: true
    field :name, :string
    field :redirect_uris, {:array, :string}

    timestamps()
  end

  @doc """
  A changeset for a client registering itself with a name and its redirect
  URIs: https anywhere, or http on localhost or 127.0.0.1, without a fragment.
  """
  def registration_changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :redirect_uris])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :redirect_uris])
    |> validate_length(:name, max: 200)
    |> validate_length(:redirect_uris, min: 1, max: @max_redirect_uris)
    |> validate_change(:redirect_uris, fn :redirect_uris, uris ->
      Enum.flat_map(uris, &redirect_uri_errors/1)
    end)
    |> unique_constraint(:client_id)
  end

  defp redirect_uri_errors(uri) do
    if String.length(uri) <= 2000 and allowed_redirect_uri?(URI.new(uri)) do
      []
    else
      [
        redirect_uris: "must be https URIs, or http on localhost or 127.0.0.1, without a fragment"
      ]
    end
  end

  defp allowed_redirect_uri?({:ok, %URI{fragment: nil, scheme: "https", host: host}}),
    do: host not in [nil, ""]

  defp allowed_redirect_uri?({:ok, %URI{fragment: nil, scheme: "http", host: host}}),
    do: host in ["localhost", "127.0.0.1"]

  defp allowed_redirect_uri?(_parsed), do: false
end
