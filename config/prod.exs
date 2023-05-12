import Config

config :logger, level: :info

config :libcluster,
  topologies: [
    k8s_chat: [
      strategy: Elixir.Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "chat-nodes",
        application_name: "chat",
        polling_interval: 3_000
      ]
    ]
  ]
