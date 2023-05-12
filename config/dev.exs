import Config

config :libcluster,
  topologies: [
    example: [
      strategy: LibCluster.LocalStrategy
    ]
  ]
