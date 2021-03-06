defmodule Logger.Watcher do
  @moduledoc false

  require Logger
  use GenServer

  @doc """
  Starts a watcher server.

  This is useful when there is a need to start a handler
  outside of the handler supervision tree.
  """
  def start_link(triplet) do
    GenServer.start_link(__MODULE__, triplet)
  end

  ## Callbacks

  @doc false
  def init({mod, handler, args}) do
    Process.flag(:trap_exit, true)

    case :gen_event.delete_handler(mod, handler, :ok) do
      {:error, :module_not_found} ->
        case :gen_event.add_sup_handler(mod, handler, args) do
          :ok ->
            {:ok, {mod, handler}}

          {:error, :ignore} ->
            # Can't return :ignore as a transient child under a one_for_one.
            # Instead return ok and then immediately exit normally - using a fake
            # message.
            send(self(), {:gen_event_EXIT, handler, :normal})
            {:ok, {mod, handler}}

          {:error, reason} ->
            {:stop, reason}
        end

      _ ->
        init({mod, handler, args})
    end
  end

  @doc false
  def handle_info({:gen_event_EXIT, handler, reason}, {_, handler} = state)
      when reason in [:normal, :shutdown] do
    {:stop, reason, state}
  end

  def handle_info({:gen_event_EXIT, handler, reason}, {mod, handler} = state) do
    message = [
      ":gen_event handler ",
      inspect(handler),
      " installed at ",
      inspect(mod),
      ?\n,
      "** (exit) ",
      format_exit(reason)
    ]

    _ = Logger.error(message)
    {:stop, reason, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def terminate(_reason, {mod, handler}) do
    # On terminate we remove the handler, this makes the
    # process sync, allowing existing messages to be flushed
    :gen_event.delete_handler(mod, handler, :ok)
    :ok
  end

  defp format_exit({:EXIT, reason}), do: Exception.format_exit(reason)
  defp format_exit(reason), do: Exception.format_exit(reason)
end
