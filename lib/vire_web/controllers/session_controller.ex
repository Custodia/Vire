defmodule VireWeb.SessionController do
  use VireWeb, :controller

  alias Plug.Conn.Utils
  alias Vire.Accounts

  # A cross-site HTML form can post a urlencoded body but not a JSON one.
  plug :require_json_body when action == :create

  def create(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Invalid email or password"}})

      user ->
        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:user_id, user.id)
        |> put_view(VireWeb.UserJSON)
        |> render(:show, user: user)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(VireWeb.ErrorJSON)
    |> render(:"400")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> send_resp(:no_content, "")
  end

  defp require_json_body(conn, _opts) do
    with [content_type] <- get_req_header(conn, "content-type"),
         {:ok, "application", "json", _params} <- Utils.media_type(content_type) do
      conn
    else
      _ ->
        conn
        |> put_status(:unsupported_media_type)
        |> put_view(VireWeb.ErrorJSON)
        |> render(:"415")
        |> halt()
    end
  end
end
