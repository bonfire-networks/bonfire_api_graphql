defmodule Bonfire.API.MastoCompatible do
  use Bonfire.UI.Common.Web, :controller

  # TODO? to avoid clients failing because they expect int IDs
  # iex> Needle.ULID.dump("01HV1RNDM8ZNPV3Z3GR2CVBB1B") ~> :binary.decode_unsigned()
  # 2070500209547882921559307103705082923
  # iex> :binary.encode_unsigned(2070500209547882921559307103705082923) |> Needle.ULID.load()
  # {:ok, "01HV1RNDM8ZNPV3Z3GR2CVBB1B"}
end
