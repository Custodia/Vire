defmodule VireWeb.OAuthRegistrationController do
  use VireWeb, :controller

  alias Vire.Mcp

  def create(conn, params) do
    attrs = %{name: params["client_name"], redirect_uris: params["redirect_uris"]}

    case Mcp.register_client(attrs) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> json(%{
          client_id: client.client_id,
          client_id_issued_at: DateTime.to_unix(client.inserted_at),
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"],
          token_endpoint_auth_method: "none"
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(registration_error(changeset))
    end
  end

  defp registration_error(%Ecto.Changeset{errors: errors}) do
    case Keyword.fetch(errors, :redirect_uris) do
      {:ok, {message, _opts}} ->
        %{error: "invalid_redirect_uri", error_description: "redirect_uris #{message}"}

      :error ->
        [{field, {message, _opts}} | _] = errors
        %{error: "invalid_client_metadata", error_description: describe(field, message)}
    end
  end

  defp describe(:name, message), do: "client_name #{message}"
end
