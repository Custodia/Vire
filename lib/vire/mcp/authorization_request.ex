defmodule Vire.Mcp.AuthorizationRequest do
  @moduledoc """
  One request to /oauth/authorize, checked against its client. A request that
  names an unknown client, a redirect URI the client did not register, or no
  S256 challenge is shown as an error and never redirected; any other fault
  goes back to the client's redirect URI.
  """

  alias Vire.Mcp
  alias Vire.Mcp.Client

  defstruct [:client, :redirect_uri, :code_challenge, :state, :params]

  @type t :: %__MODULE__{
          client: Client.t(),
          redirect_uri: String.t(),
          code_challenge: String.t(),
          state: String.t() | nil,
          params: %{String.t() => String.t()}
        }

  @names ~w(response_type client_id redirect_uri code_challenge code_challenge_method
            state scope resource)

  @doc """
  Checks the request's parameters. `resource` is the only resource a request
  may name.
  """
  @spec new(map(), String.t()) ::
          {:ok, t()} | {:error, {:page, String.t()}} | {:error, {:redirect, String.t()}}
  def new(params, resource) do
    params =
      for {name, value} <- params, name in @names, is_binary(value), into: %{}, do: {name, value}

    with {:ok, client} <- fetch_client(params),
         {:ok, redirect_uri} <- fetch_redirect_uri(client, params),
         {:ok, challenge} <- fetch_challenge(params),
         request = %__MODULE__{
           client: client,
           redirect_uri: redirect_uri,
           code_challenge: challenge,
           state: params["state"],
           params: params
         },
         :ok <- check_response_type(request),
         :ok <- check_resource(request, resource) do
      {:ok, request}
    end
  end

  @doc "The client's redirect URI carrying `query` and the request's state."
  def redirect_to(%__MODULE__{redirect_uri: uri, state: state}, query) do
    query = if state, do: Map.put(query, "state", state), else: query
    uri |> URI.new!() |> URI.append_query(URI.encode_query(query)) |> URI.to_string()
  end

  defp fetch_client(%{"client_id" => client_id}) do
    case Mcp.get_client(client_id) do
      %Client{} = client -> {:ok, client}
      nil -> page("The application asking for access is not registered.")
    end
  end

  defp fetch_client(_params), do: page("The request does not name an application.")

  defp fetch_redirect_uri(%Client{redirect_uris: uris}, %{"redirect_uri" => uri}) do
    if uri in uris, do: {:ok, uri}, else: page("The redirect URI is not registered.")
  end

  defp fetch_redirect_uri(_client, _params), do: page("The request has no redirect URI.")

  defp fetch_challenge(%{"code_challenge" => challenge, "code_challenge_method" => "S256"}) do
    if challenge =~ ~r/\A[A-Za-z0-9_-]{43}\z/,
      do: {:ok, challenge},
      else: page("The code challenge is not an S256 challenge.")
  end

  defp fetch_challenge(_params), do: page("The request has no S256 code challenge.")

  defp check_response_type(%__MODULE__{params: %{"response_type" => "code"}}), do: :ok
  defp check_response_type(request), do: redirect(request, "unsupported_response_type")

  defp check_resource(%__MODULE__{params: %{"resource" => given}} = request, resource) do
    if given == resource, do: :ok, else: redirect(request, "invalid_target")
  end

  defp check_resource(_request, _resource), do: :ok

  defp page(message), do: {:error, {:page, message}}

  defp redirect(request, error),
    do: {:error, {:redirect, redirect_to(request, %{"error" => error})}}
end
