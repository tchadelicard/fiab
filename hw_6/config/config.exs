use Mix.Config

[
  imt_order: [
    common: %{
      nb_products: 10_000,
      nb_stores: 200,
    },
    front: %{
      rate: 1, # Number of calls per second from front to OMS
      duration: 30, # Time during which the simulation runs in seconds
      weights: %{
        order: 12,
        stats: 0,
      },
    },
    back: %{
      stats_file_interval: 10, # Time between each file generation in seconds
      stocks_file_interval: 15, # Time between each file generation in seconds
    }
 ],
]
