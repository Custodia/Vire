defmodule Vire.Ingest.Decoder do
  @moduledoc """
  Decodes FIT files through Garmin's JavaScript SDK, run by `node` from `PATH`
  behind an Erlang port.

  One Node process serves one request at a time; requests queue in the order
  they arrive. A request that runs past its timeout kills the process and
  answers `{:error, :timeout}`, and one answered with anything but a response
  kills it and answers `{:error, {:bad_response, start_of_answer}}`. A process
  that exits fails the request it was serving, and the next request starts a
  new one.
  """

  use GenServer

  require Logger

  @typedoc """
  The SDK's messages grouped by type (`"recordMesgs"`, `"sessionMesgs"`, ...),
  with developer fields named after their descriptions, and the units of the
  record fields and the developer fields by name.
  """
  @type decoded :: %{messages: map(), units: map()}

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Verifies and decodes the bytes of a FIT file.

  Options: `:server`, the decoder to ask, and `:timeout` in milliseconds.
  """
  @spec decode(binary(), keyword()) :: {:ok, decoded()} | {:error, term()}
  def decode(content, opts \\ []) when is_binary(content) do
    server = Keyword.get(opts, :server, __MODULE__)
    timeout = Keyword.get(opts, :timeout, config(:timeout))
    GenServer.call(server, {:decode, content, timeout}, :infinity)
  end

  @doc "The operating-system process id of the running Node process, or `nil`."
  def os_pid(server \\ __MODULE__), do: GenServer.call(server, :os_pid)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    script = Keyword.get_lazy(opts, :script, fn -> config(:script) end)
    {:ok, %{script: script, port: nil, current: nil, queue: :queue.new()}, {:continue, :open}}
  end

  @impl GenServer
  def handle_continue(:open, state), do: {:noreply, open(state)}

  @impl GenServer
  def handle_call({:decode, content, timeout}, from, state) do
    request = Jason.encode!(%{op: "decode", data: Base.encode64(content)})
    state = %{state | queue: :queue.in({from, request, timeout}, state.queue)}
    {:noreply, next(state)}
  end

  def handle_call(:os_pid, _from, %{port: nil} = state), do: {:reply, nil, state}

  def handle_call(:os_pid, _from, %{port: port} = state) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> {:reply, os_pid, state}
      nil -> {:reply, nil, state}
    end
  end

  @impl GenServer
  def handle_info({port, {:data, response}}, %{port: port, current: {from, _ref, timer}} = state) do
    Process.cancel_timer(timer)
    state = %{state | current: nil}

    case result(response) do
      {:bad_response, response} ->
        Logger.warning("FIT decoder answered something other than a response")
        GenServer.reply(from, {:error, {:bad_response, response}})
        {:noreply, state |> kill() |> next()}

      result ->
        GenServer.reply(from, result)
        {:noreply, next(state)}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("FIT decoder exited with status #{status}")
    state = fail_current(state, {:decoder_exited, status})
    {:noreply, next(%{state | port: nil})}
  end

  def handle_info({:timeout, ref}, %{current: {_from, ref, _timer}} = state) do
    state = state |> fail_current(:timeout) |> kill()
    {:noreply, next(state)}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state), do: kill(state)

  defp next(%{current: nil, port: nil} = state) do
    if :queue.is_empty(state.queue), do: state, else: state |> open() |> send_next()
  end

  defp next(%{current: nil} = state), do: send_next(state)
  defp next(state), do: state

  defp send_next(state) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        state

      {{:value, {from, _request, _timeout}}, queue} when state.port == nil ->
        GenServer.reply(from, {:error, :decoder_unavailable})
        next(%{state | queue: queue})

      {{:value, {from, request, timeout}}, queue} ->
        if command(state.port, request) do
          ref = make_ref()
          timer = Process.send_after(self(), {:timeout, ref}, timeout)
          %{state | queue: queue, current: {from, ref, timer}}
        else
          state |> Map.put(:port, nil) |> open() |> send_next()
        end
    end
  end

  # A process that died since the last request leaves its port closed before
  # its exit status arrives.
  defp command(port, request) do
    Port.command(port, request)
  rescue
    ArgumentError -> false
  end

  defp open(state) do
    case System.find_executable("node") do
      nil ->
        Logger.error("FIT decoder cannot start: node is not on PATH")
        state

      node ->
        port =
          Port.open({:spawn_executable, node}, [
            :binary,
            :exit_status,
            {:packet, 4},
            args: [state.script],
            cd: Path.dirname(state.script)
          ])

        %{state | port: port}
    end
  end

  defp kill(%{port: nil} = state), do: state

  defp kill(%{port: port} = state) do
    with {:os_pid, os_pid} <- Port.info(port, :os_pid) do
      Port.close(port)
      System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
    end

    %{state | port: nil}
  end

  defp fail_current(%{current: nil} = state, _reason), do: state

  defp fail_current(%{current: {from, _ref, timer}} = state, reason) do
    Process.cancel_timer(timer)
    GenServer.reply(from, {:error, reason})
    %{state | current: nil}
  end

  defp result(response) do
    case Jason.decode(response) do
      {:ok, %{"ok" => true, "messages" => messages, "units" => units}} ->
        {:ok, %{messages: messages, units: units}}

      {:ok, %{"ok" => false, "error" => error}} when is_binary(error) ->
        {:error, error}

      _other ->
        {:bad_response, binary_part(response, 0, min(byte_size(response), 200))}
    end
  end

  defp config(key), do: Application.fetch_env!(:vire, __MODULE__) |> Keyword.fetch!(key)
end
