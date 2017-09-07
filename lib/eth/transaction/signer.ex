defmodule ETH.Transaction.Signer do
  import ETH.Utils

  alias ETH.Transaction.Parser, as: TransactionParser

  def hash_transaction(transaction, include_signature \\ true)
  def hash_transaction(transaction = %{
    to: _to, value: _value, data: _data, gas_price: _gas_price, gas_limit: _gas_limit,
    nonce: _nonce
  }, include_signature) do
    chain_id = get_chain_id(Map.get(transaction, :v, <<28>>), Map.get(transaction, :chain_id))

    transaction
    |> Map.delete(:chain_id)
    |> TransactionParser.to_list
    |> List.insert_at(-1, chain_id)
    |> hash_transaction_list(include_signature)
  end
  # def hash_transaction(transaction=%{}, include_signature) do # TODO: check if this is necessary
  #   chain_id = get_chain_id(Map.get(transaction, :v, <<28>>), Map.get(transaction, :chain_id))
  #
  #   transaction
  #   |> Map.delete(:chain_id)
  #   |> TransactionParser.to_list
  #   |> List.insert_at(-1, chain_id)
  #   |> hash_transaction_list(include_signature)
  # end

  def hash_transaction_list(
    transaction_list, include_signature \\ true
  ) when is_list(transaction_list) do # NOTE: usage is generally internal
    target_list = case include_signature do
      true -> transaction_list
      false ->
        # EIP155 spec:
        # when computing the hash of a transaction for purposes of signing or recovering,
        # instead of hashing only the first six elements (ie. nonce, gasprice, startgas, to, value, data),
        # hash nine elements, with v replaced by CHAIN_ID, r = 0 and s = 0
        list = Enum.take(transaction_list, 6)
        v = Enum.at(transaction_list, 6) || <<28>>
        chain_id = get_chain_id(v, Enum.at(transaction_list, 9))
        if chain_id > 0, do: list ++ [chain_id, 0, 0], else: list
    end

    target_list
    |> ExRLP.encode
    |> keccak256
  end

  def sign_transaction(transaction, private_key) when is_map(transaction) do
    transaction
    |> ETH.Transaction.to_list
    |> sign_transaction_list(private_key)
    |> ExRLP.encode
  end

  def sign_transaction_list(transaction_list = [
    nonce, gas_price, gas_limit, to, value, data, v, r, s
  ], << private_key :: binary-size(32) >>) do
    to_signed_transaction_list(transaction_list, private_key)
  end
  def sign_transaction_list(transaction_list = [
    nonce, gas_price, gas_limit, to, value, data, v, r, s
  ], << encoded_private_key :: binary-size(64) >>) do
    decoded_private_key = Base.decode16!(encoded_private_key, case: :mixed)
    to_signed_transaction_list(transaction_list, decoded_private_key)
  end

  defp to_signed_transaction_list(transaction_list = [
    nonce, gas_price, gas_limit, to, value, data, v, r, s
  ], << private_key :: binary-size(32) >>) do # NOTE: this part is problematic
    chain_id = get_chain_id(v, Enum.at(transaction_list, 9))
    message_hash = hash_transaction_list(transaction_list, false)

    [signature: signature, recovery: recovery] = secp256k1_signature(message_hash, private_key)

    << sig_r :: binary-size(32) >> <> << sig_s :: binary-size(32) >> = signature
    initial_v = recovery + 27

    sig_v = if chain_id > 0, do: initial_v + (chain_id * 2 + 8), else: initial_v

    [nonce, gas_price, gas_limit, to, value, data, <<sig_v>>, sig_r, sig_s]
  end
end
