defmodule Chat do
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("App starting...")

    children = [
      %{
        id: :chat,
        start:
          {:cowboy, :start_clear,
           [
             :chat,
             %{max_connections: :infinity, socket_opts: [port: 4000]},
             %{max_keepalive: 20_000_000, env: %{dispatch: dispatch()}}
           ]},
        restart: :permanent,
        shutdown: :infinity,
        type: :supervisor
      },
      {Registry, keys: :duplicate, name: Registry.Chat},
      Chat.BotServer
    ]

    opts = [strategy: :one_for_one, name: Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatch do
    :cowboy_router.compile([
      {:_,
       [
         {"/", :cowboy_static, {:file, priv_dir() <> "/static/index.html"}},
         {"/static/[...]", :cowboy_static, {:dir, priv_dir() <> "/static"}},
         {"/ws/[...]", Chat.WSHandler, []}
       ]}
    ])
  end

  defp priv_dir, do: List.to_string(:code.priv_dir(:chat))
end
