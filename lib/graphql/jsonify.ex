
# # Temporary hack to allow encoding user data as JSON scalar
# defimpl Jason.Encoder, for: [Bonfire.Data.Identity.Accounted, Bonfire.Data.Identity.Account, Bonfire.Data.Identity.User, Bonfire.Data.Identity.Character, Bonfire.Data.Social.Profile] do
#   def encode(struct, opts) do
#     # IO.inspect(input: struct)

#     Map.from_struct(struct)
#     |>
#     Map.drop([:__meta__])
#     |>
#     Enum.reduce(%{}, fn
#       ({k, %Ecto.Association.NotLoaded{}}, acc) -> acc
#       # ({__meta__, _}, acc) -> acc
#       ({k, %Bonfire.Data.Social.Profile{} = v}, acc) -> Map.put(acc, k, v)
#       ({k, %Bonfire.Data.Identity.Character{} = v}, acc) -> Map.put(acc, k, v)
#       ({k, %{__struct__: _} = sub_struct}, acc) -> acc #Map.put(acc, k, Jason.encode!(sub_struct))
#       ({k, v}, acc) ->
#         Map.put(acc, k, v)
#       (_, acc) ->
#        acc
#     end)
#     # |> IO.inspect()
#     |> Jason.Encode.map(opts)
#   end
# end
