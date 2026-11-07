defmodule Vire.Ingest.Garmin do
  @moduledoc """
  A client for Garmin's Personal API, acting for one user through their
  provider connection.

  The connection's API key is exchanged for a bearer token, which lives 24
  hours. The token is cached per connection in memory and exchanged again once
  less than an hour of it remains. A request Garmin answers 401 to is sent
  once more with a newly exchanged token.

  Responses of 429 and 5xx, and requests that get no answer, are retried with
  exponential back-off, up to three times. A request that still fails answers
  `{:error, reason}`:

    * `{:key_refused, status}`: the token endpoint refused the key.
    * `{:status, status}`: another endpoint answered with that status.
    * `{:transport, reason}`: no answer arrived.
    * `:unexpected_body`: a search answered with something other than a list.
    * `:no_fit_file`: a downloaded archive holds no `.fit` file.

  Neither the key nor a token appears in an answer, an error or a log line.
  """

  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Ingest.Garmin.Token
  alias Vire.Ingest.Garmin.TokenCache

  @token_path "/personalapitoken-service/personal-api/personal-api-key/token"
  @search_path "/activitylist-service/activities/search/activities"
  @download_path "/download-service/files/activity/:id"
  @page_size 99
  @lifetime 24 * 3600
  @renew_within 3600
  @max_retries 3

  @doc """
  A bearer token for the scope's Garmin connection: the cached one while more
  than an hour of it remains, otherwise one newly exchanged from the key.
  """
  @spec token(Scope.t(), ProviderConnection.t()) :: {:ok, Token.t()} | {:error, term()}
  def token(%Scope{user: %{id: user_id}}, %ProviderConnection{user_id: user_id} = connection) do
    now = System.os_time(:second)

    case TokenCache.fetch(connection) do
      {:ok, %Token{expires_at: expires_at} = token} when expires_at - now > @renew_within ->
        {:ok, token}

      _expiring_or_missing ->
        exchange(connection, now)
    end
  end

  @doc """
  The summaries of the activities whose local start date lies from `first` to
  `last`, both included, as maps with Garmin's field names. Follows the pages
  until one comes back short.
  """
  @spec search_activities(Scope.t(), ProviderConnection.t(), Date.t(), Date.t()) ::
          {:ok, [map()]} | {:error, term()}
  def search_activities(%Scope{} = scope, connection, %Date{} = first, %Date{} = last) do
    with {:ok, token} <- token(scope, connection) do
      params = [
        startDate: Date.to_iso8601(first),
        endDate: Date.to_iso8601(last),
        # Oldest first, so an activity recorded while the pages are read lands
        # past the last page instead of shifting the ones still to come.
        sortOrder: "asc",
        limit: @page_size
      ]

      search_pages(connection, token, params, 0, [])
    end
  end

  @doc """
  The bytes of the `.fit` file Garmin keeps for the activity with Garmin's id
  `activity_id`, taken out of the ZIP the download endpoint answers with.
  """
  @spec download_activity_file(Scope.t(), ProviderConnection.t(), String.t() | integer()) ::
          {:ok, binary()} | {:error, term()}
  def download_activity_file(%Scope{} = scope, connection, activity_id) do
    with {:ok, token} <- token(scope, connection),
         {:ok, archive, _token} <-
           authorized(connection, token,
             method: :get,
             url: @download_path,
             path_params: [id: activity_id],
             decode_body: false
           ) do
      fit_from_zip(archive)
    end
  end

  defp exchange(connection, now) do
    case request(
           method: :post,
           url: @token_path,
           auth: "ApiKey " <> connection.credential,
           headers: [accept: "*/*"]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        value = String.trim(body)
        token = %Token{value: value, expires_at: expiry(value) || now + @lifetime}
        TokenCache.put(connection, token)
        {:ok, token}

      {:ok, %Req.Response{status: status}} when status in [400, 401, 403] ->
        TokenCache.delete(connection)
        {:error, {:key_refused, status}}

      other ->
        failure(other)
    end
  end

  defp expiry(jwt) do
    with [_header, payload | _] <- String.split(jwt, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_integer(exp) <- Jason.decode(json) do
      exp
    else
      _unreadable -> nil
    end
  end

  defp search_pages(connection, token, params, start, pages) do
    case authorized(connection, token,
           method: :get,
           url: @search_path,
           params: [{:start, start} | params]
         ) do
      {:ok, page, token} when is_list(page) and length(page) == @page_size ->
        search_pages(connection, token, params, start + @page_size, [page | pages])

      {:ok, page, _token} when is_list(page) ->
        {:ok, [page | pages] |> Enum.reverse() |> Enum.concat()}

      {:ok, _other, _token} ->
        {:error, :unexpected_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authorized(connection, %Token{value: value} = token, options, renew? \\ true) do
    case request([{:auth, {:bearer, value}} | options]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body, token}

      {:ok, %Req.Response{status: 401}} when renew? ->
        TokenCache.delete(connection)

        with {:ok, fresh} <- exchange(connection, System.os_time(:second)) do
          authorized(connection, fresh, options, false)
        end

      {:ok, %Req.Response{status: 401}} ->
        TokenCache.delete(connection)
        {:error, {:status, 401}}

      other ->
        failure(other)
    end
  end

  defp failure({:ok, %Req.Response{status: status}}), do: {:error, {:status, status}}
  defp failure({:error, %Req.TransportError{reason: reason}}), do: {:error, {:transport, reason}}
  defp failure({:error, exception}), do: {:error, {:transport, exception.__struct__}}

  defp fit_from_zip(archive) do
    with {:ok, entries} <- :zip.unzip(archive, [:memory]),
         {_name, fit} <- Enum.find(entries, &fit_entry?/1) do
      {:ok, fit}
    else
      _no_fit -> {:error, :no_fit_file}
    end
  end

  defp fit_entry?({name, _content}),
    do: name |> List.to_string() |> String.downcase() |> String.ends_with?(".fit")

  defp request(options) do
    config = Application.fetch_env!(:vire, __MODULE__)

    [
      base_url: Keyword.fetch!(config, :base_url),
      retry: &transient?/2,
      max_retries: @max_retries
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Keyword.merge(options)
    |> Req.request()
  end

  defp transient?(_request, %Req.Response{status: status}), do: status == 429 or status >= 500

  defp transient?(_request, %Req.TransportError{reason: reason}),
    do: reason in [:timeout, :econnrefused, :closed]

  defp transient?(_request, _other), do: false
end
