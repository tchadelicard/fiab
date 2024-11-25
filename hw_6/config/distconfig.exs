[
  imt_order: [
    http: {"127.0.0.1", DistMix.add_nodei(9089)}, #89 so :lb start on 90
    nodes: Application.get_env(:distmix, :nodes),
    app_type: (case DistMix.nodei() do
      #1 -> :lb
      1 -> :back
      2 -> :statsdb
      # Start front at the end
      x -> if(x == Enum.count(Application.get_env(:distmix, :nodes)))
        do :front
        else :sim
      end
    end)
  ],
]
