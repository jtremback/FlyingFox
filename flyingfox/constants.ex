#these constants are the same for every node on the chain.
defmodule Constants do
  def initial_coins do 2_100_000_000_000_000 end
  def minbond do 2_000_000_000 end
  def min_tx_fee do 5000 end
  def max_bond_block do initial_coins/epoch/signers_per_block end
  def signers_per_block do 100 end
  def empty_account do [amount: 0, bond: 0, wait: {0, 0}, nonce: 0] end #wait={amount, height}
  def epoch do 100 end#amount of time until reveal
  def chances_per_address do 200 end
  def default_peers do [] end
end